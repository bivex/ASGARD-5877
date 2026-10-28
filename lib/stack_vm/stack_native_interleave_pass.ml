(** Phase 6f (Pass 27): Native Micro-Handler Interleaving Pass
    ─────────────────────────────────────────────────────────────
    Blurs the classical boundary between virtual bytecode and native handlers
    by embedding encrypted native machine-code micro-handlers directly inside
    the bytecode stream.

    When the pass encounters a 4-op register ALU sequence:
      [ PushReg a; PushReg b; Add|Sub|Mul; PopReg c ]
    and downstream architectural flags are dead, it fuses the sequence into a
    single [NativeEscape (kind, a, b, c, stub)] instruction containing the
    compiled machine-code bytes for the host architecture.

    At runtime:
      1. The VM escape handler decrypts the native stub bytes on-the-fly
         directly from the rolling key stream into a small RWX trampoline window.
      2. The instruction cache is invalidated via [__clear_cache].
      3. Control transfers to the interleaved micro-handler:
           ((void(*)(void*))window)(vm)
         which executes the native ALU instruction directly on [vm->ctx].
      4. The VM resumes bytecode interpretation at the next VIP.

    Soundness Invariants:
    1. Exact Value Preservation: ctx[c] = ctx[a] OP ctx[b] matches original.
    2. Zero Net Stack Delta: [PushReg a; PushReg b; ALU; PopReg c] consumed
       and pushed 0 net stack elements; [NativeEscape] has delta 0.
    3. Flag Safety: Applied strictly when condition codes are dead after the
       PopReg according to [Stack_flag_liveness].
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type native_interleave_config = {
  enabled : bool;
  rate : int;
  seed : int64;
  arch : Stack_native_stub.arch;
}

let default_native_interleave_config ?(arch = Stack_native_stub.AArch64) seed = {
  enabled = true;
  rate = 20;
  seed;
  arch;
}

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  (s, logxor z (shift_right_logical z 31))

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let z = next_int64 rng in
    Int64.to_int (Int64.logand z 0x7FFFFFFFL) mod n

let apply_block (cfg : native_interleave_config) (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int (b.id * 0x17A1 + 0x5877)))
    in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let budget = ref 1 in
    let ops_arr = Array.of_list b.ops in
    let n = Array.length ops_arr in
    let new_ops = ref [] in
    let i = ref 0 in

    while !i < n do
      let matched = ref false in
      if !budget > 0 && !i + 3 < n then begin
        match ops_arr.(!i), ops_arr.(!i + 1), ops_arr.(!i + 2), ops_arr.(!i + 3) with
        | PushReg a, PushReg b_slot, alu_op, PopReg c
          when a >= 0 && a < 4096 && b_slot >= 0 && b_slot < 4096 && c >= 0 && c < 4096 ->
            let kind_opt =
              match alu_op with
              | Add -> Some Stack_native_stub.kind_add
              | Sub -> Some Stack_native_stub.kind_sub
              | Mul -> Some Stack_native_stub.kind_mul
              | _ -> None
            in
            (match kind_opt with
             | Some kind when next_int rng 100 < cfg.rate ->
                 let flags_dead =
                   if !i + 3 < Array.length live then not live.(!i + 3) else true
                 in
                 if flags_dead then begin
                   decr budget;
                   let stub = Stack_native_stub.emit cfg.arch kind a b_slot c in
                   new_ops := NativeEscape (kind, a, b_slot, c, stub) :: !new_ops;
                   i := !i + 4;
                   matched := true
                 end
             | _ -> ())
        | _ -> ()
      end;
      if not !matched then begin
        new_ops := ops_arr.(!i) :: !new_ops;
        incr i
      end
    done;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : native_interleave_config) (_ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      let b' = apply_block cfg b in
      Hashtbl.add new_blocks id b'
    ) prog.blocks;
    { prog with blocks = new_blocks }

let native_interleave_stats prog_before prog_after =
  let count_escapes prog =
    Hashtbl.fold
      (fun _ b acc ->
        acc + List.fold_left (fun c op -> match op with NativeEscape _ -> c + 1 | _ -> c) 0 b.ops)
      prog.blocks 0
  in
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let escapes = count_escapes prog_after in
  let before = count_ops prog_before in
  let after = count_ops prog_after in
  Printf.sprintf "Native Micro-Handler Interleave: %d ops -> %d ops (%d native stubs interleaved in bytecode, %d ops fused)"
    before after escapes (before - after)
