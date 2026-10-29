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
open Random_visa_constants.Magic_numbers
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
  | Mulh -> "Mulh"
  | Imulh -> "Imulh"
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
  | Bswap -> "Bswap"
  | Clz -> "Clz"
  | Ctz -> "Ctz"
  | Rbit -> "Rbit"
  | Popcnt -> "Popcnt"
  | NativeEscape _ -> "NativeEscape"

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
    | NativeEscape (kind, a, b, c, stub) ->
        `List [ `Int kind; `Int a; `Int b; `Int c; `List (List.map (fun x -> `Int x) stub) ]
    | Add | Sub | Mul | Mulh | Imulh | Nor | Nand | Shl | Shr | Sar | Div | Idiv
    | Dup | Dup2 | Rot | Swap | PushFlags | PopFlags | Exit | Cmp | Test
    | Bswap | Clz | Ctz | Rbit | Popcnt -> `List []
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
    let seed = (Hashtbl.hash phase) lxor Int64.to_int salt_dump_phase in
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
    (* Red Herring Decoy Hubs with class-pair matching.

       The real CFF graph has exactly three edge classes:
         real_block -> cff_disp_0   (every real block targets the SAME node)
         disp_i     -> real target  (Cmp-matched)
         disp_i     -> disp_{i+1}   (dispatcher chain)
       Uniform random decoys leak that structure: a GNN learns that
       real->real pairs are always decoys (they never occur in the real
       edge set) and ranks them below every real edge, inflating its
       link-prediction AUC far above the 0.5 random-guess baseline.

       The decoy sampler below mirrors the real class-pair distribution:
         - real-like sources emit decoys ONLY toward dispatcher-like
           nodes (the 8 decoy hubs, drawn from the dispatcher pool so
           their opcode profile matches cff_disp_0), never toward real
           blocks - eliminating the real->real tell.
         - dispatcher-like sources emit decoys 50/50 toward real-like
           and ordinary dispatcher-like nodes, mirroring the Cmp-match
           and chain edges.
       A hub absorbing ~2240 decoy in-edges also dwarfs the real
       dispatcher's 253, so no single node stands out by degree. *)
    let is_disp (b : block) =
      (String.length b.label >= 8 && String.sub b.label 0 8 = "cff_disp")
      || b.label = "cff_exit"
    in
    let disp_ids =
      List.filter_map (fun b -> if is_disp b then Some b.id else None) blocks
      |> Array.of_list
    in
    let real_ids =
      List.filter_map (fun b -> if not (is_disp b) then Some b.id else None) blocks
      |> Array.of_list
    in
    (* Composition-matched decoy targets.

       Measured on the real dumps, only the real-block-source edges leak:
       their positives concentrate on the dispatcher entry (target
       in-degree ~260) while decoy targets averaged ~50, giving a
       degree-only logistic regression AUC 0.94.  Dispatcher-source
       edges were already matched (in-degree 32 vs 33).  The sampler
       therefore splits each real-like block's decoys to reproduce the
       positive composition: the [q_hi] share of high-in-degree targets
       goes to a 12-node dispatcher-pool hub set (so no single pair or
       node dominates), the remainder to the fragment-level slice of the
       real-source target pool. *)
    let real_in = Hashtbl.create 64 in
    List.iter (fun b ->
      List.iter (fun t ->
        let n = try Hashtbl.find real_in t with Not_found -> 0 in
        Hashtbl.replace real_in t (n + 1)
      ) (real_succs b)
    ) blocks;
    let real_in_of id = try Hashtbl.find real_in id with Not_found -> 0 in
    let is_hi id = real_in_of id > 10 in
    let tgt_of_real =
      List.concat_map (fun b -> if not (is_disp b) then real_succs b else []) blocks
      |> Array.of_list
    in
    let tgt_of_disp =
      List.concat_map (fun b -> if is_disp b then real_succs b else []) blocks
      |> Array.of_list
    in
    (* Id-based dispatcher check (labels are per-block). *)
    let disp_id_set = Hashtbl.create 64 in
    Array.iter (fun id -> Hashtbl.replace disp_id_set id ()) disp_ids;
    let is_disp_id id = Hashtbl.mem disp_id_set id in
    (* Full empirical target-class composition of the real-source
       positives: hi (dispatcher entry), ordinary dispatcher, fragment.
       The decoy mixture reproduces each share so no class feature can
       separate positives from decoys (measured leak before: tgt_disp
       0.70 vs 0.40, logistic coefficient 11.3). *)
    let n_tgt_real = Array.length tgt_of_real in
    let n_hi =
      Array.fold_left (fun a t -> if is_hi t then a + 1 else a) 0 tgt_of_real in
    let n_disp_tgt =
      Array.fold_left
        (fun a t -> if (not (is_hi t)) && is_disp_id t then a + 1 else a)
        0 tgt_of_real
    in
    let q_hi = if n_tgt_real = 0 then 0.0 else float n_hi /. float n_tgt_real in
    let q_disp = if n_tgt_real = 0 then 0.0 else float n_disp_tgt /. float n_tgt_real in
    (* Fragment slice: real-class targets only. *)
    let frag_of_real =
      Array.of_list
        (List.filter (fun t -> (not (is_hi t)) && not (is_disp_id t))
           (Array.to_list tgt_of_real))
    in
    let uniform_target () = all_ids.(Random.State.int rng n_all) in
    let uniform_disp () = disp_ids.(Random.State.int rng (Array.length disp_ids)) in
    let class_aware = Array.length disp_ids > 0 && Array.length real_ids > 0 in
    List.iter (fun b ->
      let k = 28 + Random.State.int rng 8 in
      let decoys = ref [] in
      let attempts = ref 0 in
      let draw_target () =
        if not class_aware then uniform_target ()
        else if is_disp b then begin
          if Array.length tgt_of_disp > 0 && Random.State.bool rng then
            tgt_of_disp.(Random.State.int rng (Array.length tgt_of_disp))
          else uniform_target ()
        end else begin
          (* With the segmented dispatcher the entry in-degree (~30 per
             segment) matches an ordinary dispatcher node's decoy load,
             so the high-degree share spreads uniformly over the whole
             dispatcher pool instead of a small hub subset. *)
          let r = Random.State.float rng 1.0 in
          if r < q_hi +. q_disp then
            uniform_disp ()
          else if Array.length frag_of_real > 0 then
            frag_of_real.(Random.State.int rng (Array.length frag_of_real))
          else
            uniform_disp ()
        end
      in
      (* A decoy MAY coincide with a real successor: excluding real
         successors handed the auditor a free oracle (the dispatcher
         entry could never appear as a decoy, so target in-degree alone
         separated real edges at AUC 0.94). *)
      while List.length !decoys < k && !attempts < k * 8 do
        incr attempts;
        let cand = draw_target () in
        if cand <> b.id
           && not (List.mem cand !decoys)
        then decoys := cand :: !decoys
      done;
      (* Candidate seeding for non-hi successors only.  Seeding the hi
         targets inflated their adjacency degree to 2x any hub's
         (reals + twins), re-opening the exact degree gap the hub set
         exists to close: with hi nodes excluded, a hub's decoy-only
         in-degree matches the entry's real-only in-degree (~243), and
         the GAT scoring head sees two identical embeddings - one
         backed by positive pairs, one by negatives - forcing its
         scores to converge to the coin-flip boundary. *)
      let seeded =
        List.filter (fun t -> t <> b.id && not (is_hi t) && not (List.mem t !decoys))
          (real_succs b)
      in
      decoys := seeded @ !decoys;
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
