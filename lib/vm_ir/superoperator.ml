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

let make_decoy_instr (rng : Random.State.t) : instr =
  let shadow_regs = [ vtmp0; vtmp1; vtmp2; vtmp3 ] in
  let target_reg = List.nth shadow_regs (Random.State.int rng 4) in
  let roll = Random.State.int rng 4 in
  let imm_val = Int64.of_int (Random.State.bits rng) in
  match roll with
  | 0 -> Mov { dst = Reg target_reg; src = Imm imm_val }
  | 1 -> Alu { op = Xor; dst = target_reg; src1 = Reg target_reg; src2 = Imm imm_val; set_flags = false }
  | 2 -> Alu { op = Add; dst = target_reg; src1 = Reg target_reg; src2 = Imm imm_val; set_flags = false }
  | _ -> Unary { op = Neg; dst = target_reg; src = Reg target_reg; set_flags = false }

let is_vtmp (r : Register.t) : bool =
  r = vtmp0 || r = vtmp1 || r = vtmp2 || r = vtmp3

let canonicalize_alu = function
  | Alu { op = Add; dst; src1; src2 = Imm imm; set_flags } when imm < 0L && imm <> Int64.min_int ->
      Alu { op = Sub; dst; src1; src2 = Imm (Int64.neg imm); set_flags }
  | Alu { op = Add; dst; src1 = Imm imm; src2 = Reg r; set_flags } ->
      if imm < 0L && imm <> Int64.min_int then
        Alu { op = Sub; dst; src1 = Reg r; src2 = Imm (Int64.neg imm); set_flags }
      else
        Alu { op = Add; dst; src1 = Reg r; src2 = Imm imm; set_flags }
  | other -> other

let fuse_and_interleave_block ~(rng : Random.State.t) (b : basic_block) : basic_block =
  let rec process acc = function
    | [] -> List.rev acc
    | [ last ] -> List.rev (canonicalize_alu last :: acc)
    | i1 :: i2 :: rest ->
        let i1 = canonicalize_alu i1 in
        let i2 = canonicalize_alu i2 in
        (* Attempt instruction fusion or decoy interleaving *)
        match (i1, i2) with
        | (Mov { dst = Reg r1; src = Imm c1 }, Alu { op = Add; dst = r2; src1 = Reg r3; src2 = Imm c2; set_flags = false })
          when r1 = r2 && r1 = r3 ->
            (* Constant fold fusion: Mov r, c1 + c2 *)
            let fused_c = Int64.add c1 c2 in
            let fused_instr = Mov { dst = Reg r1; src = Imm fused_c } in
            let decoy = make_decoy_instr rng in
            process (decoy :: fused_instr :: acc) rest
        | (Mov { dst = Reg r1; src = Imm imm }, Alu { op = Add; dst = r2; src1 = Reg r3; src2 = Reg r4; set_flags })
          when (r1 = r2 && (r1 = r3 || r1 = r4)) || (is_vtmp r1 && (r1 = r3 || r1 = r4)) ->
            let other_reg = if r1 = r3 then r4 else r3 in
            let fused_instr =
              if imm < 0L && imm <> Int64.min_int then
                Alu { op = Sub; dst = r2; src1 = Reg other_reg; src2 = Imm (Int64.neg imm); set_flags }
              else
                Alu { op = Add; dst = r2; src1 = Reg other_reg; src2 = Imm imm; set_flags }
            in
            let decoy = make_decoy_instr rng in
            process (decoy :: fused_instr :: acc) rest
        | (Mov { dst = Reg r1; src = Imm imm }, Alu { op = Sub; dst = r2; src1 = Reg r3; src2 = Reg r4; set_flags })
          when (r1 = r2 && r1 = r4) || (is_vtmp r1 && r1 = r4) ->
            let fused_instr =
              if imm < 0L && imm <> Int64.min_int then
                Alu { op = Add; dst = r2; src1 = Reg r3; src2 = Imm (Int64.neg imm); set_flags }
              else
                Alu { op = Sub; dst = r2; src1 = Reg r3; src2 = Imm imm; set_flags }
            in
            let decoy = make_decoy_instr rng in
            process (decoy :: fused_instr :: acc) rest
        | (i, next) when not (is_terminator i) ->
            if Random.State.int rng 3 = 0 then
              let decoy = make_decoy_instr rng in
              process (decoy :: i :: acc) (next :: rest)
            else
              process (i :: acc) (next :: rest)
        | (i, next) ->
            process (i :: acc) (next :: rest)
  in
  let transformed = process [] b.instrs in
  { b with instrs = transformed }

let transform_func ~(seed : Seed.t) (f : func) : func =
  let super_seed = Seed.superop_seed seed in
  (* Sort block ids for deterministic traversal *)
  let block_ids =
    Hashtbl.fold (fun id _ acc -> id :: acc) f.cfg.blocks []
    |> List.sort Int.compare
  in
  let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
  List.iter (fun id ->
    match Hashtbl.find_opt f.cfg.blocks id with
    | Some b ->
        let block_seed = splitmix64_once (Int64.logxor super_seed (Int64.of_int (b.id lxor 0x5009_0001))) in
        let rng = Seed.make_rng block_seed in
        let tb = fuse_and_interleave_block ~rng b in
        Hashtbl.replace new_blocks id tb
    | None -> ()
  ) block_ids;
  { f with cfg = { f.cfg with blocks = new_blocks } }
