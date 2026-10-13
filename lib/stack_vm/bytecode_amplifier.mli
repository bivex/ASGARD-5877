(** Mathematical Bytecode Amplifier & Treewidth Expander for ASGARD-5877:
    Превращает компактный байткод базовых блоков в плотный несократимый граф
    высокой алгебраической степени и большой древесной ширины (treewidth):
    1. Horner Polynomial Constant Synthesis (уничтожение открытых констант над Z_{2^64})
    2. Bit-Sliced Ripple/Lookahead Carry-Chain Adder/Sub Expansion
    3. Long-Range Expander Def-Use Webbing (неразделимые связи против оконного анализа) *)

open Stack_ir

type amplification_profile = {
  horner_degree       : int;   (** Степень интерполяционного полинома констант (например, 4..8) *)
  bit_slice_lanes     : int;   (** Декомпозиция сложения на полосы переносов (0 = отключено, 2 или 4) *)
  expander_chord_len  : int;   (** Длина хорды дальнодействующего сцепления в графе (5..15) *)
  expander_chord_rate : int;   (** Вероятность вставки expander knots (0..100) *)
}

val default_heavy_profile : amplification_profile
val balanced_profile : amplification_profile
val light_profile : amplification_profile
val adaptive_profile : ?block_size:int -> ?post_mba:bool -> unit -> amplification_profile

val rand_u64 : Random.State.t -> int64

(** Синтез полинома Горнера степени degree в случайной нечетной точке t_0:
    C = ((...(a_d * t_0 + a_{d-1}) * t_0 + ...) * t_0 + a_0) mod 2^64.
    Возвращает (t_0, [a_d; a_{d-1}; ...; a_0]). *)
val synth_horner_polynomial :
  Random.State.t -> target_const:int64 -> degree:int -> int64 * int64 list

(** Вычисление полинома Горнера по коэффициентам в точке t_0 (для верификации) *)
val eval_horner_polynomial : t0:int64 -> coeffs:int64 list -> int64

(** Генерация цепочки стековых операций вычисления полинома Горнера с маскированием t_0.
    Стековый дельта = +1 (эквивалентно PushImm target_const). *)
val emit_horner_stack_insns :
  Random.State.t -> target_const:int64 -> degree:int -> stack_op list

(** Генерация сети переносов для Add над Z_{2^64}.
    Стековый дельта = -1 (эквивалентно Add). *)
val emit_carry_chain_add :
  Random.State.t -> s1:int -> s2:int -> stack_op list

(** Генерация сети переносов для Sub над Z_{2^64}.
    Стековый дельта = -1 (эквивалентно Sub). *)
val emit_carry_chain_sub :
  Random.State.t -> s1:int -> s2:int -> stack_op list

(** Генерация алгебраического expander knot на вершине стека.
    Стековый дельта = 0 (сохраняет значение, уплотняет граф Def-Use). *)
val emit_expander_web_knot :
  Random.State.t -> ?s_reg:int option -> unit -> stack_op list

(** Трансформация отдельного базового блока *)
val amplify_block :
  Random.State.t -> profile:amplification_profile -> scratch_base:int -> block -> block

(** Трансформация программы Stack_ir:
    увеличивает объем и вычислительную сложность байткода в 10..35 раз без мертвого кода (0% DCE loss) *)
val amplify_stack_program :
  Random.State.t -> profile:amplification_profile -> program -> program

(** Статистика усиления (before vs after) *)
val amplifier_stats : program -> program -> string
