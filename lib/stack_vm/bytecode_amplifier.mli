(** Mathematical Bytecode Amplifier for ASGARD-5877:
    уплотняет def-use граф базовых блоков стека-VM без изменения семантики.
    Реализованные механизмы (все — тождества над Z_{2^64}):
    1. Horner Polynomial Constant Synthesis (уничтожение открытых констант):
       PushImm C → полином степени horner_degree с маскированием t_0.
    2. Carry-Chain Add/Sub: двухстадийный ripple через минтерм-базис
       NOR/NAND (мост к Mba_engine.Nullspace_mba) + кольцевой твист
       k_odd * k_inv (Mba_engine.Metamorphic_ring). При живых флагах
       замена завершается скрытым ре-дефайном CC_OP_ADD/SUB на
       сохранённых операндах (sx, sy) — PushFlags-обёртка здесь
       некорректна (восстановила бы до-командные флаги).
    3. Def-Use Webbing: тождественный нуль Nor(r, Nor(r, r)), сцепляемый
       со случайным якорем из кольцевого буфера последних K записей
       (K = clamp expander_chord_len 1..6) — хорды дальнодействуют до
       K записей назад, а не только к последней.
    4. Ring twist после Mul/Nor/Nand/Shl/Shr/Sar/Div/Idiv: исходная
       команда остаётся, поверх — нейтральный к флагам обратимый
       скейлинг (x * k) * k^{-1} = x.

    Что пока НЕ реализлено (заявлено в road-map, не здесь):
    - bit_slice_lanes используется только как вкл/выкл carry-chain
      (число полос не параметризует разложение);
    - хорды внутриблочные (межблочных якорей через Context_allocator нет);
    - treewidth-оценки в amplifier_stats нет (только op-count ratio);
    - Div/Idiv/сдвиги переменной величины не пере-кодируются алгебраически
      (только ring twist поверх). *)

open Stack_ir

type amplification_profile = {
  horner_degree       : int;   (** Степень интерполяционного полинома констант (например, 2..8) *)
  bit_slice_lanes     : int;   (** 0 = carry-chain выключен; > 0 = вкл (полосность пока не параметризует разложение) *)
  expander_chord_len  : int;   (** Периодичность хорд (шаг) и размер кольца якорей K = clamp 1..6 *)
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

(** Кольцевой твист [PushImm k_odd; Mul; PushImm k_inv; Mul]:
    значение- и флаго-сохраняющий (Mul нейтрален к флагам).
    Стековый дельта = 0. *)
val emit_ring_twist : Random.State.t -> stack_op list

(** Минтерм-представления над парой регистров (мост к Nullspace_mba),
    каждое оставляет одно значение на стеке. *)
val push_or_regs : int -> int -> stack_op list
val push_and_regs : int -> int -> stack_op list
val push_xor_regs : int -> int -> stack_op list

(** Скрытый ре-дефайн флагов CC_OP_ADD/SUB{src1=sx; src2=sy} после
    carry-chain замены при живых флагах. Дельта = 0. *)
val emit_flag_redef_add : int -> int -> stack_op list
val emit_flag_redef_sub : int -> int -> stack_op list

(** Сеть переносов для Add над Z_{2^64} (итог = s1 + s2, дельта = +1
    от пустого стека; операнды считываются из s1/s2).
    Исходные операнды сохраняются в sx/sy. *)
val emit_carry_chain_add :
  Random.State.t -> s1:int -> s2:int -> sx:int -> sy:int -> stack_op list

(** Сеть переносов для Sub над Z_{2^64} (итог = s1 - s2).
    Исходный y сохраняется в sy для ре-дефайна флагов. *)
val emit_carry_chain_sub :
  Random.State.t -> s1:int -> s2:int -> sx:int -> sy:int -> stack_op list

(** Тождественный нуль Nor(r, Nor(r, r)) ≡ 0, сцепляемый с регистром-якорем
    (дальнодействующая хорда def-use) или с вершиной стека. Дельта = 0. *)
val emit_expander_web_knot :
  Random.State.t -> ?s_reg:int option -> unit -> stack_op list

(** Трансформация отдельного базового блока *)
val amplify_block :
  Random.State.t -> profile:amplification_profile -> scratch_base:int -> block -> block

(** Трансформация программы Stack_ir (детерминизм: блоки обрабатываются
    в порядке возрастания id). Увеличивает объем байткода без мертвого кода. *)
val amplify_stack_program :
  Random.State.t -> ?ctx:Context_allocator.t -> profile:amplification_profile -> program -> program

(** Статистика усиления (before vs after; пока только op-count ratio) *)
val amplifier_stats : program -> program -> string
