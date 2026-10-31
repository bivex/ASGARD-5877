open Ir

let is_transformable_gpr = function
  | Register.Gpr (Register.RSP, _) | Register.Gpr (Register.RBP, _) -> false
  | Register.Gpr (_, Register.B64) -> true
  | _ -> false

let is_vtmp (r : Register.t) : bool =
  r = Register.vtmp0 || r = Register.vtmp1 || r = Register.vtmp2 || r = Register.vtmp3

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

let make_single_block_variants ~rng op dst s1 src2 =
  let w = Register.get_width dst in
  let tmp0 = Register.with_width Register.vtmp0 w in
  let tmp1 = Register.with_width Register.vtmp1 w in
  let tmp2 = Register.with_width Register.vtmp2 w in
  let sel  = Register.with_width Register.vtmp3 w in
  let s2_op = match src2 with Reg r -> Reg r | Imm imm -> Imm imm | _ -> assert false in

  let variants =
    match op with
    | Add ->
        (* v0: (s1 ^ s2) + 2*(s1 & s2) *)
        let v0 = [
          Mov { dst = Reg tmp0; src = Reg s1 };
          Alu { op = Xor; dst = tmp0; src1 = Reg tmp0; src2 = s2_op; set_flags = false };
          Mov { dst = Reg tmp1; src = Reg s1 };
          Alu { op = And; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Alu { op = Shl; dst = tmp1; src1 = Reg tmp1; src2 = Imm 1L; set_flags = false };
          Alu { op = Add; dst = tmp0; src1 = Reg tmp0; src2 = Reg tmp1; set_flags = false };
        ] in
        (* v1: (s1 | s2) + (s1 & s2) *)
        let v1 = [
          Mov { dst = Reg tmp1; src = Reg s1 };
          Alu { op = Or; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Mov { dst = Reg tmp2; src = Reg s1 };
          Alu { op = And; dst = tmp2; src1 = Reg tmp2; src2 = s2_op; set_flags = false };
          Alu { op = Add; dst = tmp1; src1 = Reg tmp1; src2 = Reg tmp2; set_flags = false };
        ] in
        Some (v0, v1)

    | Sub ->
        (* v0: (s1 ^ s2) - 2*(~s1 & s2) *)
        let v0 = [
          Unary { op = Not; dst = tmp1; src = Reg s1; set_flags = false };
          Alu { op = And; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Alu { op = Shl; dst = tmp1; src1 = Reg tmp1; src2 = Imm 1L; set_flags = false };
          Mov { dst = Reg tmp0; src = Reg s1 };
          Alu { op = Xor; dst = tmp0; src1 = Reg tmp0; src2 = s2_op; set_flags = false };
          Alu { op = Sub; dst = tmp0; src1 = Reg tmp0; src2 = Reg tmp1; set_flags = false };
        ] in
        (* v1: 2*(s1 & ~s2) - (s1 ^ s2) *)
        let v1 =
          match src2 with
          | Reg r -> [
              Unary { op = Not; dst = tmp2; src = Reg r; set_flags = false };
              Mov { dst = Reg tmp1; src = Reg s1 };
              Alu { op = And; dst = tmp1; src1 = Reg tmp1; src2 = Reg tmp2; set_flags = false };
              Alu { op = Shl; dst = tmp1; src1 = Reg tmp1; src2 = Imm 1L; set_flags = false };
              Mov { dst = Reg tmp2; src = Reg s1 };
              Alu { op = Xor; dst = tmp2; src1 = Reg tmp2; src2 = Reg r; set_flags = false };
              Alu { op = Sub; dst = tmp1; src1 = Reg tmp1; src2 = Reg tmp2; set_flags = false };
            ]
          | Imm imm -> [
              Mov { dst = Reg tmp1; src = Reg s1 };
              Alu { op = And; dst = tmp1; src1 = Reg tmp1; src2 = Imm (Int64.lognot imm); set_flags = false };
              Alu { op = Shl; dst = tmp1; src1 = Reg tmp1; src2 = Imm 1L; set_flags = false };
              Mov { dst = Reg tmp2; src = Reg s1 };
              Alu { op = Xor; dst = tmp2; src1 = Reg tmp2; src2 = Imm imm; set_flags = false };
              Alu { op = Sub; dst = tmp1; src1 = Reg tmp1; src2 = Reg tmp2; set_flags = false };
            ]
          | _ -> []
        in
        if v1 = [] then None else Some (v0, v1)

    | Xor ->
        (* v0: (s1 | s2) - (s1 & s2) *)
        let v0 = [
          Mov { dst = Reg tmp0; src = Reg s1 };
          Alu { op = Or; dst = tmp0; src1 = Reg tmp0; src2 = s2_op; set_flags = false };
          Mov { dst = Reg tmp1; src = Reg s1 };
          Alu { op = And; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Alu { op = Sub; dst = tmp0; src1 = Reg tmp0; src2 = Reg tmp1; set_flags = false };
        ] in
        (* v1: (s1 + s2) - 2*(s1 & s2) *)
        let v1 = [
          Mov { dst = Reg tmp1; src = Reg s1 };
          Alu { op = Add; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Mov { dst = Reg tmp2; src = Reg s1 };
          Alu { op = And; dst = tmp2; src1 = Reg tmp2; src2 = s2_op; set_flags = false };
          Alu { op = Shl; dst = tmp2; src1 = Reg tmp2; src2 = Imm 1L; set_flags = false };
          Alu { op = Sub; dst = tmp1; src1 = Reg tmp1; src2 = Reg tmp2; set_flags = false };
        ] in
        Some (v0, v1)

    | And ->
        (* v0: (s1 + s2) - (s1 | s2) *)
        let v0 = [
          Mov { dst = Reg tmp0; src = Reg s1 };
          Alu { op = Add; dst = tmp0; src1 = Reg tmp0; src2 = s2_op; set_flags = false };
          Mov { dst = Reg tmp1; src = Reg s1 };
          Alu { op = Or; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Alu { op = Sub; dst = tmp0; src1 = Reg tmp0; src2 = Reg tmp1; set_flags = false };
        ] in
        (* v1: (s1 | s2) - (s1 ^ s2) *)
        let v1 = [
          Mov { dst = Reg tmp1; src = Reg s1 };
          Alu { op = Or; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Mov { dst = Reg tmp2; src = Reg s1 };
          Alu { op = Xor; dst = tmp2; src1 = Reg tmp2; src2 = s2_op; set_flags = false };
          Alu { op = Sub; dst = tmp1; src1 = Reg tmp1; src2 = Reg tmp2; set_flags = false };
        ] in
        Some (v0, v1)

    | Or ->
        (* v0: (s1 ^ s2) + (s1 & s2) *)
        let v0 = [
          Mov { dst = Reg tmp0; src = Reg s1 };
          Alu { op = Xor; dst = tmp0; src1 = Reg tmp0; src2 = s2_op; set_flags = false };
          Mov { dst = Reg tmp1; src = Reg s1 };
          Alu { op = And; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Alu { op = Add; dst = tmp0; src1 = Reg tmp0; src2 = Reg tmp1; set_flags = false };
        ] in
        (* v1: (s1 + s2) - (s1 & s2) *)
        let v1 = [
          Mov { dst = Reg tmp1; src = Reg s1 };
          Alu { op = Add; dst = tmp1; src1 = Reg tmp1; src2 = s2_op; set_flags = false };
          Mov { dst = Reg tmp2; src = Reg s1 };
          Alu { op = And; dst = tmp2; src1 = Reg tmp2; src2 = s2_op; set_flags = false };
          Alu { op = Sub; dst = tmp1; src1 = Reg tmp1; src2 = Reg tmp2; set_flags = false };
        ] in
        Some (v0, v1)

    | _ -> None
  in
  match variants with
  | Some (v0_ops, v1_ops) ->
      let shift = Random.State.int rng 32 in
      let sel_ops = [
        Mov { dst = Reg sel; src = Reg s1 };
        Alu { op = Shr; dst = sel; src1 = Reg sel; src2 = Imm (Int64.of_int shift); set_flags = false };
        Alu { op = And; dst = sel; src1 = Reg sel; src2 = Imm 1L; set_flags = false };
        Cmp { src1 = Reg sel; src2 = Imm 0L };
        Mov { dst = Reg dst; src = Reg tmp0 };
        Cmov { cond = Flags.E; dst; src = Reg tmp1 };
      ] in
      Some (v0_ops @ v1_ops @ sel_ops)
  | None -> None

let transform ?(density = 0.5) ~rng (f : func) : func =
  let threshold = int_of_float (density *. 100.0) in
  let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
  Hashtbl.iter (fun id (b : basic_block) ->
    let rec process_instrs instrs_acc = function
      | [] -> List.rev instrs_acc
      | (Alu { op; dst; src1 = Reg s1; src2; set_flags = false } as alu_instr) :: rest
        when is_transformable_gpr dst && is_transformable_gpr s1
             && not (is_vtmp dst) && not (is_vtmp s1)
             && (match src2 with Reg r -> is_transformable_gpr r && not (is_vtmp r) | Imm _ -> true | _ -> false)
             && not (has_later_flag_consumer rest)
             && Random.State.int rng 100 < threshold ->
          (match make_single_block_variants ~rng op dst s1 src2 with
           | Some expansion ->
               process_instrs (List.rev_append expansion instrs_acc) rest
           | None ->
               process_instrs (alu_instr :: instrs_acc) rest)
      | instr :: rest ->
          process_instrs (instr :: instrs_acc) rest
    in
    let transformed_instrs = process_instrs [] b.instrs in
    Hashtbl.replace new_blocks id { b with instrs = transformed_instrs }
  ) f.cfg.blocks;
  { f with cfg = { f.cfg with blocks = new_blocks } }
