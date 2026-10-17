open Ir

type base_reg =
  | BG of Register.gpr
  | BV of Register.vreg
  | BF of int

let base_of_reg = function
  | Register.Gpr (g, _) -> BG g
  | Register.Vreg (v, _) -> BV v
  | Register.Fpr (i, _) -> BF i

let rsp_base = BG Register.RSP

let regs_of_mem_ref (m : mem_ref) : base_reg list =
  let b = match m.base with Some r -> [ base_of_reg r ] | None -> [] in
  let idx = match m.index with Some (r, _) -> [ base_of_reg r ] | None -> [] in
  b @ idx

let regs_of_operand = function
  | Reg r -> [ base_of_reg r ]
  | Imm _ -> []
  | Mem m -> regs_of_mem_ref m

type node_effect = {
  defs_reg : base_reg list;
  uses_reg : base_reg list;
  defs_flags : bool;
  uses_flags : bool;
  has_mem : bool;
  is_barrier : bool;
  is_terminator : bool;
  is_alu : bool;
}

let analyze_instr (i : instr) : node_effect =
  match i with
  | Nop ->
      { defs_reg = []; uses_reg = []; defs_flags = false; uses_flags = false; has_mem = false; is_barrier = false; is_terminator = false; is_alu = false }
  | Mov { dst = Reg d; src } ->
      let has_mem = match src with Mem _ -> true | _ -> false in
      { defs_reg = [ base_of_reg d ]; uses_reg = regs_of_operand src; defs_flags = false; uses_flags = false; has_mem; is_barrier = false; is_terminator = false; is_alu = false }
  | Mov { dst = Mem m; src } ->
      let uses = regs_of_mem_ref m @ regs_of_operand src in
      { defs_reg = []; uses_reg = uses; defs_flags = false; uses_flags = false; has_mem = true; is_barrier = false; is_terminator = false; is_alu = false }
  | Mov _ ->
      { defs_reg = []; uses_reg = []; defs_flags = false; uses_flags = false; has_mem = false; is_barrier = false; is_terminator = false; is_alu = false }
  | Lea { dst; addr } ->
      { defs_reg = [ base_of_reg dst ]; uses_reg = regs_of_mem_ref addr; defs_flags = false; uses_flags = false; has_mem = false; is_barrier = false; is_terminator = false; is_alu = false }
  | Push op ->
      { defs_reg = [ rsp_base ]; uses_reg = rsp_base :: regs_of_operand op; defs_flags = false; uses_flags = false; has_mem = true; is_barrier = false; is_terminator = false; is_alu = false }
  | Pop (Reg r) ->
      { defs_reg = [ rsp_base; base_of_reg r ]; uses_reg = [ rsp_base ]; defs_flags = false; uses_flags = false; has_mem = true; is_barrier = false; is_terminator = false; is_alu = false }
  | Pop (Mem m) ->
      { defs_reg = [ rsp_base ]; uses_reg = rsp_base :: regs_of_mem_ref m; defs_flags = false; uses_flags = false; has_mem = true; is_barrier = false; is_terminator = false; is_alu = false }
  | Pop _ ->
      { defs_reg = [ rsp_base ]; uses_reg = [ rsp_base ]; defs_flags = false; uses_flags = false; has_mem = true; is_barrier = false; is_terminator = false; is_alu = false }
  | Xchg (op1, op2) ->
      let defs = regs_of_operand op1 @ regs_of_operand op2 in
      let uses = defs in
      let has_mem = match op1, op2 with Mem _, _ | _, Mem _ -> true | _ -> false in
      { defs_reg = defs; uses_reg = uses; defs_flags = false; uses_flags = false; has_mem; is_barrier = false; is_terminator = false; is_alu = false }
  | Alu { op; dst; src1; src2; set_flags } ->
      let uses_flags = (op = Adc || op = Sbb) in
      let has_mem = match src1, src2 with Mem _, _ | _, Mem _ -> true | _ -> false in
      { defs_reg = [ base_of_reg dst ]; uses_reg = regs_of_operand src1 @ regs_of_operand src2; defs_flags = set_flags; uses_flags; has_mem; is_barrier = false; is_terminator = false; is_alu = true }
  | Unary { op = _; dst; src; set_flags } ->
      let has_mem = match src with Mem _ -> true | _ -> false in
      { defs_reg = [ base_of_reg dst ]; uses_reg = regs_of_operand src; defs_flags = set_flags; uses_flags = false; has_mem; is_barrier = false; is_terminator = false; is_alu = false }
  | Cmp { src1; src2 } | Test { src1; src2 } ->
      let has_mem = match src1, src2 with Mem _, _ | _, Mem _ -> true | _ -> false in
      { defs_reg = []; uses_reg = regs_of_operand src1 @ regs_of_operand src2; defs_flags = true; uses_flags = false; has_mem; is_barrier = false; is_terminator = false; is_alu = false }
  | Ccmp { src1; src2; _ } | Ccmn { src1; src2; _ } ->
      let has_mem = match src1, src2 with Mem _, _ | _, Mem _ -> true | _ -> false in
      { defs_reg = []; uses_reg = regs_of_operand src1 @ regs_of_operand src2; defs_flags = true; uses_flags = true; has_mem; is_barrier = false; is_terminator = false; is_alu = false }
  | Setcc { dst; _ } ->
      let has_mem = match dst with Mem _ -> true | _ -> false in
      { defs_reg = regs_of_operand dst; uses_reg = []; defs_flags = false; uses_flags = true; has_mem; is_barrier = false; is_terminator = false; is_alu = false }
  | Cmov { dst; src; _ } ->
      let has_mem = match src with Mem _ -> true | _ -> false in
      { defs_reg = [ base_of_reg dst ]; uses_reg = base_of_reg dst :: regs_of_operand src; defs_flags = false; uses_flags = true; has_mem; is_barrier = false; is_terminator = false; is_alu = false }
  | Load_symbol { dst; _ } ->
      { defs_reg = [ base_of_reg dst ]; uses_reg = []; defs_flags = false; uses_flags = false; has_mem = false; is_barrier = false; is_terminator = false; is_alu = false }
  | Get_flags r ->
      { defs_reg = [ base_of_reg r ]; uses_reg = []; defs_flags = false; uses_flags = true; has_mem = false; is_barrier = false; is_terminator = false; is_alu = false }
  | Set_flags op ->
      let has_mem = match op with Mem _ -> true | _ -> false in
      { defs_reg = []; uses_reg = regs_of_operand op; defs_flags = true; uses_flags = false; has_mem; is_barrier = false; is_terminator = false; is_alu = false }
  | Jmp _ | Jcc _ | Call _ | Ret | Vm_enter | Vm_exit | Trap _ ->
      { defs_reg = []; uses_reg = []; defs_flags = false; uses_flags = false; has_mem = false; is_barrier = true; is_terminator = true; is_alu = false }
  | _ ->
      (* Conservative barrier for vector / fp / atomic / bridges *)
      { defs_reg = []; uses_reg = []; defs_flags = true; uses_flags = true; has_mem = true; is_barrier = true; is_terminator = false; is_alu = false }

let lists_overlap l1 l2 =
  List.exists (fun x -> List.mem x l2) l1

let is_vtmp_base = function
  | BV Register.VTMP0 | BV Register.VTMP1 | BV Register.VTMP2 | BV Register.VTMP3 -> true
  | _ -> false

let has_vtmp (eff : node_effect) : bool =
  List.exists is_vtmp_base eff.defs_reg || List.exists is_vtmp_base eff.uses_reg

let has_dependency (prev : node_effect) (next : node_effect) : bool =
  if prev.is_barrier || next.is_barrier then true
  else if prev.has_mem && next.has_mem then true
  else if (prev.defs_flags || prev.uses_flags) && (next.defs_flags || next.uses_flags) then true
  else if (has_vtmp prev && next.is_alu) || (prev.is_alu && has_vtmp next) then true
  else if has_vtmp prev && has_vtmp next then true
  else if lists_overlap prev.defs_reg next.uses_reg then true (* RAW *)
  else if lists_overlap prev.uses_reg next.defs_reg then true (* WAR *)
  else if lists_overlap prev.defs_reg next.defs_reg then true (* WAW *)
  else false

let schedule_block ~rng (b : basic_block) : basic_block =
  let instrs = b.instrs in
  let n = List.length instrs in
  if n <= 2 then b
  else
    let arr = Array.of_list instrs in
    (* Split off trailing terminators so they stay anchored at the end *)
    let term_count = ref 0 in
    while !term_count < n && (analyze_instr arr.(n - 1 - !term_count)).is_terminator do
      incr term_count
    done;
    let sched_len = n - !term_count in
    if sched_len <= 1 then b
    else
      let effects = Array.init sched_len (fun i -> analyze_instr arr.(i)) in
      let succs = Array.make sched_len [] in
      let in_degree = Array.make sched_len 0 in

      for i = 0 to sched_len - 1 do
        for j = i + 1 to sched_len - 1 do
          if has_dependency effects.(i) effects.(j) then (
            succs.(i) <- j :: succs.(i);
            in_degree.(j) <- in_degree.(j) + 1
          )
        done
      done;

      let ready = ref [] in
      for i = 0 to sched_len - 1 do
        if in_degree.(i) = 0 then ready := i :: !ready
      done;

      let scheduled = ref [] in
      while !ready <> [] do
        let len = List.length !ready in
        let idx = Random.State.int rng len in
        let rec pick_nth i acc = function
          | [] -> failwith "dag_scheduler: empty ready list"
          | hd :: tl when i = 0 -> (hd, List.rev acc @ tl)
          | hd :: tl -> pick_nth (i - 1) (hd :: acc) tl
        in
        let chosen, remaining = pick_nth idx [] !ready in
        ready := remaining;
        scheduled := arr.(chosen) :: !scheduled;

        List.iter (fun s ->
          in_degree.(s) <- in_degree.(s) - 1;
          if in_degree.(s) = 0 then ready := s :: !ready
        ) succs.(chosen)
      done;

      let terminators =
        List.init !term_count (fun k -> arr.(sched_len + k))
      in
      let new_instrs = List.rev !scheduled @ terminators in
      { b with instrs = new_instrs }

let transform ~rng (f : func) : func =
  let new_tbl = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
  Hashtbl.iter (fun id b ->
    let b' = schedule_block ~rng b in
    Hashtbl.replace new_tbl id b'
  ) f.cfg.blocks;
  { f with cfg = { f.cfg with blocks = new_tbl } }
