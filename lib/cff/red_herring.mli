(** Red Herring Complexity — Effort Asymmetry & Cognitive Deception Engine.
    ────────────────────────────────────────────────────────────────────────
    Decorrelates structural CFG complexity (block counts, edge density,
    MBA depth, state aliasing) from code semantic importance.
    Applies asymmetric pseudo-random noise fields across basic blocks,
    ensuring critical security logic appears structurally plain and uniform
    while harmless or decoy checks are amplified into high-entropy labyrinths. *)

type effort_tier =
  | StealthPlain      (** Minimal/zero transformations: blends with boilerplate *)
  | Modulated         (** Balanced transformations proportional to base config *)
  | RedHerringMonster (** Hyper-amplified: maximum CFF splitting, MBA depth, opaque checks *)

val hash_block_noise : seed:int64 -> block_id:int -> salt:int -> int64
(** Deterministic SplitMix64-based pseudo-random noise for a given block. *)

val block_effort_tier : seed:int64 -> block_id:int -> effort_tier
(** Classifies a block into an effort tier based on per-block noise.
    ~30% StealthPlain (0% split), ~50% Modulated, ~20% RedHerringMonster. *)

val modulate_split_rate : base_rate:int -> seed:int64 -> block_id:int -> int
(** Calculates effective CFF/spaghetti split rate (0..100) for a block. *)

val modulate_mba_depth : base_depth:int -> seed:int64 -> block_id:int -> int
(** Calculates effective MBA expansion depth (1..5) for a block. *)

val modulate_ghost_count : max_ghosts:int -> seed:int64 -> block_id:int -> int
(** Calculates effective ghost padding instruction count (0..max_ghosts) for a block. *)
