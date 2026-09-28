(** Phase 2b: Spaghetti Control-Flow Splitting Pass
    ───────────────────────────────────────────────
    Splits straight-line basic blocks into chained fragments linked by JmpRel,
    increasing block count and dispersing control-flow before CFF dispatcher
    synthesis.

    Soundness invariants:
      • Cut is made ONLY at points where stack depth = 0 (block stack balance preserved).
      • Cut is made ONLY where architectural flags are dead (not live across cut),
        preventing subsequent CFF dispatcher comparisons from clobbering live flags.
      • Global block ceiling limits total block proliferation to preserve CFF performance.
*)

open Stack_ir

(* ── SplitMix64 PRNG ─────────────────────────────────────────────────── *)
let splitmix64 s =
  let s = Int64.add s 0x9E3779B97F4A7C15L in
  let z = s in
  let z = Int64.logxor z (Int64.shift_right_logical z 30) in
  let z = Int64.mul z 0xBF58476D1CE4E5B9L in
  let z = Int64.logxor z (Int64.shift_right_logical z 27) in
  let z = Int64.mul z 0x94D049BB133111EBL in
  let z = Int64.logxor z (Int64.shift_right_logical z 31) in
  (s, z)

type rng_state = { mutable state : int64 }

let make_rng seed = { state = seed }

let next_int64 rng =
  let s, z = splitmix64 rng.state in
  rng.state <- s;
  z

let next_int rng n =
  if n <= 0 then 0
  else
    let v = Int64.to_int (Int64.logand (next_int64 rng) 0x7FFF_FFFFL) in
    v mod n

let maybe rng prob = next_int rng 100 < prob

(* ── Split Candidates Analysis ────────────────────────────────────────── *)

let find_candidate_cuts min_chunk ops =
  let n = List.length ops in
  if n < 2 * min_chunk then []
  else
    let arr = Array.of_list ops in
    let live = Stack_flag_liveness.analyze_arr arr in
    let depth = Array.make (n + 1) 0 in
    for i = 0 to n - 1 do
      depth.(i + 1) <- depth.(i) + stack_delta arr.(i)
    done;
    let has_term_before = Array.make (n + 1) false in
    for i = 0 to n - 1 do
      has_term_before.(i + 1) <- has_term_before.(i) || Stack_balance_pass.is_terminator arr.(i)
    done;
    let candidates = ref [] in
    for k = min_chunk to n - min_chunk do
      if depth.(k) = 0 && not live.(k) && not has_term_before.(k) then
        candidates := k :: !candidates
    done;
    List.rev !candidates

let split_ops_at k ops =
  let rec aux i acc = function
    | [] -> (List.rev acc, [])
    | x :: xs ->
        if i = k then (List.rev acc, x :: xs)
        else aux (i + 1) (x :: acc) xs
  in
  aux 0 [] ops

(* ── Public API ───────────────────────────────────────────────────────── *)

type spaghetti_config = {
  seed       : int64;
  split_rate : int;   (** Probability (0–100) of splitting an eligible block *)
  max_blocks : int;   (** Upper bound on total blocks in program *)
  min_chunk  : int;   (** Minimum ops before and after split point (default: 2) *)
}

let default_spaghetti_config seed = {
  seed;
  split_rate = 80;
  max_blocks = 128;
  min_chunk  = 2;
}

let apply_program cfg prog =
  let rng = make_rng cfg.seed in
  let max_id = Hashtbl.fold (fun id _ acc -> max acc id) prog.blocks 0 in
  let next_id = ref (max_id + 1) in
  let current_block_count = ref (Hashtbl.length prog.blocks) in
  (* Sort blocks by ID for deterministic processing across builds with same seed *)
  let blocks_list =
    Hashtbl.fold (fun _ b acc -> b :: acc) prog.blocks []
    |> List.sort (fun a b -> compare a.id b.id)
  in
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks * 2) in
  List.iter (fun block ->
    if !current_block_count < cfg.max_blocks && maybe rng cfg.split_rate then
      let cuts = find_candidate_cuts cfg.min_chunk block.ops in
      match cuts with
      | [] ->
          Hashtbl.replace new_blocks block.id block
      | _ ->
          let k = List.nth cuts (next_int rng (List.length cuts)) in
          let new_bid = !next_id in
          incr next_id;
          incr current_block_count;
          let (first_half, second_half) = split_ops_at k block.ops in
          let b1 = { block with ops = first_half @ [ JmpRel new_bid ] } in
          let b2 = {
            id = new_bid;
            label = Printf.sprintf "%s_split_%d" block.label new_bid;
            ops = second_half;
          } in
          Hashtbl.replace new_blocks b1.id b1;
          Hashtbl.replace new_blocks b2.id b2
    else
      Hashtbl.replace new_blocks block.id block
  ) blocks_list;
  { prog with blocks = new_blocks }

let spaghetti_stats prog_before prog_after =
  let count_b prog = Hashtbl.length prog.blocks in
  let before = count_b prog_before in
  let after  = count_b prog_after in
  let splits = after - before in
  Printf.sprintf "Spaghetti splitting: %d blocks → %d blocks (+%d splits, +%.0f%%)"
    before after splits
    (if before = 0 then 0.0 else float_of_int splits /. float_of_int before *. 100.0)
