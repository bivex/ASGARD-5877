(** Cross-seed inter-build entropy metrics.
    Measures structural divergence between two compiled builds of the same
    function with different seeds. *)

open Vm_ir

type cross_seed_report = {
  ngram3_jaccard        : float;   (** Jaccard similarity of IR 3-gram sets (0=disjoint, 1=identical) *)
  cfg_edge_count_delta  : int;     (** |edges(B_s1)| - |edges(B_s2)| *)
  block_count_delta     : int;     (** |blocks(B_s1)| - |blocks(B_s2)| *)
  instr_count_delta     : int;     (** total instruction count delta *)
  passes_disjointness_gate : bool; (** true if ngram3_jaccard < 0.10 *)
}

let instr_fingerprint (i : Ir.instr) : string =
  let norm_op op = Ir.alu_op_to_string op in
  match i with
  | Ir.Alu { op; _ } -> "ALU_" ^ norm_op op
  | Ir.Mov { dst = Ir.Reg _; src = Ir.Imm _ } -> "MOV_R_IMM"
  | Ir.Mov { dst = Ir.Reg _; src = Ir.Reg _ } -> "MOV_R_R"
  | Ir.Mov _ -> "MOV"
  | Ir.Cmp _ -> "CMP"
  | Ir.Jmp _ -> "JMP"
  | Ir.Jcc { cond; _ } -> "JCC_" ^ Flags.condition_to_string cond
  | Ir.Cmov { cond; _ } -> "CMOV_" ^ Flags.condition_to_string cond
  | Ir.Unary { op; _ } -> "UNARY_" ^ Ir.unary_op_to_string op
  | Ir.Nop -> "NOP"
  | Ir.Push _ -> "PUSH"
  | Ir.Pop _ -> "POP"
  | Ir.Ret -> "RET"
  | Ir.Vm_exit -> "VM_EXIT"
  | Ir.Trap _ -> "TRAP"
  | Ir.Get_flags _ -> "GET_FLAGS"
  | Ir.Set_flags _ -> "SET_FLAGS"
  | _ -> "OTHER"

let collect_ngrams3 (f : Ir.func) : (string, unit) Hashtbl.t =
  let tbl = Hashtbl.create 64 in
  let block_ids =
    Hashtbl.fold (fun id _ acc -> id :: acc) f.cfg.blocks []
    |> List.sort Int.compare
  in
  List.iter (fun id ->
    match Hashtbl.find_opt f.cfg.blocks id with
    | None -> ()
    | Some b ->
        let fps = List.map instr_fingerprint b.instrs in
        let arr = Array.of_list fps in
        let n = Array.length arr in
        for i = 0 to n - 3 do
          let gram = arr.(i) ^ "|" ^ arr.(i+1) ^ "|" ^ arr.(i+2) in
          Hashtbl.replace tbl gram ()
        done
  ) block_ids;
  tbl

let jaccard_similarity tbl1 tbl2 =
  let intersect = Hashtbl.fold (fun k () acc ->
    if Hashtbl.mem tbl2 k then acc + 1 else acc
  ) tbl1 0 in
  let union = Hashtbl.fold (fun k () acc ->
    if not (Hashtbl.mem tbl2 k) then acc + 1 else acc
  ) tbl2 (Hashtbl.length tbl1) in
  if union = 0 then 1.0
  else float_of_int intersect /. float_of_int union

let count_edges (f : Ir.func) =
  Hashtbl.fold (fun _ (b : Ir.basic_block) acc ->
    acc + List.length (Ir.successors b)
  ) f.cfg.blocks 0

let count_instrs (f : Ir.func) =
  Hashtbl.fold (fun _ (b : Ir.basic_block) acc ->
    acc + List.length b.instrs
  ) f.cfg.blocks 0

let compare_builds ~f1 ~f2 : cross_seed_report =
  let ng1 = collect_ngrams3 f1 in
  let ng2 = collect_ngrams3 f2 in
  let jac = jaccard_similarity ng1 ng2 in
  let e1 = count_edges f1 in
  let e2 = count_edges f2 in
  let b1 = Hashtbl.length f1.cfg.blocks in
  let b2 = Hashtbl.length f2.cfg.blocks in
  let i1 = count_instrs f1 in
  let i2 = count_instrs f2 in
  {
    ngram3_jaccard = jac;
    cfg_edge_count_delta = e1 - e2;
    block_count_delta = b1 - b2;
    instr_count_delta = i1 - i2;
    passes_disjointness_gate = jac < 0.10;
  }

let report_to_string r =
  Printf.sprintf
    "CrossSeedMetrics(jaccard=%.3f, edge_delta=%d, block_delta=%d, instr_delta=%d, gate=%b)"
    r.ngram3_jaccard r.cfg_edge_count_delta r.block_count_delta r.instr_count_delta
    r.passes_disjointness_gate
