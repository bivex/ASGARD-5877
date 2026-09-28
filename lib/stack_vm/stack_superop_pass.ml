(** Phase 2a: Superoperator Fusion Pass
    ───────────────────────────────────
    Fuses recurring consecutive stack instruction sequences into specialized
    superoperators, collapsing multi-dispatch instruction sequences into single
    VM dispatches and diversifying the bytecode ISA on a per-build basis.
*)

open Stack_ir

(* ── SplitMix64 PRNG ─────────────────────────────────────────────────── *)
let splitmix64 s =
  let s = Int64.add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z 0xBF58476D1CE4E5B9L in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z 0x94D049BB133111EBL in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  (s, z)

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 0 then 0
  else
    let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFF_FFFFL) in
    v mod n

let maybe rng prob = next_int rng 100 < prob

(* ── Public API & Configuration ───────────────────────────────────────── *)

type superop_config = {
  seed               : int64;
  fusion_rate        : int;   (** Probability (0–100) of fusing eligible sequences *)
  enable_add_imm     : bool;
  enable_sub_imm     : bool;
  enable_add_ii      : bool;
  enable_sub_ii      : bool;
  enable_set_reg_imm : bool;
  enable_add_reg_imm : bool;
}

let default_superop_config seed = {
  seed;
  fusion_rate = 80;
  enable_add_imm = true;
  enable_sub_imm = true;
  enable_add_ii = true;
  enable_sub_ii = true;
  enable_set_reg_imm = true;
  enable_add_reg_imm = true;
}

type superop_stats = {
  initial_ops       : int;
  final_ops         : int;
  fused_ops         : int;
  add_imm_count     : int;
  sub_imm_count     : int;
  add_ii_count      : int;
  sub_ii_count      : int;
  set_reg_imm_count : int;
  add_reg_imm_count : int;
}

let apply_block cfg block =
  let rng = make_rng (Int64.logxor cfg.seed (Int64.of_int (block.id lxor 0x5170_0001))) in
  let rec aux = function
    | [] -> []
    | PushImm a :: PushImm b :: Add :: rest when cfg.enable_add_ii && maybe rng cfg.fusion_rate ->
        AddImmImm (a, b) :: aux rest
    | PushImm a :: PushImm b :: Sub :: rest when cfg.enable_sub_ii && maybe rng cfg.fusion_rate ->
        SubImmImm (a, b) :: aux rest
    | PushReg r :: PushImm c :: Add :: rest when cfg.enable_add_reg_imm && maybe rng cfg.fusion_rate ->
        AddRegImm (r, c) :: aux rest
    | PushImm c :: PopReg r :: rest when cfg.enable_set_reg_imm && maybe rng cfg.fusion_rate ->
        SetRegImm (r, c) :: aux rest
    | PushImm c :: Add :: rest when cfg.enable_add_imm && maybe rng cfg.fusion_rate ->
        AddImm c :: aux rest
    | PushImm c :: Sub :: rest when cfg.enable_sub_imm && maybe rng cfg.fusion_rate ->
        SubImm c :: aux rest
    | op :: rest ->
        op :: aux rest
  in
  { block with ops = aux block.ops }

let apply_program cfg prog =
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id b ->
    Hashtbl.replace new_blocks id (apply_block cfg b)
  ) prog.blocks;
  { prog with blocks = new_blocks }

let count_superops prog =
  let add_imm = ref 0 in
  let sub_imm = ref 0 in
  let add_ii = ref 0 in
  let sub_ii = ref 0 in
  let set_reg_imm = ref 0 in
  let add_reg_imm = ref 0 in
  let total_ops = ref 0 in
  Hashtbl.iter (fun _ b ->
    List.iter (fun op ->
      incr total_ops;
      match op with
      | AddImm _ -> incr add_imm
      | SubImm _ -> incr sub_imm
      | AddImmImm _ -> incr add_ii
      | SubImmImm _ -> incr sub_ii
      | SetRegImm _ -> incr set_reg_imm
      | AddRegImm _ -> incr add_reg_imm
      | _ -> ()
    ) b.ops
  ) prog.blocks;
  (!total_ops, !add_imm, !sub_imm, !add_ii, !sub_ii, !set_reg_imm, !add_reg_imm)

let superop_stats prog_before prog_after =
  let initial_ops = Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog_before.blocks 0 in
  let final_ops, add_imm, sub_imm, add_ii, sub_ii, set_reg_imm, add_reg_imm = count_superops prog_after in
  {
    initial_ops;
    final_ops;
    fused_ops = initial_ops - final_ops;
    add_imm_count = add_imm;
    sub_imm_count = sub_imm;
    add_ii_count = add_ii;
    sub_ii_count = sub_ii;
    set_reg_imm_count = set_reg_imm;
    add_reg_imm_count = add_reg_imm;
  }
