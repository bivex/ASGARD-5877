type t = {
  master_seed : int64;
  opcode_seed : int64;
  register_seed : int64;
  cfg_seed : int64;
  constant_seed : int64;
  mba_seed : int64;
  superop_seed : int64;
}

let fnv1a_64 (str : string) : int64 =
  let prime = 1099511628211L in
  let h = ref (-3750763034362895579L) in
  for i = 0 to String.length str - 1 do
    let b = Int64.of_int (Char.code str.[i]) in
    h := Int64.mul (Int64.logxor !h b) prime
  done;
  !h

let derive_subseed (t : t) (domain : string) : int64 =
  let domain_hash = fnv1a_64 domain in
  Int64.logxor t.master_seed domain_hash

let create ?master_seed () : t =
  let master =
    match master_seed with
    | Some s -> s
    | None ->
        Random.self_init ();
        let high = Int64.of_int (Random.bits ()) in
        let low = Int64.of_int (Random.bits ()) in
        Int64.logor (Int64.shift_left high 30) low
  in
  let base_t = {
    master_seed = master;
    opcode_seed = 0L;
    register_seed = 0L;
    cfg_seed = 0L;
    constant_seed = 0L;
    mba_seed = 0L;
    superop_seed = 0L;
  } in
  {
    master_seed = master;
    opcode_seed = derive_subseed base_t "OPCODE_PERMUTATION";
    register_seed = derive_subseed base_t "REGISTER_ALLOCATION";
    cfg_seed = derive_subseed base_t "CFG_TOPOLOGY";
    constant_seed = derive_subseed base_t "CONSTANT_BLINDING";
    mba_seed = derive_subseed base_t "MBA_TRANSFORMATION";
    superop_seed = derive_subseed base_t "SUPEROPERATOR_FUSION";
  }

let make_rng (seed : int64) : Random.State.t =
  let seed_array = [|
    Int64.to_int (Int64.logand seed 0x3FFFFFFFL);
    Int64.to_int (Int64.logand (Int64.shift_right_logical seed 30) 0x3FFFFFFFL);
  |] in
  Random.State.make seed_array

let to_string (t : t) : string =
  Printf.sprintf
    "Seed(master=0x%LX, op=0x%LX, reg=0x%LX, cfg=0x%LX, const=0x%LX, mba=0x%LX, superop=0x%LX)"
    t.master_seed t.opcode_seed t.register_seed t.cfg_seed t.constant_seed t.mba_seed t.superop_seed
