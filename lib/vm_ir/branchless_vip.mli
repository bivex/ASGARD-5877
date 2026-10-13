(** Branchless VIP Arithmetic & Flag Elimination (Step 1 Tier-4+):
    Превращает условные переходы (JZ, JNZ, JB, JAE, JL, JGE) в чистую арифметику
    над Virtual Instruction Pointer (VIP) без единой инструкции CMP/TEST/JCC. *)

type branch_cond =
  | CondEq   (** x == y (ZF == 1) *)
  | CondNe   (** x != y (ZF == 0) *)
  | CondUlt  (** x < y unsigned (CF == 1) *)
  | CondUge  (** x >= y unsigned (CF == 0) *)
  | CondSlt  (** x < y signed (SF != OF) *)
  | CondSge  (** x >= y signed (SF == OF) *)

(** Арифметический индикатор is_zero(d) \in {0, 1} без ветвлений:
    is_zero(d) = 1 - ((d | -d) lsr 63) *)
val eval_is_zero_branchless : int64 -> int64

(** Вычисление булева условия перехода (возвращает 1L если условие истинно, 0L если ложно)
    исключительно через побитовые сдвиги и арифметику кольца Z_{2^64} *)
val eval_cond_branchless : branch_cond -> int64 -> int64 -> int64

(** Вычисление следующего VIP без ветвлений:
    next_vip = fallthrough_vip + cond_bit * (target_vip - fallthrough_vip) *)
val compute_next_vip_branchless :
  cond:branch_cond -> lhs:int64 -> rhs:int64 ->
  target_vip:int64 -> fallthrough_vip:int64 -> int64

(** Одновременное обновление VIP и потокового ключа (Rolling Key) без ветвлений:
    на истинной ветке добавляется key_delta_taken, на ложной — key_delta_fallthrough *)
val compute_vip_and_key_branchless :
  cond:branch_cond -> lhs:int64 -> rhs:int64 ->
  target_vip:int64 -> fallthrough_vip:int64 ->
  base_key:int64 -> key_delta_taken:int64 -> key_delta_fallthrough:int64 ->
  int64 * int64

(** Построение типизированного C++20 AST для Branchless VIP диспетчера *)
val build_branchless_vip_ast : unit -> Cpp_codegen.Cpp_ast.top_decl list

(** Генерация C++20 заголовка для Branchless VIP диспетчера *)
val emit_branchless_vip_cpp_header : unit -> string
