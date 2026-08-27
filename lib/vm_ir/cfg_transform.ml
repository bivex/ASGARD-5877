open Ir

let split_block (max_id : int ref) (b : basic_block) : basic_block list =
  if List.length b.instrs <= 3 then [ b ]
  else
    let split_pt = List.length b.instrs / 2 in
    let rec split n acc = function
      | [] -> (List.rev acc, [])
      | x :: xs when n = 0 -> (List.rev acc, x :: xs)
      | x :: xs -> split (n - 1) (x :: acc) xs
    in
    let (p1, p2) = split split_pt [] b.instrs in
    incr max_id;
    let new_b2_id = !max_id in
    let b1_instrs = p1 @ [ Jmp (BlockId new_b2_id) ] in
    let b1 = { b with instrs = b1_instrs } in
    let b2 = { id = new_b2_id; label = Printf.sprintf "%s_split" b.label; instrs = p2 } in
    [ b1; b2 ]

let transform ~(seed : Seed.t) (f : func) : func =
  let rng = Seed.make_rng seed.cfg_seed in
  let max_id = ref 0 in
  Hashtbl.iter (fun id _ -> if id > !max_id then max_id := id) f.cfg.blocks;
  
  let new_blocks_list = ref [] in
  Hashtbl.iter (fun _ b ->
    if Random.State.bool rng then
      let split_res = split_block max_id b in
      new_blocks_list := split_res @ !new_blocks_list
    else
      new_blocks_list := b :: !new_blocks_list
  ) f.cfg.blocks;
  
  let new_tbl = Hashtbl.create (List.length !new_blocks_list) in
  List.iter (fun (b : basic_block) -> Hashtbl.replace new_tbl b.id b) !new_blocks_list;
  { f with cfg = { f.cfg with blocks = new_tbl } }
