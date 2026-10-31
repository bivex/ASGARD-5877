(** Per-seed data-space ring codec pass. *)

type config = {
  codec_rate : int;
  seed       : int64;
}

val default_config : int64 -> config
val transform_func : cfg:config -> Ir.func -> Ir.func
