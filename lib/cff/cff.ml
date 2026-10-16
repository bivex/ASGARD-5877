open Vm_ir

type cff_options = {
  inject_opaque_predicates : bool;
  obfuscate_states : bool;
  input_tainted_transitions : bool;
  split_rate : int;   (** 0..100: probability of splitting a block into two state aliases *)
  hub_count : int;    (** 1..6: number of dispatcher hubs for multi-hub partitioning *)
}

let default_cff_options = {
  inject_opaque_predicates = false;
  obfuscate_states = true;
  input_tainted_transitions = true;
  split_rate = 30;
  hub_count = 1;
}

let inject_opaque_predicate ?next_block_id ~rng ~trap_block_id (b : Ir.basic_block) =
  let target_next =
    match next_block_id with
    | Some id -> Ir.BlockId id
    | None -> (if b.label <> "" then Ir.Label b.label else Ir.BlockId b.id)
  in
  let variant = Random.State.int rng 3 in
  let opaque_check =
    match variant with
    | 0 ->
        (* Invariant 1 (Parity): (x & (x + 1)) & 1 == 0 for all integers *)
        [
          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.rax };
          Ir.Alu { op = Ir.Add; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = false };
          Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
          Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = true };
          Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 0L };
          Ir.Jcc { cond = Flags.NE; target_true = Ir.BlockId trap_block_id; target_false = target_next };
        ]
    | 1 ->
        (* Invariant 2 (Klimov-Shamir 2-adic): (x * (x + 1)) & 1 == 0 for all integers *)
        [
          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.rax };
          Ir.Alu { op = Ir.Add; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = false };
          Ir.Alu { op = Ir.Mul; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
          Ir.Alu { op = Ir.And; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 1L; set_flags = true };
          Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 0L };
          Ir.Jcc { cond = Flags.NE; target_true = Ir.BlockId trap_block_id; target_false = target_next };
        ]
    | _ ->
        (* Invariant 3 (Nilpotent Boolean MBA identity): ((x ^ c) ^ (x | c)) ^ (x & c) == 0 *)
        let c = 0x5877A564D00FL in
        [
          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.rax };
          Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm c };
          Ir.Mov { dst = Ir.Reg Register.vtmp2; src = Ir.Reg Register.vtmp0 };
          Ir.Alu { op = Ir.Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
          Ir.Alu { op = Ir.Or; dst = Register.vtmp2; src1 = Ir.Reg Register.vtmp2; src2 = Ir.Reg Register.vtmp1; set_flags = false };
          Ir.Alu { op = Ir.Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp2; set_flags = false };
          Ir.Mov { dst = Ir.Reg Register.vtmp2; src = Ir.Reg Register.rax };
          Ir.Alu { op = Ir.And; dst = Register.vtmp2; src1 = Ir.Reg Register.vtmp2; src2 = Ir.Reg Register.vtmp1; set_flags = false };
          Ir.Alu { op = Ir.Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp2; set_flags = true };
          Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 0L };
          Ir.Jcc { cond = Flags.NE; target_true = Ir.BlockId trap_block_id; target_false = target_next };
        ]
  in
  { b with instrs = opaque_check @ b.instrs }

module Node = struct
  type t = int
  let compare = Int.compare
  let hash = Hashtbl.hash
  let equal = ( = )
end

module CFG = Graph.Imperative.Digraph.ConcreteBidirectional(Node)
module Dfs = Graph.Traverse.Dfs(CFG)
module Bfs = Graph.Traverse.Bfs(CFG)
module Components = Graph.Components.Make(CFG)
module Topological = Graph.Topological.Make(CFG)
module Dominator = Graph.Dominator.Make(CFG)

type cfg_metrics = {
  num_vertices : int;
  num_edges : int;
  cyclomatic_complexity : int;
  scc_count : int;
  has_cycles : bool;
  loop_headers : int list;
}

let build_cfg (func : Ir.func) : CFG.t =
  let g = CFG.create () in
  let label_to_id = Hashtbl.create 16 in
  Hashtbl.iter (fun _ (b : Ir.basic_block) ->
    CFG.add_vertex g b.id;
    if b.label <> "" then Hashtbl.replace label_to_id b.label b.id
  ) func.cfg.blocks;

  let resolve_target = function
    | Ir.BlockId id -> Some id
    | Ir.Label lbl -> Hashtbl.find_opt label_to_id lbl
    | Ir.TargetImm _ | Ir.TargetReg _ -> None
  in

  Hashtbl.iter (fun _ (b : Ir.basic_block) ->
    match List.rev b.instrs with
    | [] -> ()
    | last :: _ -> (
        match last with
        | Ir.Jmp target -> (
            match resolve_target target with
            | Some tid -> CFG.add_edge g b.id tid
            | None -> ())
        | Ir.Jcc { target_true; target_false; _ } ->
            (match resolve_target target_true with
             | Some tid -> CFG.add_edge g b.id tid
             | None -> ());
            (match resolve_target target_false with
             | Some fid -> CFG.add_edge g b.id fid
             | None -> ())
        | _ -> ()
      )
  ) func.cfg.blocks;
  g

let analyze_cfg ?entry_id (g : CFG.t) : cfg_metrics =
  let num_vertices = CFG.nb_vertex g in
  let num_edges = CFG.nb_edges g in
  let cyclomatic_complexity = max 1 (num_edges - num_vertices + 2) in
  let sccs = Components.scc_list g in
  let scc_count = List.length sccs in
  let has_cycles =
    List.exists (fun scc ->
      match scc with
      | [] -> false
      | [v] -> CFG.mem_edge g v v
      | _ -> true
    ) sccs
  in
  let loop_headers =
    List.fold_left (fun acc scc ->
      let is_cyclic =
        match scc with
        | [] -> false
        | [v] -> CFG.mem_edge g v v
        | _ -> true
      in
      if not is_cyclic then acc
      else
        let scc_set = Hashtbl.create (List.length scc) in
        List.iter (fun v -> Hashtbl.replace scc_set v ()) scc;
        let headers =
          List.filter (fun v ->
            (match entry_id with Some eid -> v = eid | None -> false) ||
            List.exists (fun pred -> not (Hashtbl.mem scc_set pred)) (CFG.pred g v)
          ) scc
        in
        headers @ acc
    ) [] sccs
  in
  {
    num_vertices;
    num_edges;
    cyclomatic_complexity;
    scc_count;
    has_cycles;
    loop_headers = List.sort_uniq Int.compare loop_headers;
  }

let export_dot ?(name = "func_cfg") ?func (g : CFG.t) : string =
  let _ = name in
  let buf = Buffer.create 512 in
  let fmt = Format.formatter_of_buffer buf in
  let module Dot = Graph.Graphviz.Dot(struct
    include CFG
    let edge_attributes _ = []
    let default_edge_attributes _ = []
    let get_subgraph _ = None
    let vertex_attributes v =
      match func with
      | Some (f : Ir.func) -> (
          match Hashtbl.find_opt f.cfg.blocks v with
          | Some b ->
              let lbl =
                if b.label <> "" then
                  Printf.sprintf "bb_%d\\n(%s, %d instrs)" v b.label (List.length b.instrs)
                else
                  Printf.sprintf "bb_%d\\n(%d instrs)" v (List.length b.instrs)
              in
              [`Shape `Box; `Label lbl]
          | None -> [`Shape `Box; `Label (Printf.sprintf "bb_%d" v)])
      | None -> [`Shape `Box; `Label (Printf.sprintf "bb_%d" v)]
    let vertex_name v = Printf.sprintf "node_%d" v
    let default_vertex_attributes _ = []
    let graph_attributes _ = [`Rankdir `TopToBottom]
  end) in
  Dot.fprint_graph fmt g;
  Format.pp_print_flush fmt ();
  Buffer.contents buf

let reachable_blocks ~entry_id (g : CFG.t) : int list =
  let visited = Hashtbl.create 16 in
  let res = ref [] in
  if CFG.mem_vertex g entry_id then begin
    Dfs.prefix_component (fun v ->
      if not (Hashtbl.mem visited v) then begin
        Hashtbl.replace visited v ();
        res := v :: !res
      end
    ) g entry_id;
    List.rev !res
  end else []

let kronecker_product_states ~(base_states : int64 list) ~(dim : int) ~(seed : int64) : int64 list =
  let factors = List.init dim (fun i ->
    Int64.add seed (Int64.shift_left (Int64.of_int (i + 1)) 32)
  ) in
  List.concat_map (fun s ->
    List.map (fun f -> Int64.logxor s f) factors
  ) base_states

let split_hot_states ~(sorted_orig : Ir.basic_block list) ~(split_rate : int) ~rng ~(used_states : (int64, unit) Hashtbl.t) =
  let clone_map = Hashtbl.create (List.length sorted_orig) in
  let clone_entries = ref [] in
  if split_rate > 0 then
    List.iter
      (fun (b : Ir.basic_block) ->
        if Random.State.int rng 100 < split_rate then begin
          let rec gen_clone_state () =
            let s = Int64.logand (Int64.of_int32 (Random.State.int32 rng Int32.max_int)) 0xFFFFFFFEL in
            let s = if s = 0L then 0x200L else s in
            if Hashtbl.mem used_states s then gen_clone_state ()
            else begin
              Hashtbl.replace used_states s ();
              s
            end
          in
          let cs = gen_clone_state () in
          Hashtbl.replace clone_map b.id cs;
          clone_entries := (cs, b.id) :: !clone_entries
        end)
      sorted_orig;
  (clone_map, !clone_entries)

let emit_poly_hash64 ~dst ~src ~scratch =
  [
    Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg src };
    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg dst };
    Ir.Alu { op = Ir.Shr; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 30L; set_flags = false };
    Ir.Alu { op = Ir.Xor; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };
    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Imm 0xBF58476D1CE4E5B9L };
    Ir.Alu { op = Ir.Mul; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };

    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg dst };
    Ir.Alu { op = Ir.Shr; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 27L; set_flags = false };
    Ir.Alu { op = Ir.Xor; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };
    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Imm 0x94D049BB133111EBL };
    Ir.Alu { op = Ir.Mul; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };

    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg dst };
    Ir.Alu { op = Ir.Shr; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm 31L; set_flags = false };
    Ir.Alu { op = Ir.Xor; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };
  ]

let reg_base_eq (r1 : Register.t) (r2 : Register.t) : bool =
  match r1, r2 with
  | Register.Gpr (g1, _), Register.Gpr (g2, _) -> g1 = g2
  | Register.Vreg (v1, _), Register.Vreg (v2, _) -> v1 = v2
  | Register.Fpr (f1, _), Register.Fpr (f2, _) -> f1 = f2
  | _ -> false

let is_reg_read_in_op (op : Ir.operand) (target : Register.t) : bool =
  match op with
  | Ir.Reg r -> reg_base_eq r target
  | Ir.Mem m ->
      (match m.base with Some r -> reg_base_eq r target | None -> false) ||
      (match m.index with Some (r, _) -> reg_base_eq r target | None -> false)
  | Ir.Imm _ -> false

let is_reg_read_in_instr (instr : Ir.instr) (target : Register.t) : bool =
  match instr with
  | Ir.Mov { dst; src } ->
      (match dst with Ir.Mem m -> is_reg_read_in_op (Ir.Mem m) target | _ -> false)
      || is_reg_read_in_op src target
  | Ir.Lea { addr; _ } -> is_reg_read_in_op (Ir.Mem addr) target
  | Ir.Push op -> is_reg_read_in_op op target
  | Ir.Pop (Ir.Mem m) -> is_reg_read_in_op (Ir.Mem m) target
  | Ir.Xchg (op1, op2) -> is_reg_read_in_op op1 target || is_reg_read_in_op op2 target
  | Ir.Alu { op; dst; src1; src2; _ } ->
      if (op = Ir.Xor || op = Ir.Sub) && is_reg_read_in_op src1 target && is_reg_read_in_op src2 target && reg_base_eq dst target then
        false
      else
        is_reg_read_in_op src1 target || is_reg_read_in_op src2 target
  | Ir.Unary { src; _ } -> is_reg_read_in_op src target
  | Ir.Cmp { src1; src2 } -> is_reg_read_in_op src1 target || is_reg_read_in_op src2 target
  | Ir.Ccmp { src1; src2; _ } -> is_reg_read_in_op src1 target || is_reg_read_in_op src2 target
  | Ir.Ccmn { src1; src2; _ } -> is_reg_read_in_op src1 target || is_reg_read_in_op src2 target
  | Ir.Test { src1; src2 } -> is_reg_read_in_op src1 target || is_reg_read_in_op src2 target
  | Ir.Cmov { dst; src; _ } -> reg_base_eq dst target || is_reg_read_in_op src target
  | Ir.Set_flags op -> is_reg_read_in_op op target
  | Ir.Jmp (Ir.TargetReg r) -> reg_base_eq r target
  | Ir.Call (Ir.TargetReg r) -> reg_base_eq r target
  | _ -> false

let is_reg_written_in_instr (instr : Ir.instr) (target : Register.t) : bool =
  match instr with
  | Ir.Mov { dst = Ir.Reg d; _ } -> reg_base_eq d target
  | Ir.Lea { dst; _ } -> reg_base_eq dst target
  | Ir.Pop (Ir.Reg d) -> reg_base_eq d target
  | Ir.Xchg (Ir.Reg a, _) when reg_base_eq a target -> true
  | Ir.Xchg (_, Ir.Reg b) when reg_base_eq b target -> true
  | Ir.Alu { dst; _ } -> reg_base_eq dst target
  | Ir.Unary { dst; _ } -> reg_base_eq dst target
  | Ir.Setcc { dst = Ir.Reg d; _ } -> reg_base_eq d target
  | Ir.Cmov { dst; _ } -> reg_base_eq dst target
  | Ir.Get_flags d -> reg_base_eq d target
  | Ir.Load_symbol { dst; _ } -> reg_base_eq dst target
  | _ -> false

let is_read_before_written_in_block (b : Ir.basic_block) (target : Register.t) : bool option =
  let rec aux = function
    | [] -> None
    | instr :: rest ->
        if is_reg_read_in_instr instr target then Some true
        else if is_reg_written_in_instr instr target then Some false
        else aux rest
  in
  aux b.instrs

let select_input_reg (func : Ir.func) : Register.t option =
  let candidates = [
    Register.rdi; (* x86_64 arg0, ARM64 arg5 *)
    Register.rax; (* ARM64 arg0, RISC-V arg0 *)
    Register.rsi; (* x86_64 arg1, ARM64 arg4 *)
    Register.rcx; (* x86_64 arg3, ARM64 arg1 *)
    Register.rdx; (* x86_64 arg2, ARM64 arg2 *)
    Register.rbx; (* ARM64 arg3 *)
    Register.r8;  (* x86_64 arg4, ARM64 arg6 *)
    Register.r9;  (* x86_64 arg5, ARM64 arg7 *)
  ] in
  let is_read_before_written r =
    match Hashtbl.find_opt func.cfg.blocks func.cfg.entry_id with
    | Some entry_blk -> (
        match is_read_before_written_in_block entry_blk r with
        | Some true -> true
        | _ -> false
      )
    | None -> false
  in
  List.find_opt is_read_before_written candidates

let select_pinned_reg (func : Ir.func) : Register.t =
  let used = Hashtbl.create 32 in
  let mark_reg r =
    match r with
    | Register.Vreg (v, _) -> Hashtbl.replace used (Register.to_string (Register.Vreg (v, Register.B64))) ()
    | Register.Gpr (g, _) -> Hashtbl.replace used (Register.to_string (Register.Gpr (g, Register.B64))) ()
    | _ -> ()
  in
  let check_op = function
    | Ir.Reg r -> mark_reg r
    | Ir.Mem m ->
        (match m.base with Some r -> mark_reg r | None -> ());
        (match m.index with Some (r, _) -> mark_reg r | None -> ())
    | Ir.Imm _ -> ()
  in
  Hashtbl.iter (fun _ (b : Ir.basic_block) ->
    List.iter (function
      | Ir.Mov { dst; src } -> (match dst with Ir.Reg r -> mark_reg r | _ -> ()); check_op src
      | Ir.Lea { dst; addr } -> mark_reg dst; check_op (Ir.Mem addr)
      | Ir.Alu { dst; src1; src2; _ } -> mark_reg dst; check_op src1; check_op src2
      | Ir.Unary { dst; src; _ } -> mark_reg dst; check_op src
      | Ir.Cmp { src1; src2 } -> check_op src1; check_op src2
      | Ir.Ccmp { src1; src2; _ } -> check_op src1; check_op src2
      | Ir.Ccmn { src1; src2; _ } -> check_op src1; check_op src2
      | Ir.Test { src1; src2 } -> check_op src1; check_op src2
      | Ir.Cmov { dst; src; _ } -> mark_reg dst; check_op src
      | Ir.Setcc { dst; _ } -> check_op dst
      | Ir.Get_flags r -> mark_reg r
      | Ir.Set_flags op -> check_op op
      | Ir.Push op | Ir.Pop op -> check_op op
      | Ir.Xchg (op1, op2) -> check_op op1; check_op op2
      | Ir.Load_symbol { dst; _ } -> mark_reg dst
      | Ir.Jmp (Ir.TargetReg r) | Ir.Call (Ir.TargetReg r) -> mark_reg r
      | _ -> ()
    ) b.instrs
  ) func.cfg.blocks;
  (* Exclude VX26 (junk instruction decoy target) and VX25 (fs_base) *)
  let candidates = [
    Register.vx19; Register.vx20; Register.vx21; Register.vx22;
    Register.vx23; Register.vx24; Register.vx18;
    Register.r15; Register.r14; Register.r13; Register.r12; Register.rbx;
  ] in
  match List.find_opt (fun r -> not (Hashtbl.mem used (Register.to_string r))) candidates with
  | Some r -> r
  | None -> Register.vx19


let flatten_func ?(options = default_cff_options) ~rng (func : Ir.func) =
  let cfg = build_cfg func in
  let metrics = analyze_cfg ~entry_id:func.cfg.entry_id cfg in
  let original_blocks = Hashtbl.fold (fun _ b acc -> b :: acc) func.cfg.blocks [] in
  let sorted_orig = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) original_blocks in
  let n = List.length sorted_orig in
  if n <= 1 || metrics.num_vertices <= 1 then
    (* Trivial 1-block function doesn't need flattening *)
    Ok func
  else
    let max_id = List.fold_left (fun acc (b : Ir.basic_block) -> max acc b.id) 0 sorted_orig in
    let entry_block_id = max_id + 1 in
    let trap_block_id = max_id + 2 in
    let disp_base_id = max_id + 3 in

    let input_reg_opt = select_input_reg func in
    let is_tainted = options.input_tainted_transitions && Option.is_some input_reg_opt in
    let pinned_reg =
      if is_tainted then select_pinned_reg func
      else Register.vx19
    in


    (* Secret affine parameters for non-linear slot coding *)
    let secret_salt =
      let s = Random.State.int64 rng Int64.max_int in
      if s = 0L then 0x5877CAFE1337BEEFL else s
    in
    let stride =
      let s = Random.State.int64 rng Int64.max_int in
      let s = Int64.logor s 1L in
      if s = 0L then 0x9E3779B97F4A7C15L else s
    in
    let stride_inv = Rolling_key.mod_inverse_64 stride in

    (* Gather all target block IDs (primary blocks + alias clones) *)
    let (_, clone_entries_list) =
      split_hot_states ~sorted_orig ~split_rate:options.split_rate ~rng ~used_states:(Hashtbl.create 16)
    in
    let clone_bids = List.map snd clone_entries_list in
    let primary_bids = List.map (fun (b : Ir.basic_block) -> b.id) sorted_orig in
    let all_bids = primary_bids @ clone_bids in
    let total_disp = List.length all_bids in
    let targets_array = Array.of_list all_bids in

    (* Fisher-Yates shuffle targets_array if obfuscate_states *)
    if options.obfuscate_states then begin
      for i = total_disp - 1 downto 1 do
        let j = Random.State.int rng (i + 1) in
        let tmp = targets_array.(i) in
        targets_array.(i) <- targets_array.(j);
        targets_array.(j) <- tmp
      done
    end;

    (* Assign secret 64-bit state tokens to each slot:
       coded_i = secret_salt + i * stride
       state_i = poly_unhash64 coded_i
       And populate state_pool mapping bid -> state list *)
    let state_pool = Hashtbl.create n in
    for slot_idx = 0 to total_disp - 1 do
      let bid = targets_array.(slot_idx) in
      let coded = Int64.add secret_salt (Int64.mul (Int64.of_int slot_idx) stride) in
      let state = Rolling_key.poly_unhash64 coded in
      let cur = match Hashtbl.find_opt state_pool bid with Some l -> l | None -> [] in
      Hashtbl.replace state_pool bid (state :: cur)
    done;

    let get_target_state bid =
      match Hashtbl.find_opt state_pool bid with
      | Some (_ :: _) ->
          let pool = Hashtbl.find state_pool bid in
          List.nth pool (Random.State.int rng (List.length pool))
      | _ ->
          let coded = secret_salt in
          Rolling_key.poly_unhash64 coded
    in

    let emit_set_state_tainted dst_reg target_state =
      if is_tainted then
        (emit_poly_hash64 ~dst:Register.vtmp2 ~src:pinned_reg ~scratch:Register.vtmp3)
        @ [
          Ir.Mov { dst = Ir.Reg dst_reg; src = Ir.Imm target_state };
          Ir.Alu { op = Ir.Xor; dst = dst_reg; src1 = Ir.Reg dst_reg; src2 = Ir.Reg Register.vtmp2; set_flags = false };
        ]
      else
        [
          Ir.Mov { dst = Ir.Reg dst_reg; src = Ir.Imm target_state };
        ]
    in

    (* Entry Block: pins input to pinned_reg, sets state to func.cfg.entry_id's state and jumps to disp_base_id *)
    let initial_state = get_target_state func.cfg.entry_id in
    let entry_instrs =
      (if is_tainted then
         [ Ir.Mov { dst = Ir.Reg pinned_reg; src = Ir.Reg (Option.get input_reg_opt) } ]
       else
         [])
      @ (emit_set_state_tainted Register.vkey initial_state) @ [
        Ir.Jmp (Ir.BlockId disp_base_id);
      ]
    in
    let entry_block = Ir.make_block ~id:entry_block_id ~label:(func.name ^ "_cff_entry") ~instrs:entry_instrs in

    (* Trap Block *)
    let trap_block = Ir.make_block ~id:trap_block_id ~label:(func.name ^ "_cff_trap") ~instrs:[ Ir.Trap "CFF State Violation" ] in

    (* Binary Decision Tree Construction *)
    let next_fresh_id = ref (disp_base_id + 1) in
    let tree_blocks = ref [] in
    let rec build_tree low high =
      if low = high then
        Ir.BlockId targets_array.(low)
      else
        let mid = (low + high) / 2 in
        let left_target = build_tree low mid in
        let right_target = build_tree (mid + 1) high in
        let node_id = !next_fresh_id in
        incr next_fresh_id;
        let instrs = [
          Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm (Int64.of_int mid) };
          Ir.Jcc { cond = Flags.LE; target_true = left_target; target_false = right_target };
        ] in
        let blk = Ir.make_block ~id:node_id ~label:(Printf.sprintf "%s_cff_tree_%d" func.name node_id) ~instrs in
        tree_blocks := blk :: !tree_blocks;
        Ir.BlockId node_id
    in
    let tree_root_target = build_tree 0 (total_disp - 1) in

    (* Dispatcher Entry Block: unmasks dynamic taint, computes poly_hash64, decodes slot *)
    let disp_entry_instrs =
      (if is_tainted then
         (emit_poly_hash64 ~dst:Register.vtmp2 ~src:pinned_reg ~scratch:Register.vtmp3)
         @ [
           Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.vkey };
           Ir.Alu { op = Ir.Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp2; set_flags = false };
         ]
       else
         [
           Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.vkey };
         ])
      @ (emit_poly_hash64 ~dst:Register.vtmp0 ~src:Register.vtmp0 ~scratch:Register.vtmp1)
      @ [
        Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm secret_salt };
        Ir.Alu { op = Ir.Sub; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
        Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm stride_inv };
        Ir.Alu { op = Ir.Mul; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
        Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm (Int64.of_int total_disp) };
        Ir.Jcc { cond = Flags.AE; target_true = Ir.BlockId trap_block_id; target_false = tree_root_target };
      ]
    in
    let disp_entry_block = Ir.make_block ~id:disp_base_id ~label:(func.name ^ "_disp_entry") ~instrs:disp_entry_instrs in

    (* Transform each original block: redirect control flow back to disp_base_id *)
    let transformed_blocks =
      List.concat_map
        (fun (b : Ir.basic_block) ->
          let rev_instrs = List.rev b.instrs in
          let new_instrs =
            match rev_instrs with
            | [] -> [ Ir.Jmp (Ir.BlockId disp_base_id) ]
            | last :: body_rev -> (
                let body = List.rev body_rev in
                match last with
                | Ir.Jmp (Ir.BlockId target_id) ->
                    let next_state = get_target_state target_id in
                    body @ (emit_set_state_tainted Register.vkey next_state) @ [
                      Ir.Jmp (Ir.BlockId disp_base_id);
                    ]
                | Ir.Jcc { cond; target_true = Ir.BlockId t_id; target_false = Ir.BlockId f_id } ->
                    let state_true = get_target_state t_id in
                    let state_false = get_target_state f_id in
                    let setup_states =
                      if is_tainted then
                        (emit_poly_hash64 ~dst:Register.vtmp2 ~src:pinned_reg ~scratch:Register.vtmp0)
                        @ [
                          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm state_true };
                          Ir.Alu { op = Ir.Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp2; set_flags = false };
                          Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm state_false };
                          Ir.Alu { op = Ir.Xor; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp1; src2 = Ir.Reg Register.vtmp2; set_flags = false };
                        ]
                      else
                        [
                          Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Imm state_true };
                          Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm state_false };
                        ]
                    in
                    let emit_direct_cmp src1 src2 prev_body_rev =
                      let prev_body = List.rev prev_body_rev in
                      prev_body @ setup_states @ [
                        Ir.Cmp { src1; src2 };
                        Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                        Ir.Mov { dst = Ir.Reg Register.vkey; src = Ir.Reg Register.vtmp1 };
                        Ir.Jmp (Ir.BlockId disp_base_id);
                      ]
                    in
                    (match body_rev with
                    | Ir.Cmp { src1 = Ir.Reg _ as src1; src2 = Ir.Reg _ as src2 } :: prev_body_rev ->
                        emit_direct_cmp src1 src2 prev_body_rev
                    | Ir.Cmp { src1 = Ir.Reg _ as src1; src2 = Ir.Imm imm as src2 } :: prev_body_rev
                      when imm >= -2147483648L && imm <= 2147483647L ->
                        emit_direct_cmp src1 src2 prev_body_rev
                    | _ ->
                        body @ [ Ir.Get_flags Register.vtmp3 ] @ setup_states @ [
                          Ir.Set_flags (Ir.Reg Register.vtmp3);
                          Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                          Ir.Mov { dst = Ir.Reg Register.vkey; src = Ir.Reg Register.vtmp1 };
                          Ir.Jmp (Ir.BlockId disp_base_id);
                        ])
                | Ir.Ret | Ir.Vm_exit | Ir.Trap _ ->
                    b.instrs
                | other ->
                    let next_state = get_target_state (b.id + 1) in
                    body @ [ other ] @ (emit_set_state_tainted Register.vkey next_state) @ [
                      Ir.Jmp (Ir.BlockId disp_base_id);
                    ])
          in
          if options.inject_opaque_predicates && b.id <> func.cfg.entry_id then
            let body_id = !next_fresh_id in
            incr next_fresh_id;
            let pred_block =
              inject_opaque_predicate ~next_block_id:body_id ~rng ~trap_block_id
                { b with instrs = [] }
            in
            let body_block = Ir.make_block ~id:body_id ~label:(b.label ^ "_body") ~instrs:new_instrs in
            [ pred_block; body_block ]
          else
            [ { b with instrs = new_instrs } ])
        sorted_orig
    in

    let all_blocks = (entry_block :: trap_block :: disp_entry_block :: !tree_blocks) @ transformed_blocks in
    let new_func = Ir.make_func ~name:func.name ~entry_id:entry_block_id ~blocks:all_blocks in
    Ok new_func

module Pop_coupler = Pop_coupler
