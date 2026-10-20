(** ASGARD-5877: Mach-O container reader.

    See [Macho_image] for the interface. *)

type magic =
  | MH_MAGIC
  | MH_MAGIC_64
  | MH_CIGAM
  | MH_CIGAM_64

type section = {
  sectname : string;
  segname : string;
  addr : int64;
  size : int64;
  offset : int64;
  flags : int32;
}

type segment = {
  is_64 : bool;
  segname : string;
  vmaddr : int64;
  vmsize : int64;
  fileoff : int64;
  filesize : int64;
  nsects : int;
  flags : int32;
  sections : section list;
}

type routines_command = {
  is_64 : bool;
  cmd : int32;
  cmdsize : int32;
  init_address : int64;
  init_size : int64;
  routines_offset : int64;
  routines_size : int64;
}

type other_command = {
  cmd_value : int32;
  cmd_size : int32;
  file_offset : int;
}

type load_command =
  | Segment of segment
  | Routines of routines_command
  | Other of other_command

type t = {
  bytes : bytes;
  magic : magic;
  is_64 : bool;
  cpu_type : int32;
  cpu_subtype : int32;
  file_type : int32;
  flags : int32;
  ncmds : int;
  sizeofcmds : int;
  load_commands : load_command list;
}

exception Parse_error of string

let mh_magic = 0xfeedfacel
let mh_cigam = 0xcefaedfel
let mh_magic_64 = 0xfeedfacfl
let mh_cigam_64 = 0xcffaedfel

let lc_segment = 0x1
let lc_segment_64 = 0x19
let lc_routines = 0x22
let lc_routines_64 = 0x33

let header_size_32 = 28
let header_size_64 = 32
let segment_cmd_size_32 = 56
let segment_cmd_size_64 = 72
let section_size_32 = 68
let section_size_64 = 80
let routines_cmd_size_32 = 24
let routines_cmd_size_64 = 32

let fail fmt = Printf.ksprintf (fun msg -> raise (Parse_error msg)) fmt

let check_range b off len what =
  if off < 0 || len < 0 || off > Bytes.length b - len then
    fail "%s out of range (offset %d, length %d, image size %d)" what off len (Bytes.length b)

let u32 b off =
  check_range b off 4 "32-bit field";
  (* the field is unsigned, so the sign bit must not be propagated *)
  Int32.to_int (Bytes.get_int32_le b off) land 0xFFFFFFFF

let u64 b off =
  check_range b off 8 "64-bit field";
  Bytes.get_int64_le b off

let i32 b off =
  check_range b off 4 "32-bit field";
  Bytes.get_int32_le b off

(** Mach-O names are fixed-size NUL-terminated, space-padded fields. *)
let read_name b off len =
  check_range b off len "name field";
  let s = Bytes.sub_string b off len in
  let s = match String.index_opt s '\000' with Some i -> String.sub s 0 i | None -> s in
  String.trim s

let parse_magic raw =
  if Int32.equal raw mh_magic then (MH_MAGIC, false)
  else if Int32.equal raw mh_magic_64 then (MH_MAGIC_64, true)
  else if Int32.equal raw mh_cigam then (MH_CIGAM, false)
  else if Int32.equal raw mh_cigam_64 then (MH_CIGAM_64, true)
  else fail "not a Mach-O image (magic 0x%08lx)" raw

let parse_section b ~is_64 off =
  let sectname = read_name b off 16 in
  let segname = read_name b (off + 16) 16 in
  if is_64 then begin
    let addr = u64 b (off + 32) in
    let size = u64 b (off + 40) in
    let offset = Int64.of_int (u32 b (off + 48)) in
    let flags = i32 b (off + 64) in
    { sectname; segname; addr; size; offset; flags }
  end else begin
    let addr = Int64.of_int (u32 b (off + 32)) in
    let size = Int64.of_int (u32 b (off + 36)) in
    let offset = Int64.of_int (u32 b (off + 40)) in
    let flags = i32 b (off + 56) in
    { sectname; segname; addr; size; offset; flags }
  end

let parse_segment b ~is_64 off =
  let segname = read_name b (off + 8) 16 in
  let vmaddr, vmsize, fileoff, filesize, nsects, flags =
    if is_64 then
      ( u64 b (off + 24),
        u64 b (off + 32),
        u64 b (off + 40),
        u64 b (off + 48),
        u32 b (off + 64),
        i32 b (off + 68) )
    else
      ( Int64.of_int (u32 b (off + 24)),
        Int64.of_int (u32 b (off + 28)),
        Int64.of_int (u32 b (off + 32)),
        Int64.of_int (u32 b (off + 36)),
        u32 b (off + 48),
        i32 b (off + 52) )
  in
  let section_size = if is_64 then section_size_64 else section_size_32 in
  let base = if is_64 then off + segment_cmd_size_64 else off + segment_cmd_size_32 in
  let sections =
    List.init nsects (fun i -> parse_section b ~is_64 (base + (i * section_size)))
  in
  { is_64; segname; vmaddr; vmsize; fileoff; filesize; nsects; flags; sections }

let parse_routines b ~is_64 off =
  let init_address, init_size, routines_offset, routines_size =
    if is_64 then
      ( u64 b (off + 8),
        u64 b (off + 16),
        Int64.of_int (u32 b (off + 24)),
        Int64.of_int (u32 b (off + 28)) )
    else
      ( Int64.of_int (u32 b (off + 8)),
        Int64.of_int (u32 b (off + 12)),
        Int64.of_int (u32 b (off + 16)),
        Int64.of_int (u32 b (off + 20)) )
  in
  { is_64;
    cmd = Int32.of_int (if is_64 then lc_routines_64 else lc_routines);
    cmdsize = Int32.of_int (if is_64 then routines_cmd_size_64 else routines_cmd_size_32);
    init_address;
    init_size;
    routines_offset;
    routines_size }

let parse_load_command b ~off =
  let cmd = i32 b off in
  let cmdsize = i32 b (off + 4) in
  let code = Int32.to_int cmd in
  if code = lc_segment then Segment (parse_segment b ~is_64:false off)
  else if code = lc_segment_64 then Segment (parse_segment b ~is_64:true off)
  else if code = lc_routines then Routines (parse_routines b ~is_64:false off)
  else if code = lc_routines_64 then Routines (parse_routines b ~is_64:true off)
  else Other { cmd_value = cmd; cmd_size = cmdsize; file_offset = off }

let of_bytes b =
  check_range b 0 4 "Mach-O magic";
  let raw = Bytes.get_int32_le b 0 in
  let magic, is_64 = parse_magic raw in
  let header_size = if is_64 then header_size_64 else header_size_32 in
  check_range b 0 header_size "Mach-O header";
  let cpu_type = i32 b 4 in
  let cpu_subtype = i32 b 8 in
  let file_type = i32 b 12 in
  let ncmds = u32 b 16 in
  let sizeofcmds = u32 b 20 in
  let flags = i32 b 24 in
  check_range b header_size sizeofcmds "load commands";
  let rec loop i off acc =
    if i >= ncmds then List.rev acc
    else begin
      check_range b off 8 "load command header";
      let cmdsize = u32 b (off + 4) in
      if cmdsize < 8 then fail "load command %d has an invalid cmdsize (%d)" i cmdsize;
      check_range b off cmdsize "load command";
      let lc = parse_load_command b ~off in
      loop (i + 1) (off + cmdsize) (lc :: acc)
    end
  in
  { bytes = b;
    magic;
    is_64;
    cpu_type;
    cpu_subtype;
    file_type;
    flags;
    ncmds;
    sizeofcmds;
    load_commands = loop 0 header_size [] }

let of_file path =
  if not (Sys.file_exists path) then fail "file not found: %s" path;
  let ic = try open_in_bin path with Sys_error msg -> fail "%s" msg in
  let len = in_channel_length ic in
  let b = Bytes.create len in
  really_input ic b 0 len;
  close_in ic;
  of_bytes b

let load_commands img = img.load_commands

let segments img =
  List.filter_map (function Segment s -> Some s | _ -> None) (load_commands img)

let segment img name = List.find_opt (fun s -> s.segname = name) (segments img)

let section img segname sectname =
  List.find_opt
    (fun (s : section) -> s.segname = segname && s.sectname = sectname)
    (match segment img segname with Some s -> s.sections | None -> [])

let routines_commands img =
  List.filter_map (function Routines r -> Some r | _ -> None) (load_commands img)

let section_data img sect =
  let off = sect.offset in
  let len = sect.size in
  if Int64.compare len 0L < 0 || Int64.compare off (Int64.of_int (Bytes.length img.bytes)) >= 0 then
    fail "section %s,%s extends past the end of the image" sect.segname sect.sectname;
  let off = Int64.to_int off in
  let len = Int64.to_int len in
  check_range img.bytes off len "section contents";
  Bytes.sub img.bytes off len
