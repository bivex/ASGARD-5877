(** Pass C: Bit-Vector Semantic Normalization & Automated SMT Verifier
    ─────────────────────────────────────────────────────────────────
    Formally proves semantics preservation between original and transformed
    Stack-IR sequences via SMT-LIB2 bit-vector (QF_BV) verification.
*)

open Stack_ir

type verification_result =
  | Equivalent
  | Divergent of { counterexample : string }
  | Solver_timeout
  | Solver_error of string
  | Stack_depth_mismatch of { orig_depth : int; trans_depth : int }

let string_of_result = function
  | Equivalent -> "Equivalent (Q.E.D. via SMT QF_BV unsat)"
  | Divergent { counterexample } -> Printf.sprintf "Divergent! Counterexample:\n%s" counterexample
  | Solver_timeout -> "Solver_timeout"
  | Solver_error err -> Printf.sprintf "Solver_error: %s" err
  | Stack_depth_mismatch { orig_depth; trans_depth } ->
      Printf.sprintf "Stack_depth_mismatch (orig=%d, trans=%d)" orig_depth trans_depth

type bv_expr =
  | BVConst of int64
  | BVVar of string
  | BVAdd of bv_expr * bv_expr
  | BVSub of bv_expr * bv_expr
  | BVMul of bv_expr * bv_expr
  | BVAnd of bv_expr * bv_expr
  | BVOr of bv_expr * bv_expr
  | BVXor of bv_expr * bv_expr
  | BVNot of bv_expr
  | BVShl of bv_expr * bv_expr
  | BVLshr of bv_expr * bv_expr
  | BVAshr of bv_expr * bv_expr
[@@warning "-37"]

let rec smt_of_bv = function
  | BVConst c -> Printf.sprintf "#x%016LX" c
  | BVVar v -> v
  | BVAdd (a, b) -> Printf.sprintf "(bvadd %s %s)" (smt_of_bv a) (smt_of_bv b)
  | BVSub (a, b) -> Printf.sprintf "(bvsub %s %s)" (smt_of_bv a) (smt_of_bv b)
  | BVMul (a, b) -> Printf.sprintf "(bvmul %s %s)" (smt_of_bv a) (smt_of_bv b)
  | BVAnd (a, b) -> Printf.sprintf "(bvand %s %s)" (smt_of_bv a) (smt_of_bv b)
  | BVOr (a, b) -> Printf.sprintf "(bvor %s %s)" (smt_of_bv a) (smt_of_bv b)
  | BVXor (a, b) -> Printf.sprintf "(bvxor %s %s)" (smt_of_bv a) (smt_of_bv b)
  | BVNot a -> Printf.sprintf "(bvnot %s)" (smt_of_bv a)
  | BVShl (a, b) ->
      Printf.sprintf "(bvshl %s (bvand %s #x000000000000003F))" (smt_of_bv a) (smt_of_bv b)
  | BVLshr (a, b) ->
      Printf.sprintf "(bvlshr %s (bvand %s #x000000000000003F))" (smt_of_bv a) (smt_of_bv b)
  | BVAshr (a, b) ->
      Printf.sprintf "(bvashr %s (bvand %s #x000000000000003F))" (smt_of_bv a) (smt_of_bv b)

type sym_state = {
  mutable stack : bv_expr list;
  ctx : (int, bv_expr) Hashtbl.t;
  vars : (string, unit) Hashtbl.t;
}

let create_sym_state () = {
  stack = [];
  ctx = Hashtbl.create 16;
  vars = Hashtbl.create 16;
}

let get_reg_expr state r =
  match Hashtbl.find_opt state.ctx r with
  | Some e -> e
  | None ->
      let v = Printf.sprintf "reg_%d" r in
      Hashtbl.replace state.vars v ();
      let e = BVVar v in
      Hashtbl.replace state.ctx r e;
      e

let exec_sym_op state = function
  | PushImm c ->
      state.stack <- BVConst c :: state.stack
  | PushReg r ->
      let e = get_reg_expr state r in
      state.stack <- e :: state.stack
  | PopReg r ->
      begin match state.stack with
      | v :: rest ->
          state.stack <- rest;
          Hashtbl.replace state.ctx r v
      | [] -> ()
      end
  | Add ->
      begin match state.stack with
      | b :: a :: rest -> state.stack <- BVAdd (a, b) :: rest
      | _ -> ()
      end
  | Sub ->
      begin match state.stack with
      | b :: a :: rest -> state.stack <- BVSub (a, b) :: rest
      | _ -> ()
      end
  | Mul ->
      begin match state.stack with
      | b :: a :: rest -> state.stack <- BVMul (a, b) :: rest
      | _ -> ()
      end
  | Nor ->
      begin match state.stack with
      | b :: a :: rest -> state.stack <- BVNot (BVOr (a, b)) :: rest
      | _ -> ()
      end
  | Nand ->
      begin match state.stack with
      | b :: a :: rest -> state.stack <- BVNot (BVAnd (a, b)) :: rest
      | _ -> ()
      end
  | Shl ->
      begin match state.stack with
      | b :: a :: rest -> state.stack <- BVShl (a, b) :: rest
      | _ -> ()
      end
  | Shr ->
      begin match state.stack with
      | b :: a :: rest -> state.stack <- BVLshr (a, b) :: rest
      | _ -> ()
      end
  | Sar ->
      begin match state.stack with
      | b :: a :: rest -> state.stack <- BVAshr (a, b) :: rest
      | _ -> ()
      end
  | Dup ->
      begin match state.stack with
      | v :: rest -> state.stack <- v :: v :: rest
      | [] -> ()
      end
  | Dup2 ->
      begin match state.stack with
      | a :: b :: rest -> state.stack <- a :: b :: a :: b :: rest
      | _ -> ()
      end
  | Swap ->
      begin match state.stack with
      | a :: b :: rest -> state.stack <- b :: a :: rest
      | _ -> ()
      end
  | Rot ->
      begin match state.stack with
      | a :: b :: c :: rest -> state.stack <- c :: a :: b :: rest
      | _ -> ()
      end
  | _ ->
      (* Memory / Jump / Exit handled separately *)
      ()

let exec_sym_ops ops =
  let st = create_sym_state () in
  List.iter (exec_sym_op st) ops;
  st

let check_smt_script ?(timeout_sec = 10) script =
  let z3_path =
    if Sys.file_exists "/opt/homebrew/bin/z3" then "/opt/homebrew/bin/z3"
    else if Sys.file_exists "/usr/local/bin/z3" then "/usr/local/bin/z3"
    else if Sys.file_exists "/usr/bin/z3" then "/usr/bin/z3"
    else "z3"
  in
  let cmd = Printf.sprintf "%s -smt2 -t:%d -in" z3_path (timeout_sec * 1000) in
  try
    let ic, oc = Unix.open_process cmd in
    output_string oc script;
    flush oc;
    close_out oc;
    let rec read_all acc =
      try
        let line = input_line ic in
        read_all (line :: acc)
      with End_of_file ->
        List.rev acc
    in
    let lines = read_all [] in
    ignore (Unix.close_process (ic, oc));
    let output = String.concat "\n" lines in
    let trimmed = String.trim output in
    if String.starts_with ~prefix:"unsat" trimmed then
      Equivalent
    else if String.starts_with ~prefix:"sat" trimmed then
      Divergent { counterexample = trimmed }
    else if String.starts_with ~prefix:"timeout" trimmed then
      Solver_timeout
    else
      Solver_error trimmed
  with exn ->
    Solver_error (Printexc.to_string exn)

let verify_ops_equivalence ?(timeout_sec = 10) ~orig_ops ~trans_ops () =
  let st_orig = exec_sym_ops orig_ops in
  let st_trans = exec_sym_ops trans_ops in
  let orig_depth = List.length st_orig.stack in
  let trans_depth = List.length st_trans.stack in
  if orig_depth <> trans_depth then
    Stack_depth_mismatch { orig_depth; trans_depth }
  else
    let all_vars = Hashtbl.create 16 in
    Hashtbl.iter (fun v () -> Hashtbl.replace all_vars v ()) st_orig.vars;
    Hashtbl.iter (fun v () -> Hashtbl.replace all_vars v ()) st_trans.vars;

    let buf = Buffer.create 1024 in
    Buffer.add_string buf "(set-logic QF_BV)\n";
    Hashtbl.iter (fun v () ->
      Buffer.add_string buf (Printf.sprintf "(declare-const %s (_ BitVec 64))\n" v)
    ) all_vars;

    let diff_terms = ref [] in
    List.iter2 (fun o_e t_e ->
      diff_terms := Printf.sprintf "(distinct %s %s)" (smt_of_bv o_e) (smt_of_bv t_e) :: !diff_terms
    ) st_orig.stack st_trans.stack;

    let touched_slots = Hashtbl.create 16 in
    Hashtbl.iter (fun r _ -> Hashtbl.replace touched_slots r ()) st_orig.ctx;
    Hashtbl.iter (fun r _ -> Hashtbl.replace touched_slots r ()) st_trans.ctx;
    Hashtbl.iter (fun r () ->
      let o_e = get_reg_expr st_orig r in
      let t_e = get_reg_expr st_trans r in
      diff_terms := Printf.sprintf "(distinct %s %s)" (smt_of_bv o_e) (smt_of_bv t_e) :: !diff_terms
    ) touched_slots;

    if !diff_terms = [] then
      Equivalent
    else begin
      let or_body =
        if List.length !diff_terms = 1 then List.hd !diff_terms
        else "(or " ^ String.concat " " !diff_terms ^ ")"
      in
      Buffer.add_string buf (Printf.sprintf "(assert %s)\n" or_body);
      Buffer.add_string buf "(check-sat)\n(get-model)\n";
      check_smt_script ~timeout_sec (Buffer.contents buf)
    end

let verify_block_equivalence ?(timeout_sec = 10) ~orig_block ~trans_block () =
  verify_ops_equivalence ~timeout_sec ~orig_ops:orig_block.ops ~trans_ops:trans_block.ops ()

let verify_program_equivalence ?(timeout_sec = 10) ~orig_prog ~trans_prog () =
  let results = ref [] in
  Hashtbl.iter (fun id b_orig ->
    match Hashtbl.find_opt trans_prog.blocks id with
    | Some b_trans ->
        let res = verify_block_equivalence ~timeout_sec ~orig_block:b_orig ~trans_block:b_trans () in
        results := (id, res) :: !results
    | None ->
        results := (id, Solver_error "Target block missing in transformed program") :: !results
  ) orig_prog.blocks;
  List.rev !results
