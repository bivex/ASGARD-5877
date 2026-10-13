(** Динамическая перестановка раскладки VMContext на границах эпох (P0-Fixed).
    Включает Cycle Decomposition для точного разложения перестановок на транспозиции
    без коллизий циклов и порчи контекста. *)

type t = {
  perm     : int array;
  inv_perm : int array;
}

val gen_permutation : rng:Random.State.t -> n:int -> t
val emit_epoch_rotation_cpp : t -> string

type epoch_schedule = {
  n_regs       : int;
  epoch_perms  : int array array;  (** epoch_id -> reg_id -> physical_slot *)
  inv_perms    : int array array;  (** epoch_id -> physical_slot -> reg_id *)
  epoch_masks  : int64 array;      (** Ключи маскирования индексов эпохи *)
}

(** Генерация расписания перестановок контекста для заданного числа эпох *)
val gen_epoch_schedule : Random.State.t -> n_regs:int -> n_epochs:int -> epoch_schedule

(** Получение физического слота для виртуального регистра в заданной эпохе *)
val physical_slot : epoch_schedule -> epoch:int -> reg_id:int -> int

(** Разложение произвольной перестановки target (где new_arr[target[i]] = old_arr[i])
    в точную последовательность пар индексов (u, v) для in-place swap *)
val decompose_into_swaps : int array -> (int * int) list

(** Симуляция ротации массива регистров между эпохами в OCaml (для верификации) *)
val apply_swaps_in_place : int64 array -> (int * int) list -> unit

(** Генерация C++20 функции in-place ротации регистров между эпохами по расписанию *)
val emit_schedule_epoch_rotation_cpp : epoch_schedule -> from_epoch:int -> to_epoch:int -> string
