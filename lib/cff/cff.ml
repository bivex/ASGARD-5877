open Vm_ir
open Random_visa_constants.Magic_numbers

type cff_options = {
  inject_opaque_predicates : bool;
  obfuscate_states : bool;
  input_tainted_transitions : bool;
  split_rate : int;   (** 0..100: probability of splitting a block into two state aliases *)
  hub_count : int;    (** 1..6: number of dispatcher hubs for multi-hub partitioning *)
  pop_digest : (Register.t * int64) option;
  red_herring : bool;
}

let default_cff_options = {
  inject_opaque_predicates = false;
  obfuscate_states = true;
  input_tainted_transitions = true;
  split_rate = 30;
  hub_count = 1;
  pop_digest = None;
  red_herring = true;
}

let inject_opaque_predicate ?next_block_id ~rng ~trap_block_id (b : Ir.basic_block) =
  let target_next =
    match next_block_id with
    | Some id -> Ir.BlockId id
    | None -> (if b.label <> "" then Ir.Label b.label else Ir.BlockId b.id)
  in
  let all_v = Cff_opaque_catalog.all_variants in
  let variant = all_v.(Random.State.int rng (Array.length all_v)) in
  let c = Int64.logor (Random.State.int64 rng Int64.max_int) 1L in
  let pred_instrs =
    Cff_opaque_catalog.emit_ir_predicate
      ~variant ~src_reg:Register.rax ~dst_reg:Register.vtmp0 ~c
  in
  let cmp_and_branch = [
    Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm 0L };
    Ir.Jcc { cond = Flags.NE; target_true = Ir.BlockId trap_block_id; target_false = target_next };
  ] in
  { b with instrs = pred_instrs @ cmp_and_branch @ b.instrs }

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

let split_hot_states ?(red_herring = true) ?(seed = salt_xwcafe_leetbeef) ~(sorted_orig : Ir.basic_block list) ~(split_rate : int) ~rng ~(used_states : (int64, unit) Hashtbl.t) () =
  let clone_map = Hashtbl.create (List.length sorted_orig) in
  let clone_entries = ref [] in
  if split_rate > 0 then
    List.iter
      (fun (b : Ir.basic_block) ->
        let eff_rate =
          if red_herring then
            Red_herring.modulate_split_rate ~base_rate:split_rate ~seed ~block_id:b.id
          else split_rate
        in
        if eff_rate > 0 && Random.State.int rng 100 < eff_rate then begin
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

type hash_params = {
  m1 : int64;
  m2 : int64;
  s1 : int;
  s2 : int;
  s3 : int;
}

let gen_hash_params rng =
  let m1 = Int64.logor (Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) 1L in
  let m2 = Int64.logor (Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) 1L in
  let s1 = 20 + Random.State.int rng 12 in
  let s2 = 20 + Random.State.int rng 12 in
  let s3 = 20 + Random.State.int rng 12 in
  { m1; m2; s1; s2; s3 }

let unshift_xor_right (y : int64) (shift : int) : int64 =
  let rec loop acc s =
    if s >= 64 then acc
    else loop (Int64.logxor acc (Int64.shift_right_logical y s)) (s + shift)
  in
  loop y shift

let poly_unhash64_dyn hparams y =
  let x2 = unshift_xor_right y hparams.s3 in
  let inv2 = Rolling_key.mod_inverse_64 hparams.m2 in
  let w1 = Int64.mul x2 inv2 in
  let x1 = unshift_xor_right w1 hparams.s2 in
  let inv1 = Rolling_key.mod_inverse_64 hparams.m1 in
  let w0 = Int64.mul x1 inv1 in
  unshift_xor_right w0 hparams.s1

let emit_poly_hash64 ?(rng = None) ~hparams ~dst ~src ~scratch () =
  let jitter () =
    match rng with
    | None -> []
    | Some r ->
        match Random.State.int r 4 with
        | 0 -> []
        | 1 -> [
            Ir.Alu { op = Ir.Xor; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Reg scratch; set_flags = false }
          ]
        | 2 -> [
            Ir.Alu { op = Ir.Rol; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Imm 7L; set_flags = false }
          ]
        | _ -> [
            Ir.Alu { op = Ir.Add; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Imm 0x1337L; set_flags = false }
          ]
  in
  [
    Ir.Mov { dst = Ir.Reg dst; src = Ir.Reg src };
    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg dst };
    Ir.Alu { op = Ir.Shr; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm (Int64.of_int hparams.s1); set_flags = false };
    Ir.Alu { op = Ir.Xor; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };
    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Imm hparams.m1 };
    Ir.Alu { op = Ir.Mul; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };
  ]
  @ jitter ()
  @ [
    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg dst };
    Ir.Alu { op = Ir.Shr; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm (Int64.of_int hparams.s2); set_flags = false };
    Ir.Alu { op = Ir.Xor; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };
    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Imm hparams.m2 };
    Ir.Alu { op = Ir.Mul; dst; src1 = Ir.Reg dst; src2 = Ir.Reg scratch; set_flags = false };
  ]
  @ jitter ()
  @ [
    Ir.Mov { dst = Ir.Reg scratch; src = Ir.Reg dst };
    Ir.Alu { op = Ir.Shr; dst = scratch; src1 = Ir.Reg scratch; src2 = Ir.Imm (Int64.of_int hparams.s3); set_flags = false };
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
  | Ir.Cpuid -> reg_base_eq Register.rax target || reg_base_eq Register.rcx target
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
  | Ir.Cpuid ->
      reg_base_eq Register.rax target || reg_base_eq Register.rbx target
      || reg_base_eq Register.rcx target || reg_base_eq Register.rdx target
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

let select_pinned_reg (func : Ir.func) : Register.t option =
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
      | Ir.Cpuid ->
          mark_reg Register.rax; mark_reg Register.rbx; mark_reg Register.rcx; mark_reg Register.rdx
      | _ -> ()
    ) b.instrs
  ) func.cfg.blocks;
  (* Exclude VX26 (junk instruction decoy target) and VX25 (fs_base) *)
  let candidates = [
    Register.vx19; Register.vx20; Register.vx21; Register.vx22;
    Register.vx23; Register.vx24;
    Register.r15; Register.r14; Register.r13; Register.r12; Register.rbx;
  ] in
  List.find_opt (fun r -> not (Hashtbl.mem used (Register.to_string r))) candidates


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
    let disp_base_id = max_id + 2 in
    let next_fresh_id = ref (disp_base_id + 1) in
    let trap_blocks = ref [] in
    let make_trap_block ~reason =
      let t_id = !next_fresh_id in
      incr next_fresh_id;
      let label = Printf.sprintf "%s_tk_%d" func.name t_id in
      let dummy_c = Random.State.int64 rng Int64.max_int in
      let trap_instrs = match Random.State.int rng 3 with
        | 0 ->
            [ Ir.Alu { op = Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm dummy_c; set_flags = false };
              Ir.Trap reason ]
        | 1 ->
            [ Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm dummy_c };
              Ir.Alu { op = Sub; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp1; src2 = Ir.Imm 1L; set_flags = true };
              Ir.Trap reason ]
        | _ ->
            [ Ir.Trap reason ]
      in
      let blk = Ir.make_block ~id:t_id ~label ~instrs:trap_instrs in
      trap_blocks := blk :: !trap_blocks;
      t_id
    in

    let input_reg_opt = select_input_reg func in
    let pinned_reg_opt =
      if options.input_tainted_transitions then select_pinned_reg func
      else None
    in
    let is_tainted = Option.is_some input_reg_opt && Option.is_some pinned_reg_opt in
    let pinned_reg =
      match pinned_reg_opt with
      | Some r -> r
      | None -> Register.vx19
    in


    (* Secret affine parameters for non-linear slot coding *)
    let secret_salt =
      let s = Random.State.int64 rng Int64.max_int in
      if s = 0L then salt_xwcafe_leetbeef else s
    in
    let stride =
      let s = Random.State.int64 rng Int64.max_int in
      let s = Int64.logor s 1L in
      if s = 0L then 0x9E3779B97F4A7C15L else s
    in
    let stride_inv = Rolling_key.mod_inverse_64 stride in
    let hparams = gen_hash_params rng in

    (* Gather all target block IDs (primary blocks + alias clones) *)
    let (_, clone_entries_list) =
      split_hot_states ~red_herring:options.red_herring ~seed:secret_salt ~sorted_orig ~split_rate:options.split_rate ~rng ~used_states:(Hashtbl.create 16) ()
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
       state_i = poly_unhash64_dyn hparams coded_i
       And populate state_pool mapping bid -> state list *)
    let num_hubs = max 1 (min options.hub_count total_disp) in
    next_fresh_id := disp_base_id + num_hubs;
    let thunk_blocks = ref [] in

    let hub_slots = Array.init num_hubs (fun h ->
      let low = (h * total_disp) / num_hubs in
      let high = ((h + 1) * total_disp) / num_hubs - 1 in
      (low, high)
    ) in
    let find_hub_of_slot s =
      let rec loop h =
        if h >= num_hubs - 1 then num_hubs - 1
        else
          let (_, high_h) = hub_slots.(h) in
          if s <= high_h then h
          else loop (h + 1)
      in
      loop 0
    in

    let state_pool = Hashtbl.create n in
    for slot_idx = 0 to total_disp - 1 do
      let bid = targets_array.(slot_idx) in
      let h_idx = find_hub_of_slot slot_idx in
      let hub_id = disp_base_id + h_idx in
      let coded = Int64.add secret_salt (Int64.mul (Int64.of_int slot_idx) stride) in
      let state = poly_unhash64_dyn hparams coded in
      let cur = match Hashtbl.find_opt state_pool bid with Some l -> l | None -> [] in
      Hashtbl.replace state_pool bid ((state, hub_id) :: cur)
    done;

    let get_target_info bid =
      match Hashtbl.find_opt state_pool bid with
      | Some (_ :: _) ->
          let pool = Hashtbl.find state_pool bid in
          List.nth pool (Random.State.int rng (List.length pool))
      | _ ->
          failwith (Printf.sprintf "cff: target basic block id %d not found in state_pool" bid)
    in
    let pop_digest_fold dst_reg =
      match options.pop_digest with
      | Some (dreg, _) ->
          [ Ir.Alu { op = Ir.Xor; dst = dst_reg; src1 = Ir.Reg dst_reg; src2 = Ir.Reg dreg; set_flags = false } ]
      | None -> []
    in

    let emit_set_state_tainted dst_reg target_state =
      (if is_tainted then
         (emit_poly_hash64 ~hparams ~dst:Register.vtmp2 ~src:pinned_reg ~scratch:Register.vtmp3 ())
         @ [
           Ir.Mov { dst = Ir.Reg dst_reg; src = Ir.Imm target_state };
           Ir.Alu { op = Ir.Xor; dst = dst_reg; src1 = Ir.Reg dst_reg; src2 = Ir.Reg Register.vtmp2; set_flags = false };
         ]
       else
         [
           Ir.Mov { dst = Ir.Reg dst_reg; src = Ir.Imm target_state };
         ])
      @ pop_digest_fold dst_reg
    in

    (* Entry Block: pins input to pinned_reg, initializes POP digest if enabled, sets state and jumps to initial_hub *)
    let initial_state, initial_hub = get_target_info func.cfg.entry_id in
    let entry_instrs =
      (if is_tainted then
         [ Ir.Mov { dst = Ir.Reg pinned_reg; src = Ir.Reg (Option.get input_reg_opt) } ]
       else
         [])
      @ (match options.pop_digest with
         | Some (dreg, seed) -> [ Ir.Mov { dst = Ir.Reg dreg; src = Ir.Imm seed } ]
         | None -> [])
      @ (emit_set_state_tainted Register.vkey initial_state) @ [
        Ir.Jmp (Ir.BlockId initial_hub);
      ]
    in
    let entry_block = Ir.make_block ~id:entry_block_id ~label:(func.name ^ "_cff_entry") ~instrs:entry_instrs in

    (* Trap Blocks are now dynamically instantiated per-site via make_trap_block *)

    (* Binary Decision Tree Construction *)
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
        let jitter =
          match Random.State.int rng 6 with
          | 0 -> []
          | 1 -> [
              Ir.Alu { op = Ir.Xor; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Reg Register.vtmp0; set_flags = false };
            ]
          | 2 -> [
              Ir.Alu { op = Ir.Add; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Imm 0x1337L; set_flags = false };
            ]
          | 3 -> [
              Ir.Unary { op = Ir.Not; dst = Register.vx26; src = Ir.Reg Register.vx26; set_flags = false };
            ]
          | 4 -> [
              Ir.Alu { op = Ir.Rol; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Imm 7L; set_flags = false };
            ]
          | _ -> [
              Ir.Alu { op = Ir.Or; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Imm 0x5877L; set_flags = false };
            ]
        in
        let cmp_instr, cond, target_true, target_false =
          match Random.State.int rng 4 with
          | 0 ->
              (Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm (Int64.of_int mid) },
               Flags.LE, left_target, right_target)
          | 1 ->
              (Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm (Int64.of_int mid) },
               Flags.G, right_target, left_target)
          | 2 ->
              (Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm (Int64.of_int (mid + 1)) },
               Flags.L, left_target, right_target)
          | _ ->
              (Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm (Int64.of_int (mid + 1)) },
               Flags.GE, right_target, left_target)
        in
        let instrs = jitter @ [
          cmp_instr;
          Ir.Jcc { cond; target_true; target_false };
        ] in
        let blk = Ir.make_block ~id:node_id ~label:(Printf.sprintf "%s_cff_tree_%d" func.name node_id) ~instrs in
        tree_blocks := blk :: !tree_blocks;
        Ir.BlockId node_id
    in

    let entry_jitter =
      match Random.State.int rng 3 with
      | 0 -> []
      | 1 -> [
          Ir.Alu { op = Ir.Xor; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Reg Register.vkey; set_flags = false };
        ]
      | _ -> [
          Ir.Alu { op = Ir.Add; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Reg Register.vkey; set_flags = false };
          Ir.Alu { op = Ir.Rol; dst = Register.vx26; src1 = Ir.Reg Register.vx26; src2 = Ir.Imm 13L; set_flags = false };
        ]
    in

    (* Dispatcher Hub Blocks: each hub handles its subrange of slots with dedicated entry block and tree *)
    let hub_blocks = ref [] in
    for h = 0 to num_hubs - 1 do
      let (low_h, high_h) = hub_slots.(h) in
      let hub_id = disp_base_id + h in
      let tree_root_target = build_tree low_h high_h in
      let trap_target = Ir.BlockId (make_trap_block ~reason:"CFF Range Check Violation") in
      let bound_cond, bound_t, bound_f =
        if Random.State.bool rng then
          (Flags.AE, trap_target, tree_root_target)
        else
          (Flags.B, tree_root_target, trap_target)
      in
      let range_len = high_h - low_h + 1 in
      let range_check =
        if low_h = 0 then
          [
            Ir.Cmp { src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm (Int64.of_int range_len) };
            Ir.Jcc { cond = bound_cond; target_true = bound_t; target_false = bound_f };
          ]
        else
          [
            Ir.Alu { op = Ir.Sub; dst = Register.vtmp1; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Imm (Int64.of_int low_h); set_flags = false };
            Ir.Cmp { src1 = Ir.Reg Register.vtmp1; src2 = Ir.Imm (Int64.of_int range_len) };
            Ir.Jcc { cond = bound_cond; target_true = bound_t; target_false = bound_f };
          ]
      in
      let disp_entry_instrs =
        entry_jitter
        @ (if is_tainted then
             (emit_poly_hash64 ~hparams ~dst:Register.vtmp2 ~src:pinned_reg ~scratch:Register.vtmp3 ())
             @ [
               Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.vkey };
               Ir.Alu { op = Ir.Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp2; set_flags = false };
             ]
           else
             [
               Ir.Mov { dst = Ir.Reg Register.vtmp0; src = Ir.Reg Register.vkey };
             ])
        @ (match options.pop_digest with
           | Some (dreg, _) ->
               [ Ir.Alu { op = Ir.Xor; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg dreg; set_flags = false } ]
           | None -> [])
        @ (emit_poly_hash64 ~rng:(Some rng) ~hparams ~dst:Register.vtmp0 ~src:Register.vtmp0 ~scratch:Register.vtmp1 ())
        @ [
          Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm secret_salt };
          Ir.Alu { op = Ir.Sub; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
          Ir.Mov { dst = Ir.Reg Register.vtmp1; src = Ir.Imm stride_inv };
          Ir.Alu { op = Ir.Mul; dst = Register.vtmp0; src1 = Ir.Reg Register.vtmp0; src2 = Ir.Reg Register.vtmp1; set_flags = false };
        ]
        @ range_check
      in
      let hub_blk = Ir.make_block ~id:hub_id ~label:(Printf.sprintf "%s_disp_hub_%d" func.name h) ~instrs:disp_entry_instrs in
      hub_blocks := hub_blk :: !hub_blocks
    done;

    (* Layout fallthrough map across sorted_orig *)
    let fallthrough_map = Hashtbl.create (List.length sorted_orig) in
    let rec build_fallthrough = function
      | (b1 : Ir.basic_block) :: (b2 : Ir.basic_block) :: rest ->
          Hashtbl.replace fallthrough_map b1.id b2.id;
          build_fallthrough (b2 :: rest)
      | _ -> ()
    in
    build_fallthrough sorted_orig;

    (* Transform each original block: redirect control flow back to the destination hub *)
    let transformed_blocks =
      List.concat_map
        (fun (b : Ir.basic_block) ->
          let rev_instrs = List.rev b.instrs in
          let new_instrs =
            match rev_instrs with
            | [] -> (
                match Hashtbl.find_opt fallthrough_map b.id with
                | Some next_id ->
                    let next_state, target_hub = get_target_info next_id in
                    (emit_set_state_tainted Register.vkey next_state) @ [
                      Ir.Jmp (Ir.BlockId target_hub);
                    ]
                | None -> []
              )
            | last :: body_rev -> (
                let body = List.rev body_rev in
                match last with
                | Ir.Jmp (Ir.BlockId target_id) ->
                    let next_state, target_hub = get_target_info target_id in
                    body @ (emit_set_state_tainted Register.vkey next_state) @ [
                      Ir.Jmp (Ir.BlockId target_hub);
                    ]
                | Ir.Jcc { cond; target_true = Ir.BlockId t_id; target_false = Ir.BlockId f_id } ->
                    let state_true, hub_true = get_target_info t_id in
                    let state_false, hub_false = get_target_info f_id in
                    if hub_true = hub_false then
                      let setup_states =
                        (if is_tainted then
                           (emit_poly_hash64 ~hparams ~dst:Register.vtmp2 ~src:pinned_reg ~scratch:Register.vtmp0 ())
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
                           ])
                        @ (pop_digest_fold Register.vtmp0)
                        @ (pop_digest_fold Register.vtmp1)
                      in
                      let emit_direct_cmp src1 src2 prev_body_rev =
                        let prev_body = List.rev prev_body_rev in
                        prev_body @ setup_states @ [
                          Ir.Cmp { src1; src2 };
                          Ir.Cmov { cond; dst = Register.vtmp1; src = Ir.Reg Register.vtmp0 };
                          Ir.Mov { dst = Ir.Reg Register.vkey; src = Ir.Reg Register.vtmp1 };
                          Ir.Jmp (Ir.BlockId hub_true);
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
                            Ir.Jmp (Ir.BlockId hub_true);
                          ])
                    else
                      let thunk_t_id = !next_fresh_id in
                      incr next_fresh_id;
                      let thunk_f_id = !next_fresh_id in
                      incr next_fresh_id;
                      let thunk_t = Ir.make_block ~id:thunk_t_id ~label:(Printf.sprintf "%s_cff_branch_t_%d" func.name thunk_t_id)
                        ~instrs:((emit_set_state_tainted Register.vkey state_true) @ [ Ir.Jmp (Ir.BlockId hub_true) ])
                      in
                      let thunk_f = Ir.make_block ~id:thunk_f_id ~label:(Printf.sprintf "%s_cff_branch_f_%d" func.name thunk_f_id)
                        ~instrs:((emit_set_state_tainted Register.vkey state_false) @ [ Ir.Jmp (Ir.BlockId hub_false) ])
                      in
                      thunk_blocks := thunk_t :: thunk_f :: !thunk_blocks;
                      body @ [ Ir.Jcc { cond; target_true = Ir.BlockId thunk_t_id; target_false = Ir.BlockId thunk_f_id } ]
                | Ir.Ret | Ir.Vm_exit | Ir.Trap _ ->
                    b.instrs
                | other -> (
                    match Hashtbl.find_opt fallthrough_map b.id with
                    | Some next_id ->
                        let next_state, target_hub = get_target_info next_id in
                        body @ [ other ] @ (emit_set_state_tainted Register.vkey next_state) @ [
                          Ir.Jmp (Ir.BlockId target_hub);
                        ]
                    | None ->
                        body @ [ other ]
                  ))
          in
          if options.inject_opaque_predicates && b.id <> func.cfg.entry_id then
            let body_id = !next_fresh_id in
            incr next_fresh_id;
            let trap_id = make_trap_block ~reason:"CFF State Violation" in
            let pred_block =
              inject_opaque_predicate ~next_block_id:body_id ~rng ~trap_block_id:trap_id
                { b with instrs = [] }
            in
            let body_block = Ir.make_block ~id:body_id ~label:(b.label ^ "_body") ~instrs:new_instrs in
            [ pred_block; body_block ]
          else
            [ { b with instrs = new_instrs } ])
        sorted_orig
    in

    let all_blocks = (entry_block :: !trap_blocks @ !hub_blocks @ !tree_blocks @ !thunk_blocks) @ transformed_blocks in
    let new_func = Ir.make_func ~name:func.name ~entry_id:entry_block_id ~blocks:all_blocks in
    Ok new_func

module Pop_coupler = Pop_coupler
module Red_herring = Red_herring
