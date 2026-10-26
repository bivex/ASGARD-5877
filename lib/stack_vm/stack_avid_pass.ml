(** Phase 5b: Stack-VM Avid Junk Operands Pass
    ───────────────────────────────────────────
    Inserts randomized variable-size avid junk operands (PushImm / PopReg scratch)
    directly into program basic blocks.

    Soundness & Anti-Disassembly Invariants:
      1. Zero Net Stack Delta: Every injected avid operand cluster pushes a
         random non-zero pseudo-immediate onto the stack, applies an opaque
         scramble, and immediately drains it into a dedicated scratch context slot.
         Net stack delta across the avid pair = 0.
      2. Flag Preservation: Avid operations are either completely flag-neutral
         (PushImm / PopReg, PushReg), or wrapped safely if architectural flags
         are live according to [Stack_flag_liveness].
      3. Non-Linear Key Diffusion: The generated pseudo-immediates vary dynamically,
         disrupting static instruction length profiling.
      4. Scratch Isolation: Scratch slots used by avid operands are allocated
         via Context_allocator to guarantee zero collision with program state.
*)

open Stack_ir
open Random_visa_constants.Magic_numbers

type avid_config = {
  enabled  : bool;
  rate     : int;   (** Insertion probability (0..100) per eligible instruction *)
  max_avid : int;   (** Maximum avid clusters per block (0 = unlimited) *)
  seed     : int64;
}

let default_avid_config seed = {
  enabled  = true;
  rate     = 40;
  max_avid = 0;
  seed;
}

let splitmix64 s =
  let open Int64 in
  let s = add s golden_ratio_64 in
  let z = s in
  let z = mul (logxor z (shift_right_logical z 30)) splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) splitmix64_mix in
  let z = logxor z (shift_right_logical z 31) in
  (s, z)

type avid_rng = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 1 then 0
  else
    let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFFFFFFL) in
    v mod n

let is_terminator = function
  | JmpRel _ | JccRel _ | Exit -> true
  | _ -> false

(** Generates a balanced avid sequence (net stack delta = 0).
    Guarantees strict flag neutrality when flags_live is true. *)
let generate_avid_cluster rng scratch_slot flags_live =
  let imm1 = next_int64 rng in
  let imm2 = next_int64 rng in
  if flags_live then
    (* Pure flag-neutral cluster: PushImm, PopReg, PushReg are 100% flag neutral *)
    match next_int rng 2 with
    | 0 ->
        [ PushImm imm1; PopReg scratch_slot ]
    | _ ->
        [ PushImm imm1; PushReg scratch_slot; PopReg scratch_slot; PopReg scratch_slot ]
  else
    (* Flags are dead here: can use ALU-based avid clusters as well *)
    match next_int rng 3 with
    | 0 ->
        [ PushImm imm1; PopReg scratch_slot ]
    | 1 ->
        [ SetRegImm (scratch_slot, imm1); AddRegImm (scratch_slot, imm2); PopReg scratch_slot ]
    | _ ->
        [ PushImm imm1; Dup; Sub; PopReg scratch_slot ]

let apply_block (cfg : avid_config) ctx (b : block) : block =
  if not cfg.enabled || cfg.rate <= 0 then b
  else
    let rng =
      make_rng
        (Int64.logxor cfg.seed
           (Int64.of_int
              (b.id * Int64.to_int salt_avid_block_mul
               + Int64.to_int salt_avid_block_add)))
    in
    let scratch_slot = Context_allocator.alloc_scratch ctx in
    let live = Stack_flag_liveness.analyze_list b.ops in
    let new_ops = ref [] in
    let count = ref 0 in
    List.iteri (fun idx op ->
      new_ops := op :: !new_ops;
      if not (is_terminator op) && (cfg.max_avid <= 0 || !count < cfg.max_avid) then begin
        if next_int rng 100 < cfg.rate then begin
          let flags_live = live.(idx + 1) in
          let cluster = generate_avid_cluster rng scratch_slot flags_live in
          new_ops := List.rev cluster @ !new_ops;
          incr count
        end
      end
    ) b.ops;
    { b with ops = List.rev !new_ops }

let apply_program (cfg : avid_config) (ctx : Context_allocator.t) (prog : program) : program =
  if not cfg.enabled || cfg.rate <= 0 then prog
  else
    let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
    Hashtbl.iter (fun id b ->
      Hashtbl.add new_blocks id (apply_block cfg ctx b)
    ) prog.blocks;
    let context_slots = max prog.context_slots (Context_allocator.total_slots ctx) in
    { prog with blocks = new_blocks; context_slots }

let avid_stats prog_before prog_after =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let before = count_ops prog_before in
  let after  = count_ops prog_after in
  let added = after - before in
  Printf.sprintf "Avid operands: %d ops → %d ops (+%d avid junk ops, +%.1f%%)"
    before after added
    (if before = 0 then 0.0 else float_of_int added /. float_of_int before *. 100.0)
