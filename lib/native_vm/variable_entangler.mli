(** 2D Variable Entanglement (Step 2 Tier-4+):
    Сшивает пары независимых виртуальных регистров (x, y) обратимой матрицей
    A \in GL(2, Z_{2^64}), делая невозможным покомпонентный слайсинг и MCTS-синтез (Syntia). *)

type entanglement_matrix = {
  a11 : int64; a12 : int64;
  a21 : int64; a22 : int64;
  (* Обратная матрица A^{-1} mod 2^64 *)
  inv11 : int64; inv12 : int64;
  inv21 : int64; inv22 : int64;
  bias_u : int64;
  bias_v : int64;
}

(** Генерация случайной обратимой матрицы сцепления в GL(2, Z_{2^64}) *)
val gen_entanglement_matrix : Random.State.t -> entanglement_matrix

(** Прямое сшивание двух независимых переменных (x, y) -> (u, v) *)
val entangle_pair : entanglement_matrix -> int64 -> int64 -> int64 * int64

(** Обратное расщепление сшитой пары (u, v) -> (x, y) *)
val disentangle_pair : entanglement_matrix -> int64 -> int64 -> int64 * int64

(** Гомоморфное выполнение независимых прибавлений констант (x + dx, y + dy)
    НЕПОСРЕДСТВЕННО в сшитом пространстве (u, v) без расщепления! *)
val homomorphic_entangled_add_const :
  entanglement_matrix -> u:int64 -> v:int64 -> dx:int64 -> dy:int64 -> int64 * int64

(** Гомоморфная линейная трансформация пары:
    вычисляет образ (x + y, x - y) прямо над сшитыми переменными (u, v),
    возвращая новую сшитую пару (u', v') в том же самом базисе A! *)
val homomorphic_coupled_butterfly :
  entanglement_matrix -> u:int64 -> v:int64 -> int64 * int64
