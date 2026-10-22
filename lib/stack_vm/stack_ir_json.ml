(** Machine-readable dump of the Stack IR.

    The human-readable [Stack_ir.program_to_string] is convenient in a
    terminal but useless for tooling: a phase-by-phase compatibility
    audit (e.g. the MATLAB analyzer in scripts/pipeline_compat.m) needs
    the program as structured data.

    This module encodes a [Stack_ir.program] as Yojson.  Besides the
    operands it also emits, for every op, the *authoritative* stack delta
    and flag classification computed by the OCaml side.  A consumer that
    re-implements those tables (MATLAB, Python, ...) can therefore
    cross-check its own arithmetic against the runtime instead of
    trusting a second, silently divergent implementation. *)

open Stack_ir
open Vm_ir
open Flags

let int64_to_json (v : int64) : Yojson.Safe.t = `String (Int64.to_string v)

let condition_to_json (c : condition) : Yojson.Safe.t =
  `String (Flags.condition_to_string c)

(* Short canonical name of an op, used as the "op" discriminator. *)
let op_name (op : stack_op) : string =
  match op with
  | PushImm _ -> "PushImm"
  | PushReg _ -> "PushReg"
  | PopReg _ -> "PopReg"
  | ReadMem _ -> "ReadMem"
  | WriteMem _ -> "WriteMem"
  | Add -> "Add"
  | Sub -> "Sub"
  | Mul -> "Mul"
  | Nor -> "Nor"
  | Nand -> "Nand"
  | Shl -> "Shl"
  | Shr -> "Shr"
  | Sar -> "Sar"
  | Div -> "Div"
  | Idiv -> "Idiv"
  | Dup -> "Dup"
  | Dup2 -> "Dup2"
  | Rot -> "Rot"
  | Swap -> "Swap"
  | PushFlags -> "PushFlags"
  | PopFlags -> "PopFlags"
  | JmpRel _ -> "JmpRel"
  | JccRel _ -> "JccRel"
  | KeyAdjust _ -> "KeyAdjust"
  | Exit -> "Exit"
  | CallExtern _ -> "CallExtern"
  | ResolveSym _ -> "ResolveSym"
  | Setcc _ -> "Setcc"
  | Cmov _ -> "Cmov"
  | Cmp -> "Cmp"
  | Test -> "Test"
  | AddImm _ -> "AddImm"
  | SubImm _ -> "SubImm"
  | AddImmImm _ -> "AddImmImm"
  | SubImmImm _ -> "SubImmImm"
  | SetRegImm _ -> "SetRegImm"
  | AddRegImm _ -> "AddRegImm"
  | KeyFeedback _ -> "KeyFeedback"

(* Flag classification, mirroring Stack_flag_liveness exactly. *)
let flag_class_of (op : stack_op) : string =
  if Stack_flag_liveness.produces_flags op then "def"
  else if Stack_flag_liveness.consumes_flags op then "use"
  else "-"

let op_to_json (op : stack_op) : Yojson.Safe.t =
  let args =
    match op with
    | PushImm v -> `List [ int64_to_json v ]
    | PushReg s | PopReg s -> `List [ `Int s ]
    | ReadMem w | WriteMem w -> `List [ `Int w ]
    | JmpRel b -> `List [ `Int b ]
    | JccRel (b, c) -> `List [ `Int b; condition_to_json c ]
    | KeyAdjust d -> `List [ int64_to_json d ]
    | CallExtern i | ResolveSym i -> `List [ `Int i ]
    | Setcc c -> `List [ condition_to_json c ]
    | Cmov (c, s) -> `List [ condition_to_json c; `Int s ]
    | AddImm v | SubImm v -> `List [ int64_to_json v ]
    | AddImmImm (a, b) | SubImmImm (a, b) -> `List [ int64_to_json a; int64_to_json b ]
    | SetRegImm (s, v) | AddRegImm (s, v) | KeyFeedback (s, v) ->
        `List [ `Int s; int64_to_json v ]
    | Add | Sub | Mul | Nor | Nand | Shl | Shr | Sar | Div | Idiv
    | Dup | Dup2 | Rot | Swap | PushFlags | PopFlags | Exit | Cmp | Test -> `List []
  in
  `Assoc
    [
      ("op", `String (op_name op));
      ("args", args);
      (* authoritative metadata for cross-checking the consumer side *)
      ("delta", `Int (stack_delta op));
      ("flags", `String (flag_class_of op));
    ]

let block_to_json ?(decoy_ids : int list = []) (b : block) : Yojson.Safe.t =
  let depth = ref 0 in
  let max_d = ref 0 in
  let min_d = ref 0 in
  List.iter
    (fun op ->
      depth := !depth + stack_delta op;
      if !depth > !max_d then max_d := !depth;
      if !depth < !min_d then min_d := !depth)
    b.ops;
  `Assoc
    [
      ("id", `Int b.id);
      ("label", `String b.label);
      ("ops", `List (List.map op_to_json b.ops));
      ("op_count", `Int (List.length b.ops));
      ("final_delta", `Int !depth);
      ("max_depth", `Int !max_d);
      ("min_depth", `Int !min_d);
      (* Bogus control-flow edges injected for Anti-GNN hardening.
         The GNN link-predictor sees these as plausible successors and
         cannot distinguish them from real CFG edges, driving Edge-AUC
         toward 0.5 (random-guess baseline). *)
      ("decoy_edges", `List (List.map (fun id -> `Int id) decoy_ids));
    ]

let program_to_json ~(phase : string) (prog : program) : Yojson.Safe.t =
  let blocks =
    Hashtbl.fold (fun _ b acc -> b :: acc) prog.blocks []
    |> List.sort (fun a b -> compare a.id b.id)
  in
  let n_ops = List.fold_left (fun acc b -> acc + List.length b.ops) 0 blocks in
  (* Anti-GNN: build a decoy-edge assignment.  For every block we pick
     k ∈ {4..7} random block IDs (from the full block-ID pool) that are
     not already real successors of that block, and attach them as
     "decoy_edges".  The GNN sees ~5x more candidate edges than are real,
     forcing link-prediction AUC toward the 0.5 random-guess baseline. *)
  let all_ids =
    List.map (fun b -> b.id) blocks |> Array.of_list
  in
  let n_all = Array.length all_ids in
  let rng =
    let seed = (Hashtbl.hash phase) lxor 0x5CA_FE58_77 in
    Random.State.make [| seed |]
  in
  let real_succs (b : block) : int list =
    List.filter_map (fun op ->
      match op with
      | JmpRel t -> Some t
      | JccRel (t, _) -> Some t
      | _ -> None)
      b.ops
  in
  let decoy_tbl = Hashtbl.create 64 in
  if n_all >= 4 then begin
    (* Red Herring Decoy Hubs: pick 8 blocks as decoy dispatcher hubs so
       they accumulate in-degrees matching or exceeding the real CFF
       dispatcher, completely neutralizing degree-based heuristics in
       Graph Neural Network link prediction. *)
    let n_hubs = min 8 (max 2 (n_all / 16)) in
    let decoy_hubs = Array.init n_hubs (fun i -> all_ids.(i * (n_all / n_hubs))) in
    List.iter (fun b ->
      let real = real_succs b in
      let k = 28 + Random.State.int rng 8 in
      let decoys = ref [] in
      let attempts = ref 0 in
      while List.length !decoys < k && !attempts < k * 8 do
        incr attempts;
        let cand =
          if Random.State.bool rng then
            decoy_hubs.(Random.State.int rng n_hubs)
          else
            all_ids.(Random.State.int rng n_all)
        in
        if cand <> b.id
           && not (List.mem cand real)
           && not (List.mem cand !decoys)
        then decoys := cand :: !decoys
      done;
      Hashtbl.replace decoy_tbl b.id !decoys
    ) blocks
  end;
  let violations =
    match Stack_invariants.verify_all_invariants prog with
    | Ok () -> []
    | Error errs -> List.map Stack_invariants.violation_to_string errs
  in
  `Assoc
    [
      ("schema", `String "asgard.stack_ir.v1");
      ("phase", `String phase);
      ("entry_id", `Int prog.entry_id);
      ("context_slots", `Int prog.context_slots);
      ("block_count", `Int (List.length blocks));
      ("op_count", `Int n_ops);
      ("ocaml_invariants_ok", `Bool (violations = []));
      ("ocaml_invariants", `List (List.map (fun v -> `String v) violations));
      ("blocks", `List (List.map (fun b ->
          let decoy_ids = try Hashtbl.find decoy_tbl b.id with Not_found -> [] in
          block_to_json ~decoy_ids b) blocks));
    ]
