(** ASGARD-5877: Tech-2601 (arXiv:2601.10261)
    Implementation of Shadow Unwind Generation, Cryptographic Sealing,
    Stack Rollback Arithmetic, and Exception Dispatch FSM. *)

open Tech_2601_types
open Bytecode_crypto

let default_shadow_alloc = 32
let default_interceptor_symbol = "tech_2601_interceptor"

let generate_shadow_record
    ?(alloc_size = default_shadow_alloc)
    ~interceptor_symbol
    (_meta : original_metadata) : (shadow_unwind_record, tech_2601_error) result =
  let ops = [ AllocStack alloc_size ] in
  match validate_abi_shadow_rules ops with
  | Error err ->
      let msg = match err with
        | UnalignedStackAllocation sz -> Printf.sprintf "Stack alloc %d is not 16-byte aligned" sz
        | ClobberedNonVolatileReg reg -> Printf.sprintf "Shadow unwind clobbered register %s" reg
        | InvalidFrameOffset off -> Printf.sprintf "Invalid frame offset %d" off
        | EmptyUnwindOps -> "Shadow unwind codes list is empty"
      in
      Error (AbiConstraintViolation msg)
  | Ok () ->
      Ok {
        shadow_alloc_size = alloc_size;
        shadow_ops = ops;
        interceptor_symbol;
      }

let compute_stack_rollback_delta (shadow : shadow_unwind_record) : int =
  (* Shadow global unwinding allocated shadow_alloc_size bytes on the stack.
     To restore stack frame layout for genuine VM execution, we reverse this offset. *)
  -shadow.shadow_alloc_size

(* --- Canonical Binary Serialization for Metadata & LSData --- *)

let magic_header = 0x54454348l (* "TECH" *)
let format_version = 1

let write_int32 buf v =
  let b = Bytes.create 4 in
  Bytes.set_int32_le b 0 v;
  Buffer.add_bytes buf b

let write_int64 buf v =
  let b = Bytes.create 8 in
  Bytes.set_int64_le b 0 v;
  Buffer.add_bytes buf b

let write_int16 buf v =
  let b = Bytes.create 2 in
  Bytes.set_uint16_le b 0 v;
  Buffer.add_bytes buf b

let write_string buf s =
  let len = String.length s in
  write_int16 buf len;
  Buffer.add_string buf s

let read_int32 bytes off =
  (Bytes.get_int32_le bytes off, off + 4)

let read_int64 bytes off =
  (Bytes.get_int64_le bytes off, off + 8)

let read_int16 bytes off =
  (Bytes.get_uint16_le bytes off, off + 2)

let read_string bytes off =
  let len, off1 = read_int16 bytes off in
  let s = Bytes.sub_string bytes off1 len in
  (s, off1 + len)

let serialize_unwind_op buf = function
  | AllocStack sz ->
      Buffer.add_char buf '\x01';
      write_int32 buf (Int32.of_int sz)
  | PushReg reg ->
      Buffer.add_char buf '\x02';
      write_string buf reg
  | SetFramePointer (reg, off) ->
      Buffer.add_char buf '\x03';
      write_string buf reg;
      write_int32 buf (Int32.of_int off)
  | SaveReg (reg, off) ->
      Buffer.add_char buf '\x04';
      write_string buf reg;
      write_int32 buf (Int32.of_int off)

let deserialize_unwind_op bytes off =
  let tag = Bytes.get bytes off in
  let off = off + 1 in
  match tag with
  | '\x01' ->
      let sz, off1 = read_int32 bytes off in
      (AllocStack (Int32.to_int sz), off1)
  | '\x02' ->
      let reg, off1 = read_string bytes off in
      (PushReg reg, off1)
  | '\x03' ->
      let reg, off1 = read_string bytes off in
      let off_val, off2 = read_int32 bytes off1 in
      (SetFramePointer (reg, Int32.to_int off_val), off2)
  | '\x04' ->
      let reg, off1 = read_string bytes off in
      let off_val, off2 = read_int32 bytes off1 in
      (SaveReg (reg, Int32.to_int off_val), off2)
  | _ -> failwith "Invalid unwind_op tag"

let serialize_metadata (meta : original_metadata) : bytes =
  let buf = Buffer.create 256 in
  write_int32 buf magic_header;
  write_int16 buf format_version;
  write_string buf meta.func_name;
  write_int64 buf meta.code_start_pc;
  write_int32 buf (Int32.of_int meta.code_size);

  (* Unwind ops *)
  write_int16 buf (List.length meta.unwind_ops);
  List.iter (serialize_unwind_op buf) meta.unwind_ops;

  (* Try scopes *)
  write_int16 buf (List.length meta.lsdata.scopes);
  List.iter (fun sc ->
    write_int32 buf (Int32.of_int sc.scope_id);
    write_int64 buf sc.start_pc;
    write_int64 buf sc.end_pc;
    write_int64 buf sc.landing_pad_pc;
    write_int32 buf sc.catch_type_tag
  ) meta.lsdata.scopes;

  (* Destructors *)
  write_int16 buf (List.length meta.lsdata.dtors);
  List.iter (fun dt ->
    write_int32 buf (Int32.of_int dt.obj_id);
    write_int64 buf dt.live_start_pc;
    write_int64 buf dt.live_end_pc;
    write_int64 buf dt.dtor_pc
  ) meta.lsdata.dtors;

  Buffer.to_bytes buf

let deserialize_metadata (raw : bytes) : (original_metadata, tech_2601_error) result =
  try
    let off = 0 in
    let magic, off = read_int32 raw off in
    if magic <> magic_header then
      Error (DeserializationError "Invalid magic header")
    else
      let ver, off = read_int16 raw off in
      if ver <> format_version then
        Error (DeserializationError "Unsupported format version")
      else
        let func_name, off = read_string raw off in
        let code_start_pc, off = read_int64 raw off in
        let code_size_i32, off = read_int32 raw off in
        let code_size = Int32.to_int code_size_i32 in

        (* Unwind ops *)
        let op_count, off = read_int16 raw off in
        let rec read_ops acc cur_off count =
          if count = 0 then (List.rev acc, cur_off)
          else
            let op, next_off = deserialize_unwind_op raw cur_off in
            read_ops (op :: acc) next_off (count - 1)
        in
        let unwind_ops, off = read_ops [] off op_count in

        (* Try scopes *)
        let scope_count, off = read_int16 raw off in
        let rec read_scopes acc cur_off count =
          if count = 0 then (List.rev acc, cur_off)
          else
            let sc_id, off1 = read_int32 raw cur_off in
            let st_pc, off2 = read_int64 raw off1 in
            let ed_pc, off3 = read_int64 raw off2 in
            let lp_pc, off4 = read_int64 raw off3 in
            let tag, off5 = read_int32 raw off4 in
            let sc = {
              scope_id = Int32.to_int sc_id;
              start_pc = st_pc;
              end_pc = ed_pc;
              landing_pad_pc = lp_pc;
              catch_type_tag = tag;
            } in
            read_scopes (sc :: acc) off5 (count - 1)
        in
        let scopes, off = read_scopes [] off scope_count in

        (* Destructors *)
        let dtor_count, off = read_int16 raw off in
        let rec read_dtors acc cur_off count =
          if count = 0 then (List.rev acc, cur_off)
          else
            let obj_id, off1 = read_int32 raw cur_off in
            let st_pc, off2 = read_int64 raw off1 in
            let ed_pc, off3 = read_int64 raw off2 in
            let dt_pc, off4 = read_int64 raw off3 in
            let dt = {
              obj_id = Int32.to_int obj_id;
              live_start_pc = st_pc;
              live_end_pc = ed_pc;
              dtor_pc = dt_pc;
            } in
            read_dtors (dt :: acc) off4 (count - 1)
        in
        let dtors, _ = read_dtors [] off dtor_count in

        Ok {
          func_name;
          code_start_pc;
          code_size;
          unwind_ops;
          lsdata = { scopes; dtors };
        }
  with exn ->
    Error (DeserializationError (Printexc.to_string exn))

(* --- Cryptographic Encapsulation & Counter Keystream --- *)

let derive_encryption_key ~master_key ~func_name =
  Hmac_sha256.digest ~key:master_key ~data:(Bytes.of_string ("TECH-2601-ENC:" ^ func_name))

let derive_mac_key ~master_key ~func_name =
  Hmac_sha256.digest ~key:master_key ~data:(Bytes.of_string ("TECH-2601-MAC:" ^ func_name))

let xor_keystream ~enc_key plaintext =
  let len = Bytes.length plaintext in
  let out = Bytes.create len in
  let block_count = (len + 31) / 32 in
  let cur_idx = ref 0 in
  for blk = 0 to block_count - 1 do
    let counter_bytes = Bytes.create 4 in
    Bytes.set_int32_le counter_bytes 0 (Int32.of_int blk);
    let key_block = Hmac_sha256.digest ~key:enc_key ~data:counter_bytes in
    let to_copy = min 32 (len - !cur_idx) in
    for i = 0 to to_copy - 1 do
      let p = Char.code (Bytes.get plaintext (!cur_idx + i)) in
      let k = Char.code (Bytes.get key_block i) in
      Bytes.set out (!cur_idx + i) (Char.chr (p lxor k))
    done;
    cur_idx := !cur_idx + to_copy
  done;
  out

let compute_container_mac ~mac_key ~func_name ~code_start_pc ~code_size ~shadow ~ciphertext =
  let buf = Buffer.create (128 + Bytes.length ciphertext) in
  write_string buf func_name;
  write_int64 buf code_start_pc;
  write_int32 buf (Int32.of_int code_size);
  write_int32 buf (Int32.of_int shadow.shadow_alloc_size);
  write_string buf shadow.interceptor_symbol;
  Buffer.add_bytes buf ciphertext;
  Hmac_sha256.digest ~key:mac_key ~data:(Buffer.to_bytes buf)

let seal_metadata
    ~master_key
    ?(alloc_size = default_shadow_alloc)
    ?(interceptor_symbol = default_interceptor_symbol)
    (meta : original_metadata) : protected_container =
  let shadow =
    match generate_shadow_record ~alloc_size ~interceptor_symbol meta with
    | Ok s -> s
    | Error _ ->
        { shadow_alloc_size = alloc_size; shadow_ops = [ AllocStack alloc_size ]; interceptor_symbol }
  in
  let plaintext = serialize_metadata meta in
  let enc_key = derive_encryption_key ~master_key ~func_name:meta.func_name in
  let ciphertext = xor_keystream ~enc_key plaintext in
  let mac_key = derive_mac_key ~master_key ~func_name:meta.func_name in
  let auth_tag = compute_container_mac
    ~mac_key
    ~func_name:meta.func_name
    ~code_start_pc:meta.code_start_pc
    ~code_size:meta.code_size
    ~shadow
    ~ciphertext
  in
  {
    func_name = meta.func_name;
    code_start_pc = meta.code_start_pc;
    code_size = meta.code_size;
    shadow;
    encrypted_metadata_blob = ciphertext;
    auth_tag;
  }

let unseal_metadata
    ~master_key
    (container : protected_container) : (original_metadata, tech_2601_error) result =
  let mac_key = derive_mac_key ~master_key ~func_name:container.func_name in
  let expected_tag = compute_container_mac
    ~mac_key
    ~func_name:container.func_name
    ~code_start_pc:container.code_start_pc
    ~code_size:container.code_size
    ~shadow:container.shadow
    ~ciphertext:container.encrypted_metadata_blob
  in
  if not (Sha256.constant_time_equal expected_tag container.auth_tag) then
    Error TamperDetected
  else
    let enc_key = derive_encryption_key ~master_key ~func_name:container.func_name in
    let decrypted = xor_keystream ~enc_key container.encrypted_metadata_blob in
    deserialize_metadata decrypted

(* --- Exception Handling Resolution FSM (Simulating EHInterceptor) --- *)

let resolve_exception
    (meta : original_metadata)
    ~(throwing_pc : int64)
    ~(exception_type : int32) : (int64 * int64 list, tech_2601_error) result =
  let catch_all_tag = -1l in (* 0xFFFFFFFF *)
  (* Find matching try scopes enclosing throwing_pc *)
  let matching_scopes =
    List.filter (fun sc ->
      throwing_pc >= sc.start_pc && throwing_pc < sc.end_pc &&
      (sc.catch_type_tag = exception_type || sc.catch_type_tag = catch_all_tag)
    ) meta.lsdata.scopes
  in
  match matching_scopes with
  | [] -> Error (ScopeNotFound throwing_pc)
  | _ ->
      (* Pick innermost scope (smallest span) *)
      let best_scope =
        List.fold_left (fun acc sc ->
          let span sc = Int64.sub sc.end_pc sc.start_pc in
          if span sc < span acc then sc else acc
        ) (List.hd matching_scopes) (List.tl matching_scopes)
      in

      (* Collect active destructors between throwing_pc and landing pad *)
      let active_dtors =
        List.filter (fun dt ->
          throwing_pc >= dt.live_start_pc && throwing_pc < dt.live_end_pc
        ) meta.lsdata.dtors
      in

      (* Order dtors in LIFO (reverse construction) order:
         Higher live_start_pc or higher obj_id comes first *)
      let sorted_dtors =
        List.sort (fun a b ->
          let c = compare b.live_start_pc a.live_start_pc in
          if c <> 0 then c else compare b.obj_id a.obj_id
        ) active_dtors
      in
      let dtor_pcs = List.map (fun dt -> dt.dtor_pc) sorted_dtors in
      Ok (best_scope.landing_pad_pc, dtor_pcs)

let runtime_header_decls = Tech_2601_emitter.runtime_header_decls
let runtime_header_source = Tech_2601_emitter.emit_runtime_header ()

