open Ir
open Register

let all_vtmps = [ vtmp0; vtmp1; vtmp2; vtmp3 ]

let canonical_vtmp = function
  | Vreg (VTMP0, _) -> Some vtmp0
  | Vreg (VTMP1, _) -> Some vtmp1
  | Vreg (VTMP2, _) -> Some vtmp2
  | Vreg (VTMP3, _) -> Some vtmp3
  | _ -> None

let is_vtmp (r : Register.t) : bool =
  canonical_vtmp r <> None

let vtmp_mem (r : Register.t) (l : Register.t list) : bool =
  match canonical_vtmp r with
  | Some cv -> List.mem cv l
  | None -> false

let of_reg r = match canonical_vtmp r with Some cv -> [cv] | None -> []

let of_op = function
  | Reg r -> of_reg r
  | Mem m ->
      (match m.base  with Some r -> of_reg r | None -> []) @
      (match m.index with Some (r,_) -> of_reg r | None -> [])
  | Imm _ -> []

let vtmps_referenced_by_instr (i : instr) : Register.t list =
  match i with
  | Nop | Ret | Vm_exit | Trap _ | Fence _ | Vm_enter
  | Bridge_to_flow _ | Bridge_to_math _ | Load_symbol _ | Cpuid | Fpu _ -> []
  | Mov { dst; src } -> of_op dst @ of_op src
  | Lea { dst; addr } ->
      of_reg dst @
      (match addr.base  with Some r -> of_reg r | None -> []) @
      (match addr.index with Some (r,_) -> of_reg r | None -> [])
  | Push op -> of_op op
  | Pop  op -> of_op op
  | Xchg (a, b) -> of_op a @ of_op b
  | Alu { dst; src1; src2; _ } -> of_reg dst @ of_op src1 @ of_op src2
  | Unary { dst; src; _ } -> of_reg dst @ of_op src
  | Cmp  { src1; src2 } -> of_op src1 @ of_op src2
  | Ccmp { src1; src2; _ } -> of_op src1 @ of_op src2
  | Ccmn { src1; src2; _ } -> of_op src1 @ of_op src2
  | Test { src1; src2 } -> of_op src1 @ of_op src2
  | Jmp _ | Jcc _ | Call _ -> []
  | Setcc { dst; _ } -> of_op dst
  | Cmov  { dst; src; _ } -> of_reg dst @ of_op src
  | Fp_conv { dst; src; _ } -> of_reg dst @ of_reg src
  | Fjcvtzs { dst; _ } -> of_reg dst
  | Atomic_mem { dst; addr; src; _ } -> of_reg dst @ of_reg addr @ of_reg src
  | Get_flags r -> of_reg r
  | Set_flags op -> of_op op
  | Pinsr { src2; _ } -> of_op src2
  | Pextr { dst; _ } -> of_op dst
  | Read_ssp { dst } -> of_reg dst
  | Inc_ssp _ -> []
  | _ -> []

let vtmps_read_by_instr (i : instr) : Register.t list =
  match i with
  | Nop | Ret | Vm_exit | Trap _ | Fence _ | Vm_enter
  | Bridge_to_flow _ | Bridge_to_math _ | Load_symbol _ | Cpuid | Fpu _ -> []
  | Mov { dst; src } ->
      (match dst with Mem _ -> of_op dst | _ -> []) @ of_op src
  | Lea { dst = _; addr } ->
      (match addr.base  with Some r -> of_reg r | None -> []) @
      (match addr.index with Some (r,_) -> of_reg r | None -> [])
  | Push op -> of_op op
  | Pop op -> (match op with Mem _ -> of_op op | _ -> [])
  | Xchg (a, b) -> of_op a @ of_op b
  | Alu { src1; src2; _ } -> of_op src1 @ of_op src2
  | Unary { src; _ } -> of_op src
  | Cmp { src1; src2 } | Ccmp { src1; src2; _ } | Ccmn { src1; src2; _ }
  | Test { src1; src2 } -> of_op src1 @ of_op src2
  | Jmp _ | Jcc _ | Call _ -> []
  | Setcc _ -> []
  | Cmov { dst; src; _ } -> of_reg dst @ of_op src
  | Fp_conv { src; _ } -> of_reg src
  | Fjcvtzs _ -> []
  | Atomic_mem { addr; src; _ } -> of_reg addr @ of_reg src
  | Get_flags _ -> []
  | Set_flags op -> of_op op
  | Pinsr { src2; _ } -> of_op src2
  | Pextr _ -> []
  | Read_ssp _ | Inc_ssp _ -> []
  | _ -> []

let vtmp_kills (i : instr) : Register.t list =
  match i with
  | Mov { dst = Reg d; _ } -> of_reg d
  | Lea { dst; _ } -> of_reg dst
  | Alu { dst; _ } -> of_reg dst
  | Unary { dst; _ } -> of_reg dst
  | Setcc { dst = Reg d; _ } -> of_reg d
  | Read_ssp { dst } -> of_reg dst
  | Get_flags d -> of_reg d
  | Pextr { dst = Reg d; _ } -> of_reg d
  | Atomic_mem { dst; _ } -> of_reg dst
  | Pop (Reg d) -> of_reg d
  | _ -> []

let compute_block_liveness (instrs : instr array) ~(live_out : Register.t list) :
    Register.t list array =
  let n = Array.length instrs in
  let live = Array.make (n + 1) [] in
  live.(n) <- live_out;
  let acc = ref live_out in
  for k = n - 1 downto 0 do
    let kills = vtmp_kills instrs.(k) in
    let reads = vtmps_read_by_instr instrs.(k) in
    let s = List.filter (fun r -> not (List.mem r kills)) !acc in
    let s = List.fold_left (fun a r -> if List.mem r a then a else r :: a) s reads in
    live.(k) <- s;
    acc := s
  done;
  live

let block_use_def (b : basic_block) : Register.t list * Register.t list =
  let use = ref [] and def = ref [] in
  List.iter (fun i ->
      let reads = vtmps_read_by_instr i in
      let kills = vtmp_kills i in
      List.iter (fun r ->
          if not (List.mem r !def) && not (List.mem r !use) then use := r :: !use)
        reads;
      List.iter (fun r ->
          if not (List.mem r !use) && not (List.mem r !def) then def := r :: !def)
        kills)
    b.instrs;
  (!use, !def)

let compute_func_live_outs (f : func) : (int, Register.t list) Hashtbl.t =
  let blocks = Hashtbl.fold (fun id b acc -> (id, b) :: acc) f.cfg.blocks [] in
  let label_to_id = Hashtbl.create 16 in
  List.iter (fun (_, b) -> Hashtbl.replace label_to_id b.label b.id) blocks;
  let resolve = function
    | Label l -> Hashtbl.find_opt label_to_id l
    | BlockId id -> Some id
    | TargetReg _ | TargetImm _ -> None
  in
  let succs_of id =
    match List.assoc_opt id blocks with
    | Some b ->
        let ts = successors b in
        if List.exists (fun t -> resolve t = None) ts then None
        else Some (List.filter_map resolve ts)
    | None -> Some []
  in
  let use_def = List.map (fun (id, b) -> (id, block_use_def b)) blocks in
  let use_of id = match List.assoc_opt id use_def with Some (u, _) -> u | None -> [] in
  let def_of id = match List.assoc_opt id use_def with Some (_, d) -> d | None -> [] in
  let live_in = Hashtbl.create 16 in
  List.iter (fun (id, _) -> Hashtbl.replace live_in id []) blocks;
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter (fun (id, _) ->
        let fold_succs acc s =
          match Hashtbl.find_opt live_in s with
          | Some l -> List.fold_left (fun a r -> if List.mem r a then a else r :: a) acc l
          | None -> acc
        in
        let out =
          match succs_of id with
          | None -> all_vtmps
          | Some ss -> List.fold_left fold_succs [] ss
        in
        let in_b =
          List.fold_left (fun acc r -> if List.mem r acc then acc else r :: acc)
            (List.filter (fun r -> List.mem r (use_of id) || not (List.mem r (def_of id))) out)
            (use_of id)
          |> List.sort_uniq compare
        in
        if in_b <> Hashtbl.find live_in id then begin
          Hashtbl.replace live_in id in_b;
          changed := true
        end)
      blocks
  done;
  let live_outs = Hashtbl.create 16 in
  List.iter (fun (id, _) ->
      let out =
        match succs_of id with
        | None -> all_vtmps
        | Some ss ->
            List.fold_left (fun acc s ->
                match Hashtbl.find_opt live_in s with
                | Some l -> List.fold_left (fun a r -> if List.mem r a then a else r :: a) acc l
                | None -> acc) [] ss
      in
      Hashtbl.replace live_outs id (List.sort_uniq compare out))
    blocks;
  live_outs
