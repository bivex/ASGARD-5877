open Ir
[@@@warning "-33"]
open Register

let create_decoy_block (max_id : int ref) (rng : Random.State.t) : basic_block =
  incr max_id;
  let id = !max_id in
  let decoy_imm = Int64.of_int (Random.State.bits rng) in
  {
    id;
    label = Printf.sprintf "decoy_bb_%d" id;
    instrs = [
      Mov { dst = Reg Register.vtmp0; src = Imm decoy_imm };
      Alu { op = Xor; dst = Register.vtmp0; src1 = Reg Register.vtmp0; src2 = Imm 0x5877CAFE1337L; set_flags = false };
      Alu { op = Add; dst = Register.vtmp1; src1 = Reg Register.vtmp0; src2 = Imm 42L; set_flags = false };
      Trap "Decoy block trap wire";
    ];
  }

let consumes_flags_before_def instrs =
  let rec check = function
    | [] -> false
    | (Jcc _ | Cmov _ | Setcc _ | Ccmp _ | Ccmn _ | Get_flags _ | Alu { op = (Adc | Sbb); _ }) :: _ ->
        true
    | (Cmp _ | Test _ | Alu { set_flags = true; _ } | Unary { set_flags = true; _ } | Set_flags _) :: _ ->
        false
    | _ :: rest -> check rest
  in
  check instrs

let ends_with_jcc (b : basic_block) =
  match List.rev b.instrs with
  | Jcc _ :: _ -> true
  | _ -> false

let split_block_with_opaque (max_id : int ref) (rng : Random.State.t) (b : basic_block) : basic_block list =
  if ends_with_jcc b || List.length b.instrs <= 3 then [ b ]
  else
    let split_pt = List.length b.instrs / 2 in
    let rec split n acc = function
      | [] -> (List.rev acc, [])
      | x :: xs when n = 0 -> (List.rev acc, x :: xs)
      | x :: xs -> split (n - 1) (x :: acc) xs
    in
    let (p1, p2) = split split_pt [] b.instrs in
    if consumes_flags_before_def p2 then [ b ]
    else begin
      incr max_id;
      let new_b2_id = !max_id in
      let decoy = create_decoy_block max_id rng in
      let opaque_branch =
        Opaque_predicates.generate_zero_predicate
          ~rng
          ~scratch:vtmp3
          ~target_true:(BlockId new_b2_id)
          ~target_decoy:(BlockId decoy.id)
      in
      let b1_instrs = p1 @ opaque_branch in
      let b1 = { b with instrs = b1_instrs } in
      let b2 = { id = new_b2_id; label = Printf.sprintf "%s_s%d" b.label new_b2_id; instrs = p2 } in
      [ b1; b2; decoy ]
    end

let transform ~(seed : Seed.t) (f : func) : func =
  let rng = Seed.make_rng (Seed.cfg_seed seed) in
  let max_id = ref 0 in
  Hashtbl.iter (fun id _ -> if id > !max_id then max_id := id) f.cfg.blocks;
  
  let new_blocks_list = ref [] in
  Hashtbl.iter (fun _ b ->
    if Random.State.bool rng then
      let split_res = split_block_with_opaque max_id rng b in
      new_blocks_list := split_res @ !new_blocks_list
    else
      new_blocks_list := b :: !new_blocks_list
  ) f.cfg.blocks;
  
  (* Inject standalone decoy networks *)
  let num_decoys = Random.State.int rng 2 + 1 in
  for _ = 1 to num_decoys do
    let decoy = create_decoy_block max_id rng in
    new_blocks_list := decoy :: !new_blocks_list
  done;
  
  (* Shuffle block insertion order (Fisher-Yates) *)
  let arr = Array.of_list !new_blocks_list in
  for i = Array.length arr - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let tmp = arr.(i) in
    arr.(i) <- arr.(j);
    arr.(j) <- tmp
  done;
  
  let new_tbl = Hashtbl.create (Array.length arr) in
  Array.iter (fun (b : basic_block) -> Hashtbl.replace new_tbl b.id b) arr;
  { f with cfg = { f.cfg with blocks = new_tbl } }
