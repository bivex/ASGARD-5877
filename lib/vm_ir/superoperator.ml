open Ir
open Register

let is_terminator = function
  | Jmp _ | Jcc _ | Call _ | Ret | Vm_exit | Trap _ -> true
  | _ -> false

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

let fuse_and_interleave_block ~(rng : Random.State.t) (b : basic_block) : basic_block =
  let rec process acc = function
    | [] -> List.rev acc
    | [ last ] -> List.rev (last :: acc)
    | i1 :: i2 :: rest ->
        (* Attempt instruction fusion or decoy interleaving *)
        match (i1, i2) with
        | (Mov { dst = Reg r1; src = Imm c1 }, Alu { op = Add; dst = r2; src1 = Reg r3; src2 = Imm c2; set_flags = false })
          when r1 = r2 && r1 = r3 ->
            (* Constant fold fusion: Mov r, c1 + c2 *)
            let fused_c = Int64.add c1 c2 in
            let fused_instr = Mov { dst = Reg r1; src = Imm fused_c } in
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
  let rng = Seed.make_rng seed.superop_seed in
  let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
  Hashtbl.iter (fun id b ->
    let tb = fuse_and_interleave_block ~rng b in
    Hashtbl.replace new_blocks id tb
  ) f.cfg.blocks;
  { f with cfg = { f.cfg with blocks = new_blocks } }
