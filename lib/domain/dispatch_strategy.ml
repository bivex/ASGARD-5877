type host_reg_pin =
  | PinHostGpr of string
  | SpillStack of int
  | EncryptedRam of int64

type context_layout = {
  register_pins : (int * host_reg_pin) list;
  affine_a      : int;
  affine_b      : int;
  frame_size    : int;
}

type thread_domain = {
  domain_id     : int;
  opcode_subset : int list;
  domain_seed   : int64;
}

type t = {
  num_domains    : int;
  domains        : thread_domain list;
  context_layout : context_layout;
  enable_section_scattering : bool;
}

let rec gcd a b =
  if b = 0 then a else gcd b (a mod b)

let pick_coprime rng m =
  let rec loop () =
    let candidate = 3 + (Random.State.int rng (m - 3)) in
    let candidate = if candidate mod 2 = 0 then candidate + 1 else candidate in
    if gcd candidate m = 1 then candidate else loop ()
  in
  loop ()

let scramble_index layout vreg =
  (vreg * layout.affine_a + layout.affine_b) land (layout.frame_size - 1)

let generate ~rng ~total_opcodes ?(num_domains = 3) ?(enable_scattering = true) () =
  let frame_size = 256 in
  let a = pick_coprime rng frame_size in
  let b = 1 + Random.State.int rng 127 in
  
  (* Assign host registers or spilled stack slots *)
  let host_gprs = [ "r12"; "r13"; "r14"; "r15" ] in
  let register_pins =
    List.init 32 (fun i ->
      if i < List.length host_gprs then
        (i, PinHostGpr (List.nth host_gprs i))
      else
        let phys_offset = (i * a + b) land (frame_size - 1) in
        (i, SpillStack phys_offset))
  in
  
  let context_layout = { register_pins; affine_a = a; affine_b = b; frame_size } in
  
  (* Partition total_opcodes into num_domains *)
  let opcodes = List.init total_opcodes (fun i -> i) in
  let domain_buckets = Array.make num_domains [] in
  List.iter
    (fun op ->
      let d = Random.State.int rng num_domains in
      domain_buckets.(d) <- op :: domain_buckets.(d))
    opcodes;
    
  let domains =
    List.init num_domains (fun d ->
      let domain_seed = Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL in
      {
        domain_id = d;
        opcode_subset = List.rev domain_buckets.(d);
        domain_seed;
      })
  in
  
  {
    num_domains;
    domains;
    context_layout;
    enable_section_scattering = enable_scattering;
  }
