open Ir

let is_transformable_gpr = function
  | Register.Gpr (Register.RSP, _) | Register.Gpr (Register.RBP, _) -> false
  | Register.Gpr (_, Register.B64) -> true
  | _ -> false

let make_variants op dst in_a in_b tmp =
  match op with
  | Add ->
      (* v0: direct add *)
      let v0 = [
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Add; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
      ] in
      (* v1: (a | b) + (a & b) *)
      let v1 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Or; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Add; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v2: (a ^ b) + 2*(a & b) *)
      let v2 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Alu { op = Shl; dst = tmp; src1 = Reg tmp; src2 = Imm 1L; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Xor; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Add; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v3: 2*(a | b) - (a ^ b) *)
      let v3 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = Xor; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Or; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Shl; dst; src1 = Reg dst; src2 = Imm 1L; set_flags = false };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      Some (v0, v1, v2, v3)

  | Sub ->
      (* v0: direct sub *)
      let v0 = [
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
      ] in
      (* v1: (a ^ b) - 2*(~a & b) *)
      let v1 = [
        Unary { op = Not; dst = tmp; src = Reg in_a; set_flags = false };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Alu { op = Shl; dst = tmp; src1 = Reg tmp; src2 = Imm 1L; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Xor; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v2: (a & ~b) - (~a & b) *)
      let v2 = [
        Unary { op = Not; dst = tmp; src = Reg in_a; set_flags = false };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Unary { op = Not; dst; src = Reg in_b; set_flags = false };
        Alu { op = And; dst; src1 = Reg dst; src2 = Reg in_a; set_flags = false };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v3: 2*(a & ~b) - (a ^ b) *)
      let v3 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = Xor; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Unary { op = Not; dst; src = Reg in_b; set_flags = false };
        Alu { op = And; dst; src1 = Reg dst; src2 = Reg in_a; set_flags = false };
        Alu { op = Shl; dst; src1 = Reg dst; src2 = Imm 1L; set_flags = false };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      Some (v0, v1, v2, v3)

  | Xor ->
      (* v0: direct xor *)
      let v0 = [
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Xor; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
      ] in
      (* v1: (a | b) - (a & b) *)
      let v1 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Or; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v2: ~(a & b) & (a | b) *)
      let v2 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Unary { op = Not; dst = tmp; src = Reg tmp; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Or; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = And; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v3: (a & ~b) | (~a & b) *)
      let v3 = [
        Unary { op = Not; dst = tmp; src = Reg in_a; set_flags = false };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Unary { op = Not; dst; src = Reg in_b; set_flags = false };
        Alu { op = And; dst; src1 = Reg dst; src2 = Reg in_a; set_flags = false };
        Alu { op = Or; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      Some (v0, v1, v2, v3)

  | And ->
      (* v0: direct and *)
      let v0 = [
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = And; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
      ] in
      (* v1: (a | b) - (a ^ b) *)
      let v1 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = Xor; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Or; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v2: (a + b) - (a | b) *)
      let v2 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = Or; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Add; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v3: ~(~a | ~b) *)
      let v3 = [
        Unary { op = Not; dst = tmp; src = Reg in_a; set_flags = false };
        Unary { op = Not; dst; src = Reg in_b; set_flags = false };
        Alu { op = Or; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
        Unary { op = Not; dst; src = Reg dst; set_flags = false };
      ] in
      Some (v0, v1, v2, v3)

  | Or ->
      (* v0: direct or *)
      let v0 = [
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Or; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
      ] in
      (* v1: (a ^ b) + (a & b) *)
      let v1 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Xor; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Add; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v2: (a + b) - (a & b) *)
      let v2 = [
        Mov { dst = Reg tmp; src = Reg in_a };
        Alu { op = And; dst = tmp; src1 = Reg tmp; src2 = Reg in_b; set_flags = false };
        Mov { dst = Reg dst; src = Reg in_a };
        Alu { op = Add; dst; src1 = Reg dst; src2 = Reg in_b; set_flags = false };
        Alu { op = Sub; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
      ] in
      (* v3: ~(~a & ~b) *)
      let v3 = [
        Unary { op = Not; dst = tmp; src = Reg in_a; set_flags = false };
        Unary { op = Not; dst; src = Reg in_b; set_flags = false };
        Alu { op = And; dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
        Unary { op = Not; dst; src = Reg dst; set_flags = false };
      ] in
      Some (v0, v1, v2, v3)

  | _ -> None

let rec has_later_flag_consumer = function
  | [] -> false
  | (Jcc _ | Cmov _ | Setcc _ | Ccmp _ | Ccmn _ | Get_flags _ | Alu { op = (Adc | Sbb); _ }) :: _ ->
      true
  | (Cmp _ | Test _ | Alu { set_flags = true; _ } | Unary { set_flags = true; _ } | Set_flags _) :: rest ->
      let rec check_consumed = function
        | [] -> false
        | (Jcc _ | Cmov _ | Setcc _ | Ccmp _ | Ccmn _ | Get_flags _ | Alu { op = (Adc | Sbb); _ }) :: _ -> true
        | (Cmp _ | Test _ | Alu { set_flags = true; _ } | Unary { set_flags = true; _ } | Set_flags _) :: _ -> false
        | _ :: r -> check_consumed r
      in
      check_consumed rest
  | _ :: rest -> has_later_flag_consumer rest

let transform ?(density = 0.6) ~rng (f : func) : func =
  let max_id = ref 0 in
  Hashtbl.iter (fun id _ -> if id > !max_id then max_id := id) f.cfg.blocks;
  let threshold = int_of_float (density *. 100.0) in

  let all_blocks = ref [] in

  Hashtbl.iter (fun _ (b : basic_block) ->
    let rec process_instrs cur_id cur_label instrs_acc = function
      | [] ->
          let blk = { id = cur_id; label = cur_label; instrs = List.rev instrs_acc } in
          all_blocks := blk :: !all_blocks
      | (Alu { op; dst; src1 = Reg s1; src2; set_flags = false } as alu_instr) :: rest
        when is_transformable_gpr dst && is_transformable_gpr s1
             && not (has_later_flag_consumer rest)
             && Random.State.int rng 100 < threshold ->
          let w = Register.get_width dst in
          let in_a = Register.with_width Register.vtmp0 w in
          let in_b = Register.with_width Register.vtmp1 w in
          let tmp = Register.with_width Register.vtmp2 w in
          let sel = Register.with_width Register.vtmp3 w in

          let setup =
            match src2 with
            | Reg r2 when is_transformable_gpr r2 ->
                [
                  Mov { dst = Reg in_a; src = Reg s1 };
                  Mov { dst = Reg in_b; src = Reg r2 };
                ]
            | Imm imm ->
                [
                  Mov { dst = Reg in_a; src = Reg s1 };
                  Mov { dst = Reg in_b; src = Imm imm };
                ]
            | _ -> []
          in
          if setup = [] then
            process_instrs cur_id cur_label (alu_instr :: instrs_acc) rest
          else
            (match make_variants op dst in_a in_b tmp with
            | Some (v0_ops, v1_ops, v2_ops, v3_ops) ->
                incr max_id;
                let low_id = !max_id in
                incr max_id;
                let high_id = !max_id in
                incr max_id;
                let v0_id = !max_id in
                incr max_id;
                let v1_id = !max_id in
                incr max_id;
                let v2_id = !max_id in
                incr max_id;
                let v3_id = !max_id in
                incr max_id;
                let merge_id = !max_id in

                let shift = Random.State.int rng 32 in
                let selector = setup @ [
                  Mov { dst = Reg sel; src = Reg in_a };
                  Alu { op = Shr; dst = sel; src1 = Reg sel; src2 = Imm (Int64.of_int shift); set_flags = false };
                  Alu { op = And; dst = sel; src1 = Reg sel; src2 = Imm 3L; set_flags = false };
                  Cmp { src1 = Reg sel; src2 = Imm 1L };
                  Jcc { cond = Flags.BE; target_true = BlockId low_id; target_false = BlockId high_id };
                ] in

                let cur_blk = {
                  id = cur_id;
                  label = cur_label;
                  instrs = List.rev instrs_acc @ selector;
                } in

                let low_blk = {
                  id = low_id;
                  label = Printf.sprintf "%s_dmba_low_%d" f.name low_id;
                  instrs = [
                    Cmp { src1 = Reg sel; src2 = Imm 0L };
                    Jcc { cond = Flags.E; target_true = BlockId v0_id; target_false = BlockId v1_id };
                  ];
                } in

                let high_blk = {
                  id = high_id;
                  label = Printf.sprintf "%s_dmba_high_%d" f.name high_id;
                  instrs = [
                    Cmp { src1 = Reg sel; src2 = Imm 2L };
                    Jcc { cond = Flags.E; target_true = BlockId v2_id; target_false = BlockId v3_id };
                  ];
                } in

                let v0_blk = {
                  id = v0_id;
                  label = Printf.sprintf "%s_dmba0_%d" f.name v0_id;
                  instrs = v0_ops @ [ Jmp (BlockId merge_id) ];
                } in
                let v1_blk = {
                  id = v1_id;
                  label = Printf.sprintf "%s_dmba1_%d" f.name v1_id;
                  instrs = v1_ops @ [ Jmp (BlockId merge_id) ];
                } in
                let v2_blk = {
                  id = v2_id;
                  label = Printf.sprintf "%s_dmba2_%d" f.name v2_id;
                  instrs = v2_ops @ [ Jmp (BlockId merge_id) ];
                } in
                let v3_blk = {
                  id = v3_id;
                  label = Printf.sprintf "%s_dmba3_%d" f.name v3_id;
                  instrs = v3_ops @ [ Jmp (BlockId merge_id) ];
                } in

                all_blocks := cur_blk :: low_blk :: high_blk :: v0_blk :: v1_blk :: v2_blk :: v3_blk :: !all_blocks;
                let next_label = Printf.sprintf "%s_mrg_%d" cur_label merge_id in
                process_instrs merge_id next_label [] rest
            | None ->
                process_instrs cur_id cur_label (alu_instr :: instrs_acc) rest)
      | instr :: rest ->
          process_instrs cur_id cur_label (instr :: instrs_acc) rest
    in
    process_instrs b.id b.label [] b.instrs
  ) f.cfg.blocks;

  let new_tbl = Hashtbl.create (List.length !all_blocks) in
  List.iter (fun (b : basic_block) -> Hashtbl.replace new_tbl b.id b) !all_blocks;
  { f with cfg = { f.cfg with blocks = new_tbl } }
