open Ir

let is_eligible_gpr = function
  | Register.Gpr (Register.RSP, _) | Register.Gpr (Register.RBP, _) -> false
  | Register.Gpr _ -> true
  | _ -> false

let extract_gprs instrs =
  let set = Hashtbl.create 8 in
  List.iter (function
    | Mov { dst = Reg d; src = Reg s } ->
        if is_eligible_gpr d then Hashtbl.replace set d ();
        if is_eligible_gpr s then Hashtbl.replace set s ()
    | Mov { dst = Reg d; _ } ->
        if is_eligible_gpr d then Hashtbl.replace set d ()
    | Alu { dst = d; src1 = Reg s1; src2 = Reg s2; _ } ->
        if is_eligible_gpr d then Hashtbl.replace set d ();
        if is_eligible_gpr s1 then Hashtbl.replace set s1 ();
        if is_eligible_gpr s2 then Hashtbl.replace set s2 ()
    | Alu { dst = d; src1 = Reg s1; _ } ->
        if is_eligible_gpr d then Hashtbl.replace set d ();
        if is_eligible_gpr s1 then Hashtbl.replace set s1 ()
    | Cmp { src1 = Reg s1; src2 = Reg s2 } ->
        if is_eligible_gpr s1 then Hashtbl.replace set s1 ();
        if is_eligible_gpr s2 then Hashtbl.replace set s2 ()
    | Cmp { src1 = Reg s1; _ } ->
        if is_eligible_gpr s1 then Hashtbl.replace set s1 ()
    | Push (Reg r) | Pop (Reg r) | Cmov { dst = r; _ } ->
        if is_eligible_gpr r then Hashtbl.replace set r ()
    | _ -> ()
  ) instrs;
  Hashtbl.fold (fun r () acc -> r :: acc) set []

let extract_func_gprs (f : func) =
  let set = Hashtbl.create 16 in
  Hashtbl.iter (fun _ (b : basic_block) ->
    List.iter (fun r -> Hashtbl.replace set r ()) (extract_gprs b.instrs)
  ) f.cfg.blocks;
  Hashtbl.fold (fun r () acc -> r :: acc) set []

let consumes_flags_before_def instrs =
  let rec check = function
    | [] -> false
    | (Jcc _ | Cmov _ | Setcc _ | Ccmp _ | Ccmn _ | Get_flags _ | Alu { op = (Adc | Sbb); _ }) :: _ ->
        true
    | (Cmp _ | Test _ | Alu { set_flags = true; _ } | Unary { set_flags = true; _ } | Set_flags _) :: _ ->
        false
    | _ :: rest -> check rest
  in
  check instrs

let rec block_consumes_flags blocks (target_id : int) (visited : (int, unit) Hashtbl.t) : bool =
  if Hashtbl.mem visited target_id then false
  else begin
    Hashtbl.replace visited target_id ();
    match Hashtbl.find_opt blocks target_id with
    | None -> true (* conservative: if target block not found in tbl, assume consumes flags *)
    | Some b ->
        if consumes_flags_before_def b.instrs then true
        else
          let rec defines_flags = function
            | [] -> false
            | (Cmp _ | Test _ | Alu { set_flags = true; _ } | Unary { set_flags = true; _ } | Set_flags _) :: _ ->
                true
            | _ :: rest -> defines_flags rest
          in
          if defines_flags b.instrs then false
          else
            match List.rev b.instrs with
            | Jmp (BlockId next_id) :: _ -> block_consumes_flags blocks next_id visited
            | _ -> false
  end

let generate_junk_ops rng ~gpr count : instr list =
  let vdst = Register.vx26 in
  let ops = [| Add; Sub; Xor; And; Or; Imul; Shl; Shr; Ror; Rol |] in
  let rec make_instrs n acc =
    if n <= 0 then List.rev acc
    else
      let imm = Int64.of_int32 (Random.State.int32 rng Int32.max_int) in
      let instr =
        match Random.State.int rng 6 with
        | 0 -> Mov { dst = Reg vdst; src = Imm imm }
        | 1 ->
            let op = ops.(Random.State.int rng (Array.length ops)) in
            Alu { op; dst = vdst; src1 = Reg vdst; src2 = Imm imm; set_flags = false }
        | 2 ->
            let op = ops.(Random.State.int rng (Array.length ops)) in
            Alu { op; dst = vdst; src1 = Reg vdst; src2 = Reg gpr; set_flags = false }
        | 3 ->
            let op = if Random.State.bool rng then Not else Neg in
            Unary { op; dst = vdst; src = Reg vdst; set_flags = false }
        | 4 ->
            Mov { dst = Reg vdst; src = Reg gpr }
        | _ ->
            let shift = Int64.of_int (Random.State.int rng 15 + 1) in
            Alu { op = Shl; dst = vdst; src1 = Reg vdst; src2 = Imm shift; set_flags = false }
      in
      make_instrs (n - 1) (instr :: acc)
  in
  make_instrs count []

let build_diamond_2way ~max_id ~rng ~gpr ~target_id ~func_name =
  incr max_id;
  let junk0_id = !max_id in
  incr max_id;
  let junk1_id = !max_id in
  let shift = Random.State.int rng 32 in
  let len0 = Random.State.int rng 3 + 1 in
  let len1 = Random.State.int rng 4 + 2 in
  let selector_instrs = [
    Mov { dst = Reg Register.vtmp3; src = Reg gpr };
    Alu { op = Shr; dst = Register.vtmp3; src1 = Reg Register.vtmp3; src2 = Imm (Int64.of_int shift); set_flags = false };
    Alu { op = And; dst = Register.vtmp3; src1 = Reg Register.vtmp3; src2 = Imm 1L; set_flags = false };
    Cmp { src1 = Reg Register.vtmp3; src2 = Imm 0L };
    Jcc { cond = Flags.E; target_true = BlockId junk0_id; target_false = BlockId junk1_id };
  ] in
  let junk0_block = {
    id = junk0_id;
    label = Printf.sprintf "%s_dkj0_%d" func_name junk0_id;
    instrs = generate_junk_ops rng ~gpr len0 @ [ Jmp (BlockId target_id) ];
  } in
  let junk1_block = {
    id = junk1_id;
    label = Printf.sprintf "%s_dkj1_%d" func_name junk1_id;
    instrs = generate_junk_ops rng ~gpr len1 @ [ Jmp (BlockId target_id) ];
  } in
  (selector_instrs, [ junk0_block; junk1_block ])

let build_diamond_4way ~max_id ~rng ~gpr ~target_id ~func_name =
  incr max_id;
  let mid_left_id = !max_id in
  incr max_id;
  let mid_right_id = !max_id in
  incr max_id;
  let junk0_id = !max_id in
  incr max_id;
  let junk1_id = !max_id in
  incr max_id;
  let junk2_id = !max_id in
  incr max_id;
  let junk3_id = !max_id in

  let shift = Random.State.int rng 32 in
  let len0 = Random.State.int rng 2 + 1 in
  let len1 = Random.State.int rng 3 + 2 in
  let len2 = Random.State.int rng 2 + 1 in
  let len3 = Random.State.int rng 4 + 2 in

  let selector_instrs = [
    Mov { dst = Reg Register.vtmp3; src = Reg gpr };
    Alu { op = Shr; dst = Register.vtmp3; src1 = Reg Register.vtmp3; src2 = Imm (Int64.of_int shift); set_flags = false };
    Alu { op = And; dst = Register.vtmp3; src1 = Reg Register.vtmp3; src2 = Imm 3L; set_flags = false };
    Cmp { src1 = Reg Register.vtmp3; src2 = Imm 1L };
    Jcc { cond = Flags.LE; target_true = BlockId mid_left_id; target_false = BlockId mid_right_id };
  ] in

  let mid_left_block = {
    id = mid_left_id;
    label = Printf.sprintf "%s_dkml_%d" func_name mid_left_id;
    instrs = [
      Cmp { src1 = Reg Register.vtmp3; src2 = Imm 0L };
      Jcc { cond = Flags.E; target_true = BlockId junk0_id; target_false = BlockId junk1_id };
    ];
  } in
  let mid_right_block = {
    id = mid_right_id;
    label = Printf.sprintf "%s_dkmr_%d" func_name mid_right_id;
    instrs = [
      Cmp { src1 = Reg Register.vtmp3; src2 = Imm 2L };
      Jcc { cond = Flags.E; target_true = BlockId junk2_id; target_false = BlockId junk3_id };
    ];
  } in

  let junk0_block = {
    id = junk0_id;
    label = Printf.sprintf "%s_dkj0_%d" func_name junk0_id;
    instrs = generate_junk_ops rng ~gpr len0 @ [ Jmp (BlockId target_id) ];
  } in
  let junk1_block = {
    id = junk1_id;
    label = Printf.sprintf "%s_dkj1_%d" func_name junk1_id;
    instrs = generate_junk_ops rng ~gpr len1 @ [ Jmp (BlockId target_id) ];
  } in
  let junk2_block = {
    id = junk2_id;
    label = Printf.sprintf "%s_dkj2_%d" func_name junk2_id;
    instrs = generate_junk_ops rng ~gpr len2 @ [ Jmp (BlockId target_id) ];
  } in
  let junk3_block = {
    id = junk3_id;
    label = Printf.sprintf "%s_dkj3_%d" func_name junk3_id;
    instrs = generate_junk_ops rng ~gpr len3 @ [ Jmp (BlockId target_id) ];
  } in

  (selector_instrs, [ mid_left_block; mid_right_block; junk0_block; junk1_block; junk2_block; junk3_block ])

let transform ?(density = 0.75) ?(split_blocks = true) ~rng (f : func) : func =
  let max_id = ref 0 in
  Hashtbl.iter (fun id _ -> if id > !max_id then max_id := id) f.cfg.blocks;
  let all_gprs = extract_func_gprs f in
  if all_gprs = [] then f
  else
    let threshold = int_of_float (density *. 100.0) in
    let new_blocks = ref [] in

    (* Phase 1: split large basic blocks at safe non-flag points to create more diamond opportunities *)
    let working_blocks = ref [] in
    Hashtbl.iter (fun _ (b : basic_block) ->
      if split_blocks && List.length b.instrs >= 8 && Random.State.int rng 100 < threshold then
        let split_idx = List.length b.instrs / 2 in
        let rec split n acc = function
          | [] -> (List.rev acc, [])
          | x :: xs when n = 0 -> (List.rev acc, x :: xs)
          | x :: xs -> split (n - 1) (x :: acc) xs
        in
        let (p1, p2) = split split_idx [] b.instrs in
        if not (consumes_flags_before_def p2) then begin
          incr max_id;
          let new_b2_id = !max_id in
          let b1 = { b with instrs = p1 @ [ Jmp (BlockId new_b2_id) ] } in
          let b2 = { id = new_b2_id; label = Printf.sprintf "%s_spl_%d" b.label new_b2_id; instrs = p2 } in
          working_blocks := b1 :: b2 :: !working_blocks
        end else
          working_blocks := b :: !working_blocks
      else
        working_blocks := b :: !working_blocks
    ) f.cfg.blocks;

    (* Build temporary blocks table to check flag consumption across targets *)
    let temp_tbl = Hashtbl.create (List.length !working_blocks + 16) in
    List.iter (fun (b : basic_block) -> Hashtbl.replace temp_tbl b.id b) !working_blocks;

    (* Phase 2: replace safe unconditional jumps with data-keyed diamonds *)
    List.iter (fun (b : basic_block) ->
      let b_rev = List.rev b.instrs in
      match b_rev with
      | Jmp (BlockId tid) :: body_rev when Random.State.int rng 100 < threshold ->
          let visited = Hashtbl.create 8 in
          if not (block_consumes_flags temp_tbl tid visited) then
            let local_gprs = extract_gprs b.instrs in
            let candidates = if local_gprs <> [] then local_gprs else all_gprs in
            let chosen_gpr = List.nth candidates (Random.State.int rng (List.length candidates)) in
            let use_4way = Random.State.bool rng in
            let (selector, diamond_blks) =
              if use_4way then
                build_diamond_4way ~max_id ~rng ~gpr:chosen_gpr ~target_id:tid ~func_name:f.name
              else
                build_diamond_2way ~max_id ~rng ~gpr:chosen_gpr ~target_id:tid ~func_name:f.name
            in
            let new_b_instrs = List.rev body_rev @ selector in
            new_blocks := { b with instrs = new_b_instrs } :: (diamond_blks @ !new_blocks)
          else
            new_blocks := b :: !new_blocks
      | _ ->
          new_blocks := b :: !new_blocks
    ) !working_blocks;

    let final_tbl = Hashtbl.create (List.length !new_blocks) in
    List.iter (fun (b : basic_block) -> Hashtbl.replace final_tbl b.id b) !new_blocks;
    { f with cfg = { f.cfg with blocks = final_tbl } }
