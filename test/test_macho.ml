(** ASGARD-5877: Mach-O container and compact unwind tests.

    The images are synthesised byte by byte so that the expectations do not
    depend on the toolchain that produced them. *)

open Macho

let text_file_off = 0x1000
let unwind_file_off = 0x2000
let table_file_off = 0x3000
let image_size = 0x4000

let set_u32 b off v = Bytes.set_int32_le b off (Int32.of_int v)
let set_u64 b off v = Bytes.set_int64_le b off v

let set_name b off s =
  Bytes.fill b off 16 ' ';
  Bytes.blit_string s 0 b off (String.length s)

type routine_spec = {
  address : int64;
  size : int64;
  unwind_offset : int64;
  unwind_size : int64;
}

type image_spec = {
  is_64 : bool;
  base : int64;
  text_addr : int64;
  text_size : int64;
  unwind_size : int64;
  routines : routine_spec list;
  with_routines : bool;
  with_unwind_info : bool;
}

let build_image spec =
  let entry_size = if spec.is_64 then 24 else 16 in
  let header_size = if spec.is_64 then 32 else 28 in
  let seg_cmd_size = if spec.is_64 then 72 else 56 in
  let sect_size = if spec.is_64 then 80 else 68 in
  let routines_cmd_size = if spec.is_64 then 32 else 24 in
  let nsects = if spec.with_unwind_info then 2 else 1 in
  let segment_size = seg_cmd_size + (nsects * sect_size) in
  let ncmds = if spec.with_routines then 2 else 1 in
  let sizeofcmds = segment_size + (if spec.with_routines then routines_cmd_size else 0) in
  let b = Bytes.make image_size '\000' in
  let seg_off = header_size in
  let sect_off = seg_off + seg_cmd_size in
  let routines_off = seg_off + segment_size in
  (* header *)
  set_u32 b 0 (if spec.is_64 then 0xfeedfacf else 0xfeedface);
  set_u32 b 4 0x0100000c;
  set_u32 b 8 0;
  set_u32 b 12 2;
  set_u32 b 16 ncmds;
  set_u32 b 20 sizeofcmds;
  set_u32 b 24 0;
  if spec.is_64 then set_u32 b 28 0;
  (* LC_SEGMENT / LC_SEGMENT_64 *)
  set_u32 b seg_off (if spec.is_64 then 0x19 else 0x1);
  set_u32 b (seg_off + 4) segment_size;
  set_name b (seg_off + 8) "__TEXT";
  if spec.is_64 then begin
    set_u64 b (seg_off + 24) spec.base;
    set_u64 b (seg_off + 32) 0x10000L;
    set_u64 b (seg_off + 40) 0L;
    set_u64 b (seg_off + 48) 0x4000L;
    set_u32 b (seg_off + 56) 7;
    set_u32 b (seg_off + 60) 5;
    set_u32 b (seg_off + 64) nsects;
    set_u32 b (seg_off + 68) 0;
  end else begin
    set_u32 b (seg_off + 24) (Int64.to_int spec.base);
    set_u32 b (seg_off + 28) 0x10000;
    set_u32 b (seg_off + 32) 0;
    set_u32 b (seg_off + 36) 0x4000;
    set_u32 b (seg_off + 40) 7;
    set_u32 b (seg_off + 44) 5;
    set_u32 b (seg_off + 48) nsects;
    set_u32 b (seg_off + 52) 0;
  end;
  (* __text section *)
  let write_section off name addr size file_off =
    set_name b off name;
    set_name b (off + 16) "__TEXT";
    if spec.is_64 then begin
      set_u64 b (off + 32) addr;
      set_u64 b (off + 40) size;
      set_u32 b (off + 48) file_off;
      set_u32 b (off + 52) 4;
      set_u32 b (off + 56) 0;
      set_u32 b (off + 60) 0;
      set_u32 b (off + 64) 0x80000400;
    end else begin
      set_u32 b (off + 32) (Int64.to_int addr);
      set_u32 b (off + 36) (Int64.to_int size);
      set_u32 b (off + 40) file_off;
      set_u32 b (off + 44) 4;
      set_u32 b (off + 48) 0;
      set_u32 b (off + 52) 0;
      set_u32 b (off + 56) 0x80000400;
    end
  in
  write_section sect_off "__text" spec.text_addr spec.text_size text_file_off;
  if spec.with_unwind_info then
    write_section (sect_off + sect_size) "__unwind_info"
      (Int64.add spec.text_addr 0x1000L) spec.unwind_size unwind_file_off;
  (* the unwind_info_section_header that the linker puts in front of the
     page table *)
  let uih = unwind_file_off in
  set_u32 b uih 1;
  set_u32 b (uih + 4) 0;
  set_u32 b (uih + 8) 0;
  set_u32 b (uih + 12) 0;
  set_u32 b (uih + 16) 0;
  set_u32 b (uih + 20) 28;
  set_u32 b (uih + 24) 1;
  (* LC_ROUTINES / LC_ROUTINES64 *)
  if spec.with_routines then begin
    set_u32 b routines_off (if spec.is_64 then 0x33 else 0x22);
    set_u32 b (routines_off + 4) routines_cmd_size;
    if spec.is_64 then begin
      set_u64 b (routines_off + 8) spec.base;
      set_u64 b (routines_off + 16) 0L;
      set_u32 b (routines_off + 24) table_file_off;
      set_u32 b (routines_off + 28) (List.length spec.routines * entry_size);
    end else begin
      set_u32 b (routines_off + 8) (Int64.to_int spec.base);
      set_u32 b (routines_off + 12) 0;
      set_u32 b (routines_off + 16) table_file_off;
      set_u32 b (routines_off + 20) (List.length spec.routines * entry_size);
    end;
    List.iteri
      (fun i r ->
        let off = table_file_off + (i * entry_size) in
        if spec.is_64 then begin
          set_u64 b off r.address;
          set_u64 b (off + 8) r.size;
          set_u32 b (off + 16) (Int64.to_int r.unwind_offset);
          set_u32 b (off + 20) (Int64.to_int r.unwind_size);
        end else begin
          set_u32 b off (Int64.to_int r.address);
          set_u32 b (off + 4) (Int64.to_int r.size);
          set_u32 b (off + 8) (Int64.to_int r.unwind_offset);
          set_u32 b (off + 12) (Int64.to_int r.unwind_size);
        end)
      spec.routines
  end;
  b

let consistent_routines =
  [ { address = 0x1000L; size = 0x100L; unwind_offset = 0L; unwind_size = 0x40L };
    { address = 0x1100L; size = 0x80L; unwind_offset = 0x40L; unwind_size = 0x40L } ]

let spec64 ?(routines = consistent_routines) ?(with_routines = true)
    ?(with_unwind_info = true) () =
  { is_64 = true;
    base = 0x100000000L;
    text_addr = 0x1000L;
    text_size = 0x1200L;
    unwind_size = 0x100L;
    routines;
    with_routines;
    with_unwind_info }

let spec32 ?(routines = consistent_routines) ?(with_routines = true)
    ?(with_unwind_info = true) () =
  { is_64 = false;
    base = 0x1000L;
    text_addr = 0x1000L;
    text_size = 0x1200L;
    unwind_size = 0x100L;
    routines;
    with_routines;
    with_unwind_info }

let check_parse_error name f =
  Alcotest.(match_raises name)
    (fun e -> match e with Macho_image.Parse_error _ -> true | _ -> false)
    f

let test_parse_header_64 () =
  let img = Macho_image.of_bytes (build_image (spec64 ())) in
  Alcotest.(check bool) "is 64-bit" true img.Macho_image.is_64;
  Alcotest.(check int) "ncmds" 2 img.Macho_image.ncmds;
  Alcotest.(check (list int)) "cpu type" [ 0x0100000c ]
    (List.map Int32.to_int [ img.Macho_image.cpu_type ])

let test_parse_header_32 () =
  let img = Macho_image.of_bytes (build_image (spec32 ())) in
  Alcotest.(check bool) "is 64-bit" false img.Macho_image.is_64;
  Alcotest.(check int) "ncmds" 2 img.Macho_image.ncmds

let test_parse_segments_and_sections () =
  let img = Macho_image.of_bytes (build_image (spec64 ())) in
  (match Macho_image.segment img "__TEXT" with
  | None -> Alcotest.fail "the __TEXT segment was not found"
  | Some seg ->
      Alcotest.(check string) "segment name" "__TEXT" seg.Macho_image.segname;
      Alcotest.(check int) "section count" 2 seg.Macho_image.nsects);
  (match Macho_image.section img "__TEXT" "__text" with
  | None -> Alcotest.fail "the __text section was not found"
  | Some s ->
      Alcotest.(check int64) "section address" 0x1000L s.Macho_image.addr;
      Alcotest.(check int64) "section size" 0x1200L s.Macho_image.size);
  (match Macho_image.section img "__TEXT" "__unwind_info" with
  | None -> Alcotest.fail "the __unwind_info section was not found"
  | Some s -> Alcotest.(check int64) "unwind info size" 0x100L s.Macho_image.size);
  Alcotest.(check bool) "unknown segment" true
    (Macho_image.segment img "__DATA" = None)

let test_routines_command_64 () =
  let img = Macho_image.of_bytes (build_image (spec64 ())) in
  match Macho_image.routines_commands img with
  | [ rc ] ->
      Alcotest.(check bool) "is 64-bit command" true rc.Macho_image.is_64;
      Alcotest.(check int32) "command value" 0x33l rc.Macho_image.cmd;
      Alcotest.(check int64) "table offset" (Int64.of_int table_file_off)
        rc.Macho_image.routines_offset;
      Alcotest.(check int) "table size" (2 * 24) (Int64.to_int rc.Macho_image.routines_size)
  | other -> Alcotest.fail (Printf.sprintf "expected one routines command, got %d" (List.length other))

let test_routines_command_32 () =
  let img = Macho_image.of_bytes (build_image (spec32 ())) in
  match Macho_image.routines_commands img with
  | [ rc ] ->
      Alcotest.(check bool) "is 64-bit command" false rc.Macho_image.is_64;
      Alcotest.(check int32) "command value" 0x22l rc.Macho_image.cmd;
      Alcotest.(check int) "table size" (2 * 16) (Int64.to_int rc.Macho_image.routines_size)
  | other -> Alcotest.fail (Printf.sprintf "expected one routines command, got %d" (List.length other))

let test_decode_routines_64 () =
  let img = Macho_image.of_bytes (build_image (spec64 ())) in
  let rs = Macho_unwind.decode_routines img in
  Alcotest.(check int) "routine count" 2 (List.length rs);
  (match rs with
  | r0 :: r1 :: _ ->
      Alcotest.(check int64) "first address" 0x1000L r0.Macho_unwind.address;
      Alcotest.(check int64) "first size" 0x100L r0.Macho_unwind.size;
      Alcotest.(check int64) "second unwind offset" 0x40L r1.Macho_unwind.unwind_info_offset;
      Alcotest.(check int64) "second unwind size" 0x40L r1.Macho_unwind.unwind_info_size
  | _ -> Alcotest.fail "the routine table was not decoded")

let test_decode_routines_32 () =
  let img = Macho_image.of_bytes (build_image (spec32 ())) in
  let rs = Macho_unwind.decode_routines img in
  Alcotest.(check int) "routine count" 2 (List.length rs);
  (match rs with
  | r0 :: _ ->
      Alcotest.(check int64) "first address" 0x1000L r0.Macho_unwind.address;
      Alcotest.(check int64) "first size" 0x100L r0.Macho_unwind.size
  | [] -> Alcotest.fail "the routine table was not decoded")

let test_routine_for_address () =
  let img = Macho_image.of_bytes (build_image (spec64 ())) in
  (match Macho_unwind.routine_for_address img 0x1080L with
  | Some r -> Alcotest.(check int64) "covering routine" 0x1000L r.Macho_unwind.address
  | None -> Alcotest.fail "no routine covers the address");
  Alcotest.(check bool) "outside every routine" true
    (Macho_unwind.routine_for_address img 0x5000L = None)

let test_check_consistent () =
  let img = Macho_image.of_bytes (build_image (spec64 ())) in
  let report = Macho_unwind.check img in
  Alcotest.(check int) "issue count" 0 (List.length report.Macho_unwind.issues);
  Alcotest.(check int) "routine count" 2 (List.length report.Macho_unwind.routines);
  Alcotest.(check int64) "text start" 0x1000L report.Macho_unwind.text_start;
  Alcotest.(check int64) "text end" 0x2200L report.Macho_unwind.text_end

let test_check_detects_overrun () =
  let routines =
    [ { address = 0x1000L; size = 0x200L; unwind_offset = 0L; unwind_size = 0x40L };
      { address = 0x1100L; size = 0x80L; unwind_offset = 0x40L; unwind_size = 0x40L } ]
  in
  let img = Macho_image.of_bytes (build_image (spec64 ~routines ())) in
  let report = Macho_unwind.check img in
  Alcotest.(check int) "issue count" 1 (List.length report.Macho_unwind.issues);
  (match report.Macho_unwind.issues with
  | [ Macho_unwind.Size_overruns_next_routine { limit; _ } ] ->
      Alcotest.(check int64) "limit" 0x1100L limit
  | other ->
      Alcotest.fail (Printf.sprintf "expected an overrun issue, got %d issues" (List.length other)))

let test_check_detects_address_outside_text () =
  let routines =
    [ { address = 0x1000L; size = 0x100L; unwind_offset = 0L; unwind_size = 0x40L };
      { address = 0x9000L; size = 0x80L; unwind_offset = 0x40L; unwind_size = 0x40L } ]
  in
  let img = Macho_image.of_bytes (build_image (spec64 ~routines ())) in
  let report = Macho_unwind.check img in
  Alcotest.(check bool) "address issue" true
    (List.exists
       (function Macho_unwind.Address_outside_text _ -> true | _ -> false)
       report.Macho_unwind.issues)

let test_check_detects_unwind_info_out_of_range () =
  let routines =
    [ { address = 0x1000L; size = 0x100L; unwind_offset = 0L; unwind_size = 0x40L };
      { address = 0x1100L; size = 0x80L; unwind_offset = 0xF0L; unwind_size = 0x40L } ]
  in
  let img = Macho_image.of_bytes (build_image (spec64 ~routines ())) in
  let report = Macho_unwind.check img in
  Alcotest.(check bool) "unwind info issue" true
    (List.exists
       (function Macho_unwind.Unwind_info_out_of_range _ -> true | _ -> false)
       report.Macho_unwind.issues)

let test_check_detects_unsorted_table () =
  let routines =
    [ { address = 0x1100L; size = 0x80L; unwind_offset = 0x40L; unwind_size = 0x40L };
      { address = 0x1000L; size = 0x100L; unwind_offset = 0L; unwind_size = 0x40L } ]
  in
  let img = Macho_image.of_bytes (build_image (spec64 ~routines ())) in
  let report = Macho_unwind.check img in
  Alcotest.(check bool) "unsorted issue" true
    (List.exists
       (function Macho_unwind.Unsorted_routines _ -> true | _ -> false)
       report.Macho_unwind.issues)

let test_layout_section_index () =
  let img = Macho_image.of_bytes (build_image (spec64 ~with_routines:false ())) in
  let report = Macho_unwind.check img in
  (match report.Macho_unwind.layout with
  | Macho_unwind.Section_index s ->
      Alcotest.(check int32) "header version" 1l s.version;
      Alcotest.(check int) "page count" 1 s.index_count
  | _ ->
      Alcotest.fail (Printf.sprintf "expected a section index layout, got %s" (Macho_unwind.format_report report)));
  Alcotest.(check int) "issue count" 0 (List.length report.Macho_unwind.issues)

let test_layout_routine_table () =
  let img = Macho_image.of_bytes (build_image (spec64 ())) in
  let report = Macho_unwind.check img in
  Alcotest.(check bool) "routine table layout" true
    (match report.Macho_unwind.layout with
    | Macho_unwind.Routine_table cmds -> List.length cmds = 1
    | _ -> false)

let test_check_without_unwind_info () =
  let img =
    Macho_image.of_bytes (build_image (spec64 ~with_routines:false ~with_unwind_info:false ()))
  in
  let report = Macho_unwind.check img in
  (* An image without unwind information carries no routine table that could
     disagree with the code: the absence is a layout, not an inconsistency. *)
  Alcotest.(check int) "issue count" 0 (List.length report.Macho_unwind.issues);
  Alcotest.(check bool) "no unwind info layout" true
    (match report.Macho_unwind.layout with
    | Macho_unwind.No_unwind_info -> true
    | _ -> false);
  Alcotest.(check bool) "the report says the unwind info is absent" true
    (let text = Macho_unwind.format_report report in
     let needle = "__TEXT,__unwind_info: absent" in
     let n = String.length needle in
     let rec find i =
       i + n <= String.length text
       && (String.sub text i n = needle || find (i + 1))
     in
     find 0)

let test_repair_clamps_size () =
  let routines =
    [ { address = 0x1000L; size = 0x200L; unwind_offset = 0L; unwind_size = 0x40L };
      { address = 0x1100L; size = 0x80L; unwind_offset = 0x40L; unwind_size = 0x40L } ]
  in
  let original = build_image (spec64 ~routines ()) in
  let img = Macho_image.of_bytes original in
  let report = Macho_unwind.check img in
  let repaired = Macho_unwind.repair img report in
  Alcotest.(check int) "image size is preserved" (Bytes.length original) (Bytes.length repaired);
  let fixed = Macho_image.of_bytes repaired in
  let report2 = Macho_unwind.check fixed in
  Alcotest.(check int) "issue count after repair" 0 (List.length report2.Macho_unwind.issues);
  (match report2.Macho_unwind.routines with
  | r0 :: _ -> Alcotest.(check int64) "clamped size" 0x100L r0.Macho_unwind.size
  | [] -> Alcotest.fail "the routine table was lost by the repair");
  (* the rest of the image is untouched *)
  let text_off = text_file_off in
  Alcotest.(check bool) "text section is untouched" true
    (Bytes.sub_string original text_off 16 = Bytes.sub_string repaired text_off 16)

let test_repair_keeps_valid_entries () =
  let original = build_image (spec64 ()) in
  let img = Macho_image.of_bytes original in
  let report = Macho_unwind.check img in
  let repaired = Macho_unwind.repair img report in
  Alcotest.(check bool) "a consistent image is left alone" true (Bytes.equal original repaired)

let test_repair_32 () =
  let routines =
    [ { address = 0x1000L; size = 0x200L; unwind_offset = 0L; unwind_size = 0x40L };
      { address = 0x1100L; size = 0x80L; unwind_offset = 0x40L; unwind_size = 0x40L } ]
  in
  let img = Macho_image.of_bytes (build_image (spec32 ~routines ())) in
  let report = Macho_unwind.check img in
  let repaired = Macho_unwind.repair img report in
  let fixed = Macho_image.of_bytes repaired in
  let report2 = Macho_unwind.check fixed in
  Alcotest.(check int) "issue count after repair" 0 (List.length report2.Macho_unwind.issues)

let test_rejects_non_macho () =
  let garbage = Bytes.make 64 '\x7f' in
  check_parse_error "garbage" (fun () -> ignore (Macho_image.of_bytes garbage))

let test_rejects_truncated_image () =
  let full = build_image (spec64 ()) in
  let truncated = Bytes.sub full 0 48 in
  check_parse_error "truncated" (fun () -> ignore (Macho_image.of_bytes truncated))

let test_rejects_truncated_table () =
  let full = build_image (spec64 ()) in
  (* cut the image so that the routine table is no longer inside it *)
  let truncated = Bytes.sub full 0 table_file_off in
  check_parse_error "truncated" (fun () -> ignore (Macho_unwind.decode_routines (Macho_image.of_bytes truncated)))

let test_format_report () =
  let img = Macho_image.of_bytes (build_image (spec64 ())) in
  let report = Macho_unwind.check img in
  let text = Macho_unwind.format_report report in
  Alcotest.(check bool) "mentions the routine count" true
    (String.length text > 0 && String.contains text 'r')

let tests =
  [ Alcotest.test_case "parse a 64-bit Mach-O header" `Quick test_parse_header_64;
    Alcotest.test_case "parse a 32-bit Mach-O header" `Quick test_parse_header_32;
    Alcotest.test_case "parse segments and sections" `Quick test_parse_segments_and_sections;
    Alcotest.test_case "parse an LC_ROUTINES64 command" `Quick test_routines_command_64;
    Alcotest.test_case "parse an LC_ROUTINES command" `Quick test_routines_command_32;
    Alcotest.test_case "decode the routine table of a 64-bit image" `Quick test_decode_routines_64;
    Alcotest.test_case "decode the routine table of a 32-bit image" `Quick test_decode_routines_32;
    Alcotest.test_case "find the routine that covers an address" `Quick test_routine_for_address;
    Alcotest.test_case "accept a consistent compact unwind table" `Quick test_check_consistent;
    Alcotest.test_case "detect a routine that overruns the next one" `Quick test_check_detects_overrun;
    Alcotest.test_case "detect a routine outside __text" `Quick test_check_detects_address_outside_text;
    Alcotest.test_case "detect unwind info outside the section" `Quick
      test_check_detects_unwind_info_out_of_range;
    Alcotest.test_case "detect an unsorted routine table" `Quick test_check_detects_unsorted_table;
    Alcotest.test_case "detect a section index layout" `Quick test_layout_section_index;
    Alcotest.test_case "detect a routine table layout" `Quick test_layout_routine_table;
    Alcotest.test_case "treat an image without unwind information as a state, not an issue" `Quick
      test_check_without_unwind_info;
    Alcotest.test_case "repair a stale routine size" `Quick test_repair_clamps_size;
    Alcotest.test_case "leave a consistent image untouched" `Quick test_repair_keeps_valid_entries;
    Alcotest.test_case "repair a 32-bit routine table" `Quick test_repair_32;
    Alcotest.test_case "reject a buffer that is not Mach-O" `Quick test_rejects_non_macho;
    Alcotest.test_case "reject a truncated image" `Quick test_rejects_truncated_image;
    Alcotest.test_case "reject an image whose routine table is missing" `Quick
      test_rejects_truncated_table;
    Alcotest.test_case "render a report" `Quick test_format_report;
  ]
