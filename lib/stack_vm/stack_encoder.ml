open Vm_ir
open Stack_ir
open Flags

type encrypted_bytecode = {
  bytes : bytes;
  block_offsets : (int, int) Hashtbl.t;
  seed_key : int64;
}

let rotl64 v k =
  let k = k mod 64 in
  Int64.logor (Int64.shift_left v k) (Int64.shift_right_logical v (64 - k))

let step_key key byte_val =
  Int64.add (rotl64 key 3) (Int64.of_int (byte_val lxor 0x5A))

let cond_to_code = function
  | E -> 0 | NE -> 1 | B -> 2 | AE -> 3
  | BE -> 4 | A -> 5 | S -> 6 | NS -> 7
  | L -> 8 | GE -> 9 | LE -> 10 | G -> 11
  | O -> 12 | NO -> 13 | P -> 14 | NP -> 15
  | ALWAYS -> 16

let code_to_cond = function
  | 0 -> E | 1 -> NE | 2 -> B | 3 -> AE
  | 4 -> BE | 5 -> A | 6 -> S | 7 -> NS
  | 8 -> L | 9 -> GE | 10 -> LE | 11 -> G
  | 12 -> O | 13 -> NO | 14 -> P | 15 -> NP
  | _ -> ALWAYS

let add_i16 buf v =
  Buffer.add_char buf (Char.chr (v land 0xFF));
  Buffer.add_char buf (Char.chr ((v lsr 8) land 0xFF))

let add_i32 buf v =
  for i = 0 to 3 do
    Buffer.add_char buf (Char.chr ((v lsr (i * 8)) land 0xFF))
  done

let add_i64 buf v =
  for i = 0 to 7 do
    let b = Int64.to_int (Int64.logand (Int64.shift_right_logical v (i * 8)) 0xFFL) in
    Buffer.add_char buf (Char.chr b)
  done

let encode_op_into buf = function
  | PushImm v ->
      Buffer.add_char buf (Char.chr 0x01);
      add_i64 buf v
  | PushReg idx ->
      Buffer.add_char buf (Char.chr 0x02);
      add_i16 buf idx
  | PopReg idx ->
      Buffer.add_char buf (Char.chr 0x03);
      add_i16 buf idx
  | ReadMem w ->
      Buffer.add_char buf (Char.chr 0x04);
      Buffer.add_char buf (Char.chr (w land 0xFF))
  | WriteMem w ->
      Buffer.add_char buf (Char.chr 0x05);
      Buffer.add_char buf (Char.chr (w land 0xFF))
  | Add -> Buffer.add_char buf (Char.chr 0x06)
  | Sub -> Buffer.add_char buf (Char.chr 0x07)
  | Mul -> Buffer.add_char buf (Char.chr 0x08)
  | Nor -> Buffer.add_char buf (Char.chr 0x09)
  | Nand -> Buffer.add_char buf (Char.chr 0x0A)
  | Shl -> Buffer.add_char buf (Char.chr 0x0B)
  | Shr -> Buffer.add_char buf (Char.chr 0x0C)
  | Dup -> Buffer.add_char buf (Char.chr 0x0D)
  | Swap -> Buffer.add_char buf (Char.chr 0x0E)
  | PushFlags -> Buffer.add_char buf (Char.chr 0x0F)
  | PopFlags -> Buffer.add_char buf (Char.chr 0x10)
  | JmpRel b ->
      Buffer.add_char buf (Char.chr 0x11);
      add_i32 buf b
  | JccRel (b, c) ->
      Buffer.add_char buf (Char.chr 0x12);
      Buffer.add_char buf (Char.chr (cond_to_code c));
      add_i32 buf b
  | KeyAdjust delta ->
      Buffer.add_char buf (Char.chr 0x13);
      add_i64 buf delta
  | Exit -> Buffer.add_char buf (Char.chr 0x14)

let encode_op op =
  let buf = Buffer.create 16 in
  encode_op_into buf op;
  Buffer.to_bytes buf

let encode_program ?(seed_key = 0x5877A564D00FL) prog =
  let plain_buf = Buffer.create 1024 in
  let block_offsets = Hashtbl.create (Hashtbl.length prog.blocks) in
  let sorted_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) prog.blocks []
                      |> List.sort (fun a b -> compare a.id b.id) in
  List.iter (fun b ->
    Hashtbl.replace block_offsets b.id (Buffer.length plain_buf);
    List.iter (encode_op_into plain_buf) b.ops
  ) sorted_blocks;

  let plain = Buffer.to_bytes plain_buf in
  let len = Bytes.length plain in
  let cipher = Bytes.create len in
  let key = ref seed_key in
  for i = 0 to len - 1 do
    let p = Char.code (Bytes.get plain i) in
    let k_byte = Int64.to_int (Int64.logand !key 0xFFL) in
    let c = p lxor k_byte in
    Bytes.set cipher i (Char.chr c);
    key := step_key !key p
  done;
  { bytes = cipher; block_offsets; seed_key }

let read_byte cipher pos key =
  if !pos >= Bytes.length cipher then None
  else begin
    let c = Char.code (Bytes.get cipher !pos) in
    incr pos;
    let k_byte = Int64.to_int (Int64.logand !key 0xFFL) in
    let p = c lxor k_byte in
    key := step_key !key p;
    Some p
  end

let read_i16 cipher pos key =
  match read_byte cipher pos key, read_byte cipher pos key with
  | Some b0, Some b1 -> Some (b0 lor (b1 lsl 8))
  | _ -> None

let read_i32 cipher pos key =
  let res = ref 0 in
  let ok = ref true in
  for i = 0 to 3 do
    match read_byte cipher pos key with
    | Some b -> res := !res lor (b lsl (i * 8))
    | None -> ok := false
  done;
  if !ok then Some !res else None

let read_i64 cipher pos key =
  let res = ref 0L in
  let ok = ref true in
  for i = 0 to 7 do
    match read_byte cipher pos key with
    | Some b ->
        let b_i64 = Int64.shift_left (Int64.of_int b) (i * 8) in
        res := Int64.logor !res b_i64
    | None -> ok := false
  done;
  if !ok then Some !res else None

let decode_op cipher pos key =
  match read_byte cipher pos key with
  | None -> None
  | Some 0x01 -> (match read_i64 cipher pos key with Some v -> Some (PushImm v) | None -> None)
  | Some 0x02 -> (match read_i16 cipher pos key with Some idx -> Some (PushReg idx) | None -> None)
  | Some 0x03 -> (match read_i16 cipher pos key with Some idx -> Some (PopReg idx) | None -> None)
  | Some 0x04 -> (match read_byte cipher pos key with Some w -> Some (ReadMem w) | None -> None)
  | Some 0x05 -> (match read_byte cipher pos key with Some w -> Some (WriteMem w) | None -> None)
  | Some 0x06 -> Some Add
  | Some 0x07 -> Some Sub
  | Some 0x08 -> Some Mul
  | Some 0x09 -> Some Nor
  | Some 0x0A -> Some Nand
  | Some 0x0B -> Some Shl
  | Some 0x0C -> Some Shr
  | Some 0x0D -> Some Dup
  | Some 0x0E -> Some Swap
  | Some 0x0F -> Some PushFlags
  | Some 0x10 -> Some PopFlags
  | Some 0x11 -> (match read_i32 cipher pos key with Some b -> Some (JmpRel b) | None -> None)
  | Some 0x12 ->
      (match read_byte cipher pos key, read_i32 cipher pos key with
       | Some c_code, Some b -> Some (JccRel (b, code_to_cond c_code))
       | _ -> None)
  | Some 0x13 -> (match read_i64 cipher pos key with Some delta -> Some (KeyAdjust delta) | None -> None)
  | Some 0x14 -> Some Exit
  | Some _ -> None

let decode_all cipher seed_key =
  let pos = ref 0 in
  let key = ref seed_key in
  let ops = ref [] in
  let finished = ref false in
  while not !finished && !pos < Bytes.length cipher do
    match decode_op cipher pos key with
    | Some op -> ops := op :: !ops
    | None -> finished := true
  done;
  List.rev !ops
