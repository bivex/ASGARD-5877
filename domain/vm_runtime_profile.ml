type t = {
  seed             : int64;
  dispatch         : Dispatch_strategy.t;
  mutation         : Mutation_profile.t;
  cff_depth        : int;
  enable_nested_vm : bool;
}

let generate ~seed ~total_opcodes ?(cff_depth = 8) ?(enable_nested_vm = true) () =
  let seed_int = Int64.to_int (Int64.logand seed 0x3FFFFFFFL) in
  let rng = Random.State.make [| seed_int |] in
  
  let dispatch = Dispatch_strategy.generate ~rng ~total_opcodes () in
  let mutation = Mutation_profile.generate ~rng ~total_opcodes () in
  
  {
    seed;
    dispatch;
    mutation;
    cff_depth;
    enable_nested_vm;
  }
