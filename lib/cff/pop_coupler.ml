open Vm_ir

type pop_config = {
  digest_reg : Register.t;
  scratch_reg1 : Register.t;
  scratch_reg2 : Register.t;
  initial_seed : int64;
}

let default_pop_config = {
  digest_reg = Register.vtmp2;
  scratch_reg1 = Register.vtmp0;
  scratch_reg2 = Register.vtmp1;
  initial_seed = 0x5877CAFEBABE1337L;
}

let rol64 v s =
  let s = s land 63 in
  Int64.logor (Int64.shift_left v s) (Int64.shift_right_logical v (64 - s))

let advance_digest prev_digest bid cond_tag =
  let k1 = rol64 prev_digest 13 in
  let golden = 0x9E3779B97F4A7C15L in
  let term = Int64.add (Int64.mul (Int64.of_int (bid + 1)) golden) cond_tag in
  Int64.logxor k1 term

let apply_pop_transform ?(config = default_pop_config) ~rng (func : Ir.func) =
  let _ = rng in
  let orig_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) func.cfg.blocks [] in
  let sorted_orig = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) orig_blocks in

  let transformed_blocks =
    List.map
      (fun (b : Ir.basic_block) ->
        let bid_val = Int64.of_int (b.id + 1) in
        let golden_const = 0x9E3779B97F4A7C15L in
        let term_const = Int64.mul bid_val golden_const in

        (* Emit ARX Digest Step:
           P = ROL13(P) ^ (bid * Golden) *)
        let digest_update_instrs = [
          (* scratch1 = P << 13 *)
          Ir.Mov { dst = Ir.Reg config.scratch_reg1; src = Ir.Reg config.digest_reg };
          Ir.Alu { op = Ir.Shl; dst = config.scratch_reg1; src1 = Ir.Reg config.scratch_reg1; src2 = Ir.Imm 13L; set_flags = false };
          (* scratch2 = P >> 51 *)
          Ir.Mov { dst = Ir.Reg config.scratch_reg2; src = Ir.Reg config.digest_reg };
          Ir.Alu { op = Ir.Shr; dst = config.scratch_reg2; src1 = Ir.Reg config.scratch_reg2; src2 = Ir.Imm 51L; set_flags = false };
          (* scratch1 = scratch1 | scratch2 (ROL13) *)
          Ir.Alu { op = Ir.Or; dst = config.scratch_reg1; src1 = Ir.Reg config.scratch_reg1; src2 = Ir.Reg config.scratch_reg2; set_flags = false };
          (* P = scratch1 ^ term_const *)
          Ir.Alu { op = Ir.Xor; dst = config.digest_reg; src1 = Ir.Reg config.scratch_reg1; src2 = Ir.Imm term_const; set_flags = false };
        ] in

        let init_instrs =
          if b.id = func.cfg.entry_id then
            [ Ir.Mov { dst = Ir.Reg config.digest_reg; src = Ir.Imm config.initial_seed } ]
          else []
        in

        let new_instrs = init_instrs @ digest_update_instrs @ b.instrs in
        { b with instrs = new_instrs })
      sorted_orig
  in

  Ir.make_func ~name:func.name ~entry_id:func.cfg.entry_id ~blocks:transformed_blocks
