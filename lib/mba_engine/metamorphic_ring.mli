(** Гомоморфное кодирование данных в кольце Z_{2^64} и нелинейные инволюции против SiMBA/MBA-Blast *)

type ring_codec = {
  a     : int64;
  a_inv : int64;
  b     : int64;
}

val inv_mod_2_64 : int64 -> int64
val gen_ring_codec : Random.State.t -> ring_codec
val encode_val : ring_codec -> int64 -> int64
val decode_val : ring_codec -> int64 -> int64

(** Предвычисление коэффициентов (C1, C2, C3) для гомоморфного сложения:
    \hat{z} = C1 * \hat{x} + C2 * \hat{y} + C3 (mod 2^64) *)
val compile_homomorphic_add :
  ring_codec -> ring_codec -> ring_codec -> int64 * int64 * int64

(** Предвычисление коэффициентов (K_xy, K_x, K_y, K_0) для гомоморфного умножения:
    \hat{z} = K_xy * (\hat{x} * \hat{y}) + K_x * \hat{x} + K_y * \hat{y} + K_0 (mod 2^64) *)
val compile_homomorphic_mul :
  ring_codec -> ring_codec -> ring_codec -> int64 * int64 * int64 * int64

(** Нелинейная биективная инволюция F(x) = x ^ (((x & 0x7FFFFFFF) * odd_c) lsl 33),
    разрушающая 2^k-мерное линейное пространство табличных решателей SiMBA / MBA-Blast.
    Обладает свойством строгой самообратимости: F(F(x)) == x для всех 64-битных входов! *)
val eval_xorshift33_involution : c_odd:int64 -> int64 -> int64
