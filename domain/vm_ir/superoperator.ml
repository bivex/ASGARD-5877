open Ir
open Register

let is_terminator = function
  | Jmp _ | Jcc _ | Call _ | Ret | Vm_exit | Trap _ -> true
  | _ -> false

(* SplitMix64 for block-level deterministic randomization *)
let splitmix64_once (s : int64) : int64 =
  let s = Int64.add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z 0xBF58476D1CE4E5B9L in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z 0x94D049BB133111EBL in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  z

let is_vtmp = Vtmp_liveness.is_vtmp
let vtmp_mem = Vtmp_liveness.vtmp_mem
let vtmps_in_instr = Vtmp_liveness.vtmps_referenced_by_instr

(* Make a decoy write into a vtmp that is NOT currently live (i.e. not
   referenced by the instruction immediately before or after the insertion
   point).  [avoid] is the union of vtmps from those neighbours. *)
let make_decoy_instr_avoiding ~(avoid : Register.t list) (rng : Random.State.t) : instr option =
  let shadow_regs = [ vtmp0; vtmp1; vtmp2; vtmp3 ] in
  let candidates = List.filter (fun r -> not (List.mem r avoid)) shadow_regs in
  match candidates with
  | [] -> None
  | _ ->
      let target_reg = List.nth candidates (Random.State.int rng (List.length candidates)) in
      let roll = Random.State.int rng 4 in
      let imm_val = Int64.of_int (Random.State.bits rng) in
      Some (match roll with
        | 0 -> Mov { dst = Reg target_reg; src = Imm imm_val }
        | 1 -> Alu { op = Xor;  dst = target_reg; src1 = Reg target_reg; src2 = Imm imm_val; set_flags = false }
        | 2 -> Alu { op = Add;  dst = target_reg; src1 = Reg target_reg; src2 = Imm imm_val; set_flags = false }
        | _ -> Unary { op = Neg; dst = target_reg; src = Reg target_reg; set_flags = false })

let canonicalize_alu = function
  | Alu { op = Add; dst; src1; src2 = Imm imm; set_flags } when imm < 0L && imm <> Int64.min_int ->
      Alu { op = Sub; dst; src1; src2 = Imm (Int64.neg imm); set_flags }
  | Alu { op = Add; dst; src1 = Imm imm; src2 = Reg r; set_flags } ->
      if imm < 0L && imm <> Int64.min_int then
        Alu { op = Sub; dst; src1 = Reg r; src2 = Imm (Int64.neg imm); set_flags }
      else
        Alu { op = Add; dst; src1 = Reg r; src2 = Imm imm; set_flags }
  | other -> other

let compute_vtmp_liveness = Vtmp_liveness.compute_block_liveness
let compute_vtmp_live_outs = Vtmp_liveness.compute_func_live_outs
let all_vtmps = Vtmp_liveness.all_vtmps

let fuse_and_interleave_block ~(rng : Random.State.t) ~(live_out : Register.t list)
    (b : basic_block) : basic_block =
  let instrs = Array.of_list b.instrs in
  let n = Array.length instrs in
  let live = compute_vtmp_liveness instrs ~live_out in
  (* Decoy must not clobber a vtmp that is live past the insertion point;
     [tail_live] is the liveness after the (i1, i2) pair in the ORIGINAL
     instruction order, which is what any fused/decoy sequence preserves. *)
  let maybe_decoy i1 i2 tail_live =
    let avoid = vtmps_in_instr i1 @ vtmps_in_instr i2 @ tail_live in
    make_decoy_instr_avoiding ~avoid rng
  in
  let rec process k acc =
    if k >= n then List.rev acc
    else if k = n - 1 then List.rev (canonicalize_alu instrs.(k) :: acc)
    else
      let i1 = canonicalize_alu instrs.(k) in
      let i2 = canonicalize_alu instrs.(k + 1) in
      let tail_live = live.(k + 2) in
      let cont_with_fused fused =
        match maybe_decoy i1 i2 tail_live with
        | Some decoy -> process (k + 2) (fused :: decoy :: acc)
        | None -> process (k + 2) (fused :: acc)
      in
      match (i1, i2) with
      | (Mov { dst = Reg r1; src = Imm c1 }, Alu { op = Add; dst = r2; src1 = Reg r3; src2 = Imm c2; set_flags = false })
        when r1 = r2 && r1 = r3 ->
          (* Constant fold fusion: Mov r, c1 + c2 *)
          cont_with_fused (Mov { dst = Reg r1; src = Imm (Int64.add c1 c2) })
      | (Mov { dst = Reg r1; src = Imm imm }, Alu { op = Add; dst = r2; src1 = Reg r3; src2 = Reg r4; set_flags })
        when (r1 = r2 && (r1 = r3 || r1 = r4))
             || (is_vtmp r1 && (r1 = r3 || r1 = r4) && not (vtmp_mem r1 tail_live)) ->
          (* When r1 <> r2 the Mov disappears without overwriting r1, so the
             fusion is only sound while nothing downstream reads r1. *)
          let other_reg = if r1 = r3 then r4 else r3 in
          let fused_instr =
            if imm < 0L && imm <> Int64.min_int then
              Alu { op = Sub; dst = r2; src1 = Reg other_reg; src2 = Imm (Int64.neg imm); set_flags }
            else
              Alu { op = Add; dst = r2; src1 = Reg other_reg; src2 = Imm imm; set_flags }
          in
          cont_with_fused fused_instr
      | (Mov { dst = Reg r1; src = Imm imm }, Alu { op = Sub; dst = r2; src1 = Reg r3; src2 = Reg r4; set_flags })
        when (r1 = r2 && r1 = r4)
             || (is_vtmp r1 && r1 = r4 && not (vtmp_mem r1 tail_live)) ->
          let fused_instr =
            if imm < 0L && imm <> Int64.min_int then
              Alu { op = Add; dst = r2; src1 = Reg r3; src2 = Imm (Int64.neg imm); set_flags }
            else
              Alu { op = Sub; dst = r2; src1 = Reg r3; src2 = Imm imm; set_flags }
          in
          cont_with_fused fused_instr
      | (i, next) when not (is_terminator i) ->
          if Random.State.int rng 3 = 0 then
            match maybe_decoy i next tail_live with
            | Some decoy -> process (k + 1) (i :: decoy :: acc)
            | None -> process (k + 1) (i :: acc)
          else
            process (k + 1) (i :: acc)
      | (i, _next) ->
          process (k + 1) (i :: acc)
  in
  let transformed = process 0 [] in
  { b with instrs = transformed }

let transform_func ~(seed : Seed.t) (f : func) : func =
  let super_seed = Seed.superop_seed seed in
  (* Sort block ids for deterministic traversal *)
  let block_ids =
    Hashtbl.fold (fun id _ acc -> id :: acc) f.cfg.blocks []
    |> List.sort Int.compare
  in
  let live_outs = compute_vtmp_live_outs f in
  let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
  List.iter (fun id ->
    match Hashtbl.find_opt f.cfg.blocks id with
    | Some b ->
        let block_seed = splitmix64_once (Int64.logxor super_seed (Int64.of_int (b.id lxor 0x5009_0001))) in
        let rng = Seed.make_rng block_seed in
        let block_live_out =
          match Hashtbl.find_opt live_outs b.id with Some l -> l | None -> all_vtmps
        in
        let tb = fuse_and_interleave_block ~rng ~live_out:block_live_out b in
        Hashtbl.replace new_blocks id tb
    | None -> ()
  ) block_ids;
  { f with cfg = { f.cfg with blocks = new_blocks } }
