(** Domain catalog: instruction families and frequency priors for V-ISA synthesis. *)

(** Complete catalog of 28 instruction families. *)
val family_catalog : (Instruction_class.t * Instruction_family.t list) list

(** Families available for a given instruction class. *)
val families_for : Instruction_class.t -> Instruction_family.t list

(** Find a family by base mnemonic (e.g. "vwadd"). *)
val lookup_family : string -> Instruction_family.t option

(** Names of registered profiles ("rvv-like", "uniform"). *)
val available_profiles : unit -> string list

(** Resolve a profile by name. *)
val get_profile : string -> (Generation_profile.t, Errors.t) result

(** [sample_family ~rng ~profile ~candidates] picks a family weighted by
    [profile.weight_for(klass) * family.weight]. *)
val sample_family :
  rng:Random.State.t ->
  profile:Generation_profile.t ->
  candidates:Instruction_family.t list ->
  Instruction_family.t

(** [assign_encodings families] assigns unique [funct6] values (0..63)
    in descending order of family weight, ensuring no (funct6, funct3) collision. *)
val assign_encodings :
  Instruction_family.t list ->
  ((Instruction_family.t * int) list, Errors.t) result

(** [generate_isa ~rng ?name ?config ?profile ~num_instructions ()] synthesizes a full
    V-ISA specification under the given profile and instruction budget. *)
val generate_isa :
  rng:Random.State.t ->
  ?name:string ->
  ?config:Vector_config.t ->
  ?profile:Generation_profile.t ->
  num_instructions:int ->
  unit ->
  (Vector_isa_spec.t, Errors.t) result
