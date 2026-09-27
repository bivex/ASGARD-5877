open Vm_ir
open Stack_ir
open Flags

type opcode_map = {
  op_push_imm : int;
  op_push_reg : int;
  op_pop_reg : int;
  op_read_mem : int;
  op_write_mem : int;
  op_add : int;
  op_sub : int;
  op_mul : int;
  op_nor : int;
  op_nand : int;
  op_shl : int;
  op_shr : int;
  op_dup : int;
  op_swap : int;
  op_push_flags : int;
  op_pop_flags : int;
  op_jmp_rel : int;
  op_jcc_rel : int;
  op_key_adjust : int;
  op_exit : int;
  op_call_extern : int;
  op_resolve_sym : int;
  op_setcc : int;
  op_cmov : int;
  op_cmp : int;
  op_test : int;
  op_sar : int;
  op_div : int;
  op_idiv : int;
}

let default_opcode_map = {
  op_push_imm = 0x01;
  op_push_reg = 0x02;
  op_pop_reg = 0x03;
  op_read_mem = 0x04;
  op_write_mem = 0x05;
  op_add = 0x06;
  op_sub = 0x07;
  op_mul = 0x08;
  op_nor = 0x09;
  op_nand = 0x0A;
  op_shl = 0x0B;
  op_shr = 0x0C;
  op_dup = 0x0D;
  op_swap = 0x0E;
  op_push_flags = 0x0F;
  op_pop_flags = 0x10;
  op_jmp_rel = 0x11;
  op_jcc_rel = 0x12;
  op_key_adjust = 0x13;
  op_exit = 0x14;
  op_call_extern = 0x15;
  op_resolve_sym = 0x16;
  op_setcc = 0x17;
  op_cmov = 0x18;
  op_cmp = 0x19;
  op_test = 0x1A;
  op_sar = 0x1B;
  op_div = 0x1C;
  op_idiv = 0x1D;
}

let splitmix64 state =
  state := Int64.add !state 0x9E3779B97F4A7C15L;
  let z = ref !state in
  z := Int64.logxor !z (Int64.shift_right_logical !z 30);
  z := Int64.mul !z 0xBF58476D1CE4E5B9L;
  z := Int64.logxor !z (Int64.shift_right_logical !z 27);
  z := Int64.mul !z 0x94D049BB133111EBL;
  z := Int64.logxor !z (Int64.shift_right_logical !z 31);
  !z

let generate_opcode_map seed =
  let state = ref (if seed = 0L then 0x5877A564D00FL else seed) in
  let pool = Array.init 254 (fun i -> i + 1) in
  for i = 0 to 28 do
    let r = splitmix64 state in
    let range = 254 - i in
    let offset = Int64.to_int (Int64.rem (Int64.logand r 0x7FFFFFFFFFFFFFFFL) (Int64.of_int range)) in
    let j = i + offset in
    let tmp = pool.(i) in
    pool.(i) <- pool.(j);
    pool.(j) <- tmp
  done;
  {
    op_push_imm    = pool.(0);
    op_push_reg    = pool.(1);
    op_pop_reg     = pool.(2);
    op_read_mem    = pool.(3);
    op_write_mem   = pool.(4);
    op_add         = pool.(5);
    op_sub         = pool.(6);
    op_mul         = pool.(7);
    op_nor         = pool.(8);
    op_nand        = pool.(9);
    op_shl         = pool.(10);
    op_shr         = pool.(11);
    op_dup         = pool.(12);
    op_swap        = pool.(13);
    op_push_flags  = pool.(14);
    op_pop_flags   = pool.(15);
    op_jmp_rel     = pool.(16);
    op_jcc_rel     = pool.(17);
    op_key_adjust  = pool.(18);
    op_exit        = pool.(19);
    op_call_extern = pool.(20);
    op_resolve_sym = pool.(21);
    op_setcc       = pool.(22);
    op_cmov        = pool.(23);
    op_cmp         = pool.(24);
    op_test        = pool.(25);
    op_sar         = pool.(26);
    op_div         = pool.(27);
    op_idiv        = pool.(28);
  }

type encrypted_bytecode = {
  bytes : bytes;
  block_offsets : (int, int) Hashtbl.t;
  block_keys : (int, int64) Hashtbl.t;
  seed_key : int64;
  op_map : opcode_map;
  (* Anti-VMPredator address binding: stored seed_key/block_keys literals are
     pre-XORed with this mask, and the C++ runtime XORs it back out with the
     key derived from its own handler addresses (derive_addr_key). The cipher
     bytes themselves are untouched — only the stored literals move. 0L means
     "not address-bound" and reproduces the legacy encoding exactly. *)
  addr_mask : int64;
}

(* Effective (unmasked) rolling seed: what the runtime reconstructs at entry
   after folding in the address key. This is the value decode_all and the
   OCaml evaluator must start from. *)
let effective_seed_key enc = Int64.logxor enc.seed_key enc.addr_mask

(* Re-bind (or un-bind) the stored literals to a new address mask. Delta-based
   so the operation composes: applying m2 over an enc masked with m1 only
   flips the literals by (m1 xor m2); mask 0L restores plaintext literals.
     stored' = effective xor mask' = (stored xor mask) xor mask' *)
let apply_addr_mask enc mask =
  let delta = Int64.logxor mask enc.addr_mask in
  let remasked_keys = Hashtbl.create (Hashtbl.length enc.block_keys) in
  Hashtbl.iter (fun id v ->
    Hashtbl.replace remasked_keys id (Int64.logxor v delta)) enc.block_keys;
  { enc with
    addr_mask = mask;
    seed_key = Int64.logxor enc.seed_key delta;
    block_keys = remasked_keys }

(* Parse exactly 16 uppercase/lowercase hex digits into the unsigned 64-bit
   pattern they denote. Int64.of_string "0x…" rejects values above
   Int64.max_int, but address keys are full-range, so fold manually. *)
let parse_u64_hex s =
  let digit c =
    match c with
    | '0' .. '9' -> Char.code c - Char.code '0'
    | 'a' .. 'f' -> Char.code c - Char.code 'a' + 10
    | 'A' .. 'F' -> Char.code c - Char.code 'A' + 10
    | _ -> failwith "parse_u64_hex: non-hex digit"
  in
  if String.length s <> 16 then failwith "parse_u64_hex: expected 16 hex digits";
  String.fold_left (fun acc c ->
    Int64.logor (Int64.shift_left acc 4) (Int64.of_int (digit c))) 0L s

let rotl64 v k =
  let k = k mod 64 in
  Int64.logor (Int64.shift_left v k) (Int64.shift_right_logical v (64 - k))

let step_key key byte_val =
  Int64.add (rotl64 key 3) (Int64.of_int (byte_val lxor 0x5A))

(* ── SipHash-1-2 (64-bit) for per-block key derivation ─────────────── *)
(** SipHash-1-2: 1 compression round, 2 finalisation rounds.
    Produces a 64-bit PRF output from a 128-bit key split into (k0, k1)
    and a 64-bit message word m.  Used to derive independent per-block
    entry keys so that compromising one block's key gives no information
    about any other block's key (unlike a linear rolling key stream). *)
let siphash_block ~k0 ~k1 m =
  let open Int64 in
  let ( lxor ) = logxor in
  let rotl v s = logor (shift_left v s) (shift_right_logical v (64 - s)) in
  let v0 = ref (k0 lxor 0x736F6D6570736575L) in
  let v1 = ref (k1 lxor 0x646F72616E646F6DL) in
  let v2 = ref (k0 lxor 0x6C7967656E657261L) in
  let v3 = ref (k1 lxor 0x7465646279746573L) in
  v3 := !v3 lxor m;
  v0 := add !v0 !v1; v1 := rotl !v1 13; v1 := !v1 lxor !v0;
  v0 := rotl !v0 32;
  v2 := add !v2 !v3; v3 := rotl !v3 16; v3 := !v3 lxor !v2;
  v0 := add !v0 !v3; v3 := rotl !v3 21; v3 := !v3 lxor !v0;
  v2 := add !v2 !v1; v1 := rotl !v1 17; v1 := !v1 lxor !v2;
  v2 := rotl !v2 32;
  v0 := !v0 lxor m;
  v2 := !v2 lxor 0xFFL;
  let sip_round () =
    v0 := add !v0 !v1; v1 := rotl !v1 13; v1 := !v1 lxor !v0;
    v0 := rotl !v0 32;
    v2 := add !v2 !v3; v3 := rotl !v3 16; v3 := !v3 lxor !v2;
    v0 := add !v0 !v3; v3 := rotl !v3 21; v3 := !v3 lxor !v0;
    v2 := add !v2 !v1; v1 := rotl !v1 17; v1 := !v1 lxor !v2;
    v2 := rotl !v2 32
  in
  sip_round (); sip_round ();
  !v0 lxor !v1 lxor !v2 lxor !v3

(** [derive_block_key seed_key block_id block_offset] derives an independent
    64-bit block entry key via SipHash-1-2.  Split seed into two halves for
    the 128-bit SipHash key; message = block_id XOR block_offset.
    Compromising one block's key yields zero information about other blocks. *)
let derive_block_key seed_key block_id block_offset =
  (* Split seed_key into two independent 64-bit halves via rotation *)
  let k0 = Int64.logxor seed_key 0x5877_A564_D00F_0000L in
  let k1 = Int64.logxor seed_key 0xD00F_5877_0000_A564L in
  let m  = Int64.logxor (Int64.of_int block_id) (Int64.of_int block_offset) in
  siphash_block ~k0 ~k1 m


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

let encode_op_into op_map buf = function
  | PushImm v ->
      Buffer.add_char buf (Char.chr op_map.op_push_imm);
      add_i64 buf v
  | PushReg idx ->
      Buffer.add_char buf (Char.chr op_map.op_push_reg);
      add_i16 buf idx
  | PopReg idx ->
      Buffer.add_char buf (Char.chr op_map.op_pop_reg);
      add_i16 buf idx
  | ReadMem w ->
      Buffer.add_char buf (Char.chr op_map.op_read_mem);
      Buffer.add_char buf (Char.chr (w land 0xFF))
  | WriteMem w ->
      Buffer.add_char buf (Char.chr op_map.op_write_mem);
      Buffer.add_char buf (Char.chr (w land 0xFF))
  | Add -> Buffer.add_char buf (Char.chr op_map.op_add)
  | Sub -> Buffer.add_char buf (Char.chr op_map.op_sub)
  | Mul -> Buffer.add_char buf (Char.chr op_map.op_mul)
  | Nor -> Buffer.add_char buf (Char.chr op_map.op_nor)
  | Nand -> Buffer.add_char buf (Char.chr op_map.op_nand)
  | Shl -> Buffer.add_char buf (Char.chr op_map.op_shl)
  | Shr -> Buffer.add_char buf (Char.chr op_map.op_shr)
  | Sar -> Buffer.add_char buf (Char.chr op_map.op_sar)
  | Div -> Buffer.add_char buf (Char.chr op_map.op_div)
  | Idiv -> Buffer.add_char buf (Char.chr op_map.op_idiv)
  | Dup -> Buffer.add_char buf (Char.chr op_map.op_dup)
  | Swap -> Buffer.add_char buf (Char.chr op_map.op_swap)
  | PushFlags -> Buffer.add_char buf (Char.chr op_map.op_push_flags)
  | PopFlags -> Buffer.add_char buf (Char.chr op_map.op_pop_flags)
  | JmpRel b ->
      Buffer.add_char buf (Char.chr op_map.op_jmp_rel);
      add_i32 buf b
  | JccRel (b, c) ->
      Buffer.add_char buf (Char.chr op_map.op_jcc_rel);
      Buffer.add_char buf (Char.chr (cond_to_code c));
      add_i32 buf b
  | KeyAdjust delta ->
      Buffer.add_char buf (Char.chr op_map.op_key_adjust);
      add_i64 buf delta
  | Exit -> Buffer.add_char buf (Char.chr op_map.op_exit)
  | CallExtern idx ->
      Buffer.add_char buf (Char.chr op_map.op_call_extern);
      add_i32 buf idx
  | ResolveSym idx ->
      Buffer.add_char buf (Char.chr op_map.op_resolve_sym);
      add_i32 buf idx
  | Setcc c ->
      Buffer.add_char buf (Char.chr op_map.op_setcc);
      Buffer.add_char buf (Char.chr (cond_to_code c))
  | Cmov (c, idx) ->
      Buffer.add_char buf (Char.chr op_map.op_cmov);
      Buffer.add_char buf (Char.chr (cond_to_code c));
      add_i16 buf idx
  | Cmp -> Buffer.add_char buf (Char.chr op_map.op_cmp)
  | Test -> Buffer.add_char buf (Char.chr op_map.op_test)

let encode_op ?(op_map = default_opcode_map) op =
  let buf = Buffer.create 16 in
  encode_op_into op_map buf op;
  Buffer.to_bytes buf

let encode_program ?(seed_key = 0x5877A564D00FL) ?op_map ?(polymorphic = true)
    ?(addr_mask = 0L) prog =
  let resolved_op_map = match op_map with
    | Some m -> m
    | None -> if polymorphic then generate_opcode_map seed_key else default_opcode_map
  in
  let plain_buf = Buffer.create 1024 in
  let block_offsets = Hashtbl.create (Hashtbl.length prog.blocks) in
  let block_keys = Hashtbl.create (Hashtbl.length prog.blocks) in
  (* KeyAdjust key-stream symmetry: the runtime XORs the rolling key with
     delta right after consuming the 8 operand bytes of a KeyAdjust. The
     encryptor must therefore apply the same mutation at the same byte
     boundary — after encrypting the last operand byte (offset op_pos+8). *)
  let key_adjust_ends : (int, int64) Hashtbl.t = Hashtbl.create 16 in
  let sorted_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) prog.blocks []
                      |> List.sort (fun a b -> compare a.id b.id) in
  List.iter (fun b ->
    Hashtbl.replace block_offsets b.id (Buffer.length plain_buf);
    List.iter (fun op ->
      let op_pos = Buffer.length plain_buf in
      encode_op_into resolved_op_map plain_buf op;
      match op with
      | KeyAdjust delta -> Hashtbl.replace key_adjust_ends (op_pos + 8) delta
      | _ -> ()
    ) b.ops
  ) sorted_blocks;

  let offset_to_id = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id off -> Hashtbl.replace offset_to_id off id) block_offsets;

  let plain = Buffer.to_bytes plain_buf in
  let len = Bytes.length plain in
  let cipher = Bytes.create len in
  (* Per-block SipHash re-key: each block starts from a key derived as
       K_B = SipHash-1-2(seed_key, block_id XOR block_offset)
     Within a block the rolling stream continues normally, but entry keys
     are independent — knowing block N's key reveals nothing about block M. *)
  let key = ref seed_key in
  for i = 0 to len - 1 do
    (match Hashtbl.find_opt offset_to_id i with
     | Some id ->
         let sip_key = derive_block_key seed_key id i in
         key := sip_key;
         Hashtbl.replace block_keys id sip_key
     | None -> ());
    let p = Char.code (Bytes.get plain i) in
    let k_byte = Int64.to_int (Int64.logand !key 0xFFL) in
    let c = p lxor k_byte in
    Bytes.set cipher i (Char.chr c);
    key := step_key !key p;
    (match Hashtbl.find_opt key_adjust_ends i with
     | Some delta -> key := Int64.logxor !key delta
     | None -> ())
  done;
  (* Address binding: the encryption loop above ran on effective keys; only
     the returned literals are masked so the binary stores
     (effective xor addr_mask) and the runtime folds the address key back
     in. With mask 0 the stored literals equal the effective ones (legacy
     behavior, byte-identical). *)
  let stored_keys = Hashtbl.create (Hashtbl.length block_keys) in
  Hashtbl.iter (fun id v ->
    Hashtbl.replace stored_keys id (Int64.logxor v addr_mask)) block_keys;
  { bytes = cipher;
    block_offsets;
    block_keys = stored_keys;
    seed_key = Int64.logxor seed_key addr_mask;
    op_map = resolved_op_map;
    addr_mask }

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

let decode_op ?(op_map = default_opcode_map) cipher pos key =
  match read_byte cipher pos key with
  | None -> None
  | Some b when b = op_map.op_push_imm ->
      (match read_i64 cipher pos key with Some v -> Some (PushImm v) | None -> None)
  | Some b when b = op_map.op_push_reg ->
      (match read_i16 cipher pos key with Some idx -> Some (PushReg idx) | None -> None)
  | Some b when b = op_map.op_pop_reg ->
      (match read_i16 cipher pos key with Some idx -> Some (PopReg idx) | None -> None)
  | Some b when b = op_map.op_read_mem ->
      (match read_byte cipher pos key with Some w -> Some (ReadMem w) | None -> None)
  | Some b when b = op_map.op_write_mem ->
      (match read_byte cipher pos key with Some w -> Some (WriteMem w) | None -> None)
  | Some b when b = op_map.op_add -> Some Add
  | Some b when b = op_map.op_sub -> Some Sub
  | Some b when b = op_map.op_mul -> Some Mul
  | Some b when b = op_map.op_nor -> Some Nor
  | Some b when b = op_map.op_nand -> Some Nand
  | Some b when b = op_map.op_shl -> Some Shl
  | Some b when b = op_map.op_shr -> Some Shr
  | Some b when b = op_map.op_sar -> Some Sar
  | Some b when b = op_map.op_div -> Some Div
  | Some b when b = op_map.op_idiv -> Some Idiv
  | Some b when b = op_map.op_dup -> Some Dup
  | Some b when b = op_map.op_swap -> Some Swap
  | Some b when b = op_map.op_push_flags -> Some PushFlags
  | Some b when b = op_map.op_pop_flags -> Some PopFlags
  | Some b when b = op_map.op_jmp_rel ->
      (match read_i32 cipher pos key with Some b -> Some (JmpRel b) | None -> None)
  | Some b when b = op_map.op_jcc_rel ->
      (match read_byte cipher pos key, read_i32 cipher pos key with
       | Some c_code, Some b -> Some (JccRel (b, code_to_cond c_code))
       | _ -> None)
  | Some b when b = op_map.op_key_adjust ->
      (* Mirror the runtime: the rolling key is XORed with delta right
         after the operand bytes are consumed, so decoding stays in sync
         with the encryptor's mutated key stream. *)
      (match read_i64 cipher pos key with
       | Some delta ->
           key := Int64.logxor !key delta;
           Some (KeyAdjust delta)
       | None -> None)
  | Some b when b = op_map.op_exit -> Some Exit
  | Some b when b = op_map.op_call_extern ->
      (match read_i32 cipher pos key with Some idx -> Some (CallExtern idx) | None -> None)
  | Some b when b = op_map.op_resolve_sym ->
      (match read_i32 cipher pos key with Some idx -> Some (ResolveSym idx) | None -> None)
  | Some b when b = op_map.op_setcc ->
      (match read_byte cipher pos key with Some c_code -> Some (Setcc (code_to_cond c_code)) | None -> None)
  | Some b when b = op_map.op_cmov ->
      (match read_byte cipher pos key, read_i16 cipher pos key with
       | Some c_code, Some idx -> Some (Cmov (code_to_cond c_code, idx))
       | _ -> None)
  | Some b when b = op_map.op_cmp -> Some Cmp
  | Some b when b = op_map.op_test -> Some Test
  | Some _ -> None

let decode_all ?op_map ?block_keys ?block_offsets cipher seed_key =
  let resolved_op_map = match op_map with
    | Some m -> m
    | None   -> generate_opcode_map seed_key
  in
  (* offset -> block_key lookup for per-block SipHash re-key *)
  let offset_to_key : (int, int64) Hashtbl.t = Hashtbl.create 16 in
  (match block_keys, block_offsets with
   | Some bk, Some bo ->
       Hashtbl.iter (fun id off ->
         match Hashtbl.find_opt bk id with
         | Some k -> Hashtbl.replace offset_to_key off k
         | None   -> ()
       ) bo
   | _ -> ());
  let pos = ref 0 in
  let initial_key =
    match Hashtbl.find_opt offset_to_key 0 with
    | Some k -> k
    | None   -> seed_key
  in
  let key = ref initial_key in
  let ops = ref [] in
  let finished = ref false in
  while not !finished && !pos < Bytes.length cipher do
    if !pos > 0 then
      (match Hashtbl.find_opt offset_to_key !pos with
       | Some k -> key := k
       | None   -> ());
    match decode_op ~op_map:resolved_op_map cipher pos key with
    | Some op -> ops := op :: !ops
    | None    -> finished := true
  done;
  List.rev !ops

(** Block-aware convenience: decode all ops from [encrypted_bytecode],
    correctly handling per-block SipHash re-key. *)
let decode_enc enc =
  (* Stored block_keys = sip_key XOR addr_mask.  Unmask to get effective
     SipHash keys before passing to decode_all, mirroring run_bytecode's
     key := logxor new_key enc.addr_mask treatment. *)
  let eff_block_keys = Hashtbl.create (Hashtbl.length enc.block_keys) in
  Hashtbl.iter (fun id k ->
    Hashtbl.replace eff_block_keys id (Int64.logxor k enc.addr_mask)
  ) enc.block_keys;
  decode_all
    ~op_map:enc.op_map
    ~block_keys:eff_block_keys
    ~block_offsets:enc.block_offsets
    enc.bytes
    (effective_seed_key enc)
