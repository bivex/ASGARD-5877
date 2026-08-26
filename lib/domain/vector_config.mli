(** Vector Configuration Value Object representing hardware vector engine parameters. *)

type t = private {
  vlen : int;
  elen : int;
  default_sew : Types.Sew.t;
  default_lmul : Types.Lmul.t;
  tail_policy : Types.Tail_policy.t;
  mask_policy : Types.Mask_policy.t;
  num_vregs : int;
}

(** Smart constructor validating power-of-2 invariants, elen <= vlen, and num_vregs >= 8. *)
val make :
  ?vlen:int ->
  ?elen:int ->
  ?default_sew:Types.Sew.t ->
  ?default_lmul:Types.Lmul.t ->
  ?tail_policy:Types.Tail_policy.t ->
  ?mask_policy:Types.Mask_policy.t ->
  ?num_vregs:int ->
  unit ->
  (t, Errors.t) result

(** Default configuration: VLEN=128, ELEN=64, SEW=E32, LMUL=M1, num_vregs=32. *)
val default : t

(** Number of bytes per vector register: [vlen / 8]. *)
val vlen_bytes : t -> int

(** [calculate_vlmax cfg sew lmul] calculates (VLEN / SEW) * LMUL. *)
val calculate_vlmax : t -> Types.Sew.t -> Types.Lmul.t -> int
