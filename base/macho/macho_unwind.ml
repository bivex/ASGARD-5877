(** ASGARD-5877: compact unwind analysis for Mach-O images.

    See [Macho_unwind] for the interface. *)

type routine = {
  address : int64;
  size : int64;
  unwind_info_offset : int64;
  unwind_info_size : int64;
}

(** An inconsistency of the compact unwind information.  An image that carries
    no unwind information at all is not inconsistent: the protector compiles the
    protected binary without unwind tables, and the layout of such an image is
    reported as [No_unwind_info] instead. *)
type issue =
  | Missing_text_section
  | Unsorted_routines of { previous : int64; current : int64 }
  | Address_outside_text of { routine : routine; text_start : int64; text_end : int64 }
  | Size_overruns_next_routine of { routine : routine; limit : int64 }
  | Unwind_info_out_of_range of { routine : routine; section_size : int64 }

type section_index = {
  version : int32;
  index_count : int;
}

type layout =
  | Routine_table of Macho_image.routines_command list
  | Section_index of section_index
  | No_unwind_info

type report = {
  routines : routine list;
  issues : issue list;
  layout : layout;
  text_start : int64;
  text_end : int64;
  unwind_info_size : int64;
}

let routine_entry_size_32 = 16
let routine_entry_size_64 = 24

(** The routine entry fields are unsigned. *)
let u32 b off =
  Int64.of_int (Int32.to_int (Bytes.get_int32_le b off) land 0xFFFFFFFF)

let decode_entry b ~is_64 off =
  if is_64 then begin
    let address = Bytes.get_int64_le b off in
    let size = Bytes.get_int64_le b (off + 8) in
    let unwind_info_offset = u32 b (off + 16) in
    let unwind_info_size = u32 b (off + 20) in
    { address; size; unwind_info_offset; unwind_info_size }
  end else begin
    let address = u32 b off in
    let size = u32 b (off + 4) in
    let unwind_info_offset = u32 b (off + 8) in
    let unwind_info_size = u32 b (off + 12) in
    { address; size; unwind_info_offset; unwind_info_size }
  end

let entries_of_command (img : Macho_image.t) (rc : Macho_image.routines_command) =
  let b = img.bytes in
  let entry_size = if rc.is_64 then routine_entry_size_64 else routine_entry_size_32 in
  let count = Int64.div rc.routines_size (Int64.of_int entry_size) in
  let count = Int64.to_int count in
  let base = Int64.to_int rc.routines_offset in
  (* A routine table that does not fit inside the image is a malformed image.
     Reporting it beats silently dropping the table. *)
  if count < 0 || base < 0 || base > Bytes.length b - (count * entry_size) then
    raise
      (Macho_image.Parse_error
         (Printf.sprintf
            "the routine table of LC_ROUTINES%s (offset %d, size %Ld) does not fit into the image"
            (if rc.is_64 then "64" else "")
            base rc.routines_size));
  List.init count (fun i -> decode_entry b ~is_64:rc.is_64 (base + (i * entry_size)))

let decode_routines img =
  List.concat_map (entries_of_command img) (Macho_image.routines_commands img)

let routine_for_address img address =
  List.find_opt
    (fun r ->
      Int64.compare r.address address <= 0
      && Int64.compare address (Int64.add r.address r.size) < 0)
    (decode_routines img)

(** The [unwind_info_section_header] that the linker puts at the start of
    [__TEXT,__unwind_info] when it does not emit a routine table. *)
let section_index_layout (img : Macho_image.t) =
  match Macho_image.section img "__TEXT" "__unwind_info" with
  | None -> None
  | Some sect ->
      let off = Int64.to_int sect.offset in
      let len = Int64.to_int sect.size in
      if len < 28 || off < 0 || off > Bytes.length img.bytes - 28 then None
      else begin
        let b = img.bytes in
        let version = Bytes.get_int32_le b off in
        let index_count = Int32.to_int (Bytes.get_int32_le b (off + 24)) in
        if Int32.to_int version <> 1 || index_count < 0 then None
        else Some { version; index_count }
      end

let layout (img : Macho_image.t) =
  let cmds = Macho_image.routines_commands img in
  if cmds <> [] then Routine_table cmds
  else match section_index_layout img with
    | Some s -> Section_index s
    | None -> No_unwind_info

(** The first address a routine may not reach: the next routine, or the end
    of [__TEXT,__text]. *)
let extent_limit routines index text_end =
  let next =
    if index + 1 < Array.length routines then routines.(index + 1).address else text_end
  in
  if Int64.compare next text_end > 0 then text_end else next

let check img =
  let text = Macho_image.section img "__TEXT" "__text" in
  let unwind = Macho_image.section img "__TEXT" "__unwind_info" in
  let text_start = match text with Some s -> s.Macho_image.addr | None -> 0L in
  let text_end =
    match text with
    | Some s -> Int64.add s.Macho_image.addr s.Macho_image.size
    | None -> 0L
  in
  let unwind_info_size = match unwind with Some s -> s.Macho_image.size | None -> 0L in
  let routines = Array.of_list (decode_routines img) in
  let issues = ref [] in
  let add i = issues := i :: !issues in
  if text = None then add Missing_text_section;
  (* An image without an unwind info section is not inconsistent: there is no
     routine table that could disagree with the code.  The absence is reported
     through the layout, not as an issue. *)
  let rec sorted prev i =
    if i < Array.length routines then begin
      let address = routines.(i).address in
      (match prev with
      | Some p when Int64.compare p address > 0 ->
          add (Unsorted_routines { previous = p; current = address })
      | _ -> ());
      sorted (Some address) (i + 1)
    end
  in
  sorted None 0;
  for i = 0 to Array.length routines - 1 do
    let r = routines.(i) in
    if text <> None then begin
      if Int64.compare r.address text_start < 0
         || Int64.compare r.address text_end >= 0
      then add (Address_outside_text { routine = r; text_start; text_end });
      let limit = extent_limit routines i text_end in
      if Int64.compare (Int64.add r.address r.size) limit > 0
         && Int64.compare r.address limit < 0
      then add (Size_overruns_next_routine { routine = r; limit })
    end;
    if unwind <> None then
      if
        Int64.compare
          (Int64.add r.unwind_info_offset r.unwind_info_size)
          unwind_info_size
        > 0
      then add (Unwind_info_out_of_range { routine = r; section_size = unwind_info_size })
  done;
  { routines = Array.to_list routines;
    issues = List.rev !issues;
    layout = layout img;
    text_start;
    text_end;
    unwind_info_size }

let repair (img : Macho_image.t) report =
  let b = Bytes.copy img.bytes in
  let flat = Array.of_list report.routines in
  let base = ref 0 in
  List.iter
    (fun (rc : Macho_image.routines_command) ->
      let entry_size =
        if rc.is_64 then routine_entry_size_64 else routine_entry_size_32
      in
      let count = List.length (entries_of_command img rc) in
      let table = Int64.to_int rc.routines_offset in
      for i = 0 to count - 1 do
        let idx = !base + i in
        if idx < Array.length flat then begin
          let r = flat.(idx) in
          let limit = extent_limit flat idx report.text_end in
          if Int64.compare r.address limit < 0 then begin
            let clamped = Int64.sub limit r.address in
            if Int64.compare clamped r.size < 0 then begin
              let at = table + (i * entry_size) in
              if rc.is_64 then Bytes.set_int64_le b (at + 8) clamped
              else if Int64.compare clamped (Int64.of_int max_int) <= 0 then
                Bytes.set_int32_le b (at + 4) (Int32.of_int (Int64.to_int clamped))
            end
          end
        end
      done;
      base := !base + count)
    (Macho_image.routines_commands img);
  b

let repair_to_file (img : Macho_image.t) report path =
  let b = repair img report in
  try
    let oc = open_out_bin path in
    output_bytes oc b;
    close_out oc;
    Ok ()
  with Sys_error msg -> Error msg

let format_issue = function
  | Missing_text_section -> "no __TEXT,__text section"
  | Unsorted_routines { previous; current } ->
      Printf.sprintf "routine table is not sorted (0x%Lx after 0x%Lx)" current previous
  | Address_outside_text { routine; text_start; text_end } ->
      Printf.sprintf "routine at 0x%Lx is outside __TEXT,__text [0x%Lx, 0x%Lx)"
        routine.address text_start text_end
  | Size_overruns_next_routine { routine; limit } ->
      Printf.sprintf "routine at 0x%Lx claims %Ld bytes and overruns 0x%Lx"
        routine.address routine.size limit
  | Unwind_info_out_of_range { routine; section_size } ->
      Printf.sprintf "routine at 0x%Lx points at unwind info outside the section (size %Ld)"
        routine.address section_size

let format_layout = function
  | Routine_table cmds ->
      Printf.sprintf "routine table (LC_ROUTINES%s, %d command(s))"
        (match cmds with
        | c :: _ -> if c.Macho_image.is_64 then "64" else ""
        | [] -> "")
        (List.length cmds)
  | Section_index s ->
      Printf.sprintf "section index (unwind_info_section_header v%ld, %d page(s))"
        s.version s.index_count
  | No_unwind_info -> "not emitted (no __TEXT,__unwind_info section)"

let format_report report =
  let buf = Buffer.create 256 in
  Buffer.add_string buf
    (Printf.sprintf "layout: %s\n" (format_layout report.layout));
  Buffer.add_string buf
    (Printf.sprintf "routines: %d\n" (List.length report.routines));
  Buffer.add_string buf
    (Printf.sprintf "__TEXT,__text: [0x%Lx, 0x%Lx)\n" report.text_start report.text_end);
  (match report.layout with
  | No_unwind_info ->
      Buffer.add_string buf "__TEXT,__unwind_info: absent\n"
  | _ ->
      Buffer.add_string buf
        (Printf.sprintf "__TEXT,__unwind_info: %Ld bytes\n" report.unwind_info_size));
  Buffer.add_string buf (Printf.sprintf "issues: %d\n" (List.length report.issues));
  List.iter
    (fun i -> Buffer.add_string buf (Printf.sprintf "  - %s\n" (format_issue i)))
    report.issues;
  Buffer.contents buf
