(** Dispatch_strategy — Multi-domain threaded dispatch and decentralized context model. *)

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

val scramble_index : context_layout -> int -> int

val generate :
  rng:Random.State.t ->
  total_opcodes:int ->
  ?num_domains:int ->
  ?enable_scattering:bool ->
  unit ->
  t
