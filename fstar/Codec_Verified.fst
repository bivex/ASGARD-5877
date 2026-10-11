(**
  Codec_Verified.fst — Формальная верификация кодека инструкций Vanguard-9292 в F*.
  F* 2026.08.23 + Z3 5.0.0.

  Доказывает:
  1. Корректность упаковки и распаковки битовых срезов (Bitfield Slice Packing Roundtrip).
  2. Инволютивность шифрования скользящим ключом XOR над 64-битными последовательностями.
  3. Полную обратимость кодека инструкций (End-to-End Encrypted Codec Roundtrip):
     decode (encode insn key) key == insn.
  4. Тотальную безопасность парсера (Parser Total Safety / Crash Freedom):
     Для ЛЮБОГО 64-битного потока бит декодер тотален, детерминирован и не падает.
*)
module Codec_Verified

open FStar.Seq

(* ------------------------------------------------------------------ *)
(* 1. Базовые типы битовых последовательностей                         *)
(* ------------------------------------------------------------------ *)

type bit = bool
type word64 = s:seq bit{length s == 64}
type byte8  = s:seq bit{length s == 8}
type byte16 = s:seq bit{length s == 16}

type v_instr = {
  v_op   : byte8;
  v_dst  : byte8;
  v_src1 : byte8;
  v_src2 : byte8;
  v_imm  : byte16;
  v_mask : byte8;
  v_junk : byte8;
}

(* ------------------------------------------------------------------ *)
(* 2. Леммы декомпозиции срезов последовательностей                   *)
(* ------------------------------------------------------------------ *)

val lemma_slice_prefix : #a:Type -> s1:seq a -> s2:seq a ->
  Lemma (equal (slice (append s1 s2) 0 (length s1)) s1)
let lemma_slice_prefix #a s1 s2 =
  lemma_eq_intro (slice (append s1 s2) 0 (length s1)) s1

val lemma_slice_suffix : #a:Type -> s1:seq a -> s2:seq a ->
  Lemma (equal (slice (append s1 s2) (length s1) (length s1 + length s2)) s2)
let lemma_slice_suffix #a s1 s2 =
  lemma_eq_intro (slice (append s1 s2) (length s1) (length s1 + length s2)) s2

val lemma_slice_nested : #a:Type -> s1:seq a -> s2:seq a -> i:nat -> j:nat{i <= j /\ j <= length s2} ->
  Lemma (equal (slice (append s1 s2) (length s1 + i) (length s1 + j)) (slice s2 i j))
let lemma_slice_nested #a s1 s2 i j =
  lemma_eq_intro (slice (append s1 s2) (length s1 + i) (length s1 + j)) (slice s2 i j)

(* ------------------------------------------------------------------ *)
(* 3. Упаковка и распаковка инструкции Vanguard-9292                  *)
(* ------------------------------------------------------------------ *)

let pack (i:v_instr) : word64 =
  let w_tail5 = append i.v_imm (append i.v_mask i.v_junk) in
  let w_tail6 = append i.v_src2 w_tail5 in
  let w_tail7 = append i.v_src1 w_tail6 in
  let w_tail8 = append i.v_dst w_tail7 in
  append i.v_op w_tail8

let unpack (w:word64) : v_instr = {
  v_op   = slice w 0 8;
  v_dst  = slice w 8 16;
  v_src1 = slice w 16 24;
  v_src2 = slice w 24 32;
  v_imm  = slice w 32 48;
  v_mask = slice w 48 56;
  v_junk = slice w 56 64;
}

(** Теорема 1: Упаковка и последующая распаковка сохраняют инструкцию идентично *)
val theorem_pack_unpack_roundtrip : i:v_instr ->
  Lemma (unpack (pack i) == i)
let theorem_pack_unpack_roundtrip i =
  let w_tail5 = append i.v_imm (append i.v_mask i.v_junk) in
  let w_tail6 = append i.v_src2 w_tail5 in
  let w_tail7 = append i.v_src1 w_tail6 in
  let w_tail8 = append i.v_dst w_tail7 in
  let w = append i.v_op w_tail8 in
  (* Поле op: [0..8) *)
  lemma_slice_prefix i.v_op w_tail8;
  lemma_eq_elim (slice w 0 8) i.v_op;
  (* Поле dst: [8..16) *)
  lemma_slice_nested i.v_op w_tail8 0 8;
  lemma_slice_prefix i.v_dst w_tail7;
  lemma_eq_elim (slice w 8 16) i.v_dst;
  (* Поле src1: [16..24) *)
  lemma_slice_nested i.v_op w_tail8 8 16;
  lemma_slice_nested i.v_dst w_tail7 0 8;
  lemma_slice_prefix i.v_src1 w_tail6;
  lemma_eq_elim (slice w 16 24) i.v_src1;
  (* Поле src2: [24..32) *)
  lemma_slice_nested i.v_op w_tail8 16 24;
  lemma_slice_nested i.v_dst w_tail7 8 16;
  lemma_slice_nested i.v_src1 w_tail6 0 8;
  lemma_slice_prefix i.v_src2 w_tail5;
  lemma_eq_elim (slice w 24 32) i.v_src2;
  (* Поле imm: [32..48) *)
  lemma_slice_nested i.v_op w_tail8 24 40;
  lemma_slice_nested i.v_dst w_tail7 16 32;
  lemma_slice_nested i.v_src1 w_tail6 8 24;
  lemma_slice_nested i.v_src2 w_tail5 0 16;
  lemma_slice_prefix i.v_imm (append i.v_mask i.v_junk);
  lemma_eq_elim (slice w 32 48) i.v_imm;
  (* Поле mask: [48..56) *)
  lemma_slice_nested i.v_op w_tail8 40 48;
  lemma_slice_nested i.v_dst w_tail7 32 40;
  lemma_slice_nested i.v_src1 w_tail6 24 32;
  lemma_slice_nested i.v_src2 w_tail5 16 24;
  lemma_slice_nested i.v_imm (append i.v_mask i.v_junk) 0 8;
  lemma_slice_prefix i.v_mask i.v_junk;
  lemma_eq_elim (slice w 48 56) i.v_mask;
  (* Поле junk: [56..64) *)
  lemma_slice_nested i.v_op w_tail8 48 56;
  lemma_slice_nested i.v_dst w_tail7 40 48;
  lemma_slice_nested i.v_src1 w_tail6 32 40;
  lemma_slice_nested i.v_src2 w_tail5 24 32;
  lemma_slice_nested i.v_imm (append i.v_mask i.v_junk) 8 16;
  lemma_slice_suffix i.v_mask i.v_junk;
  lemma_eq_elim (slice w 56 64) i.v_junk

(* ------------------------------------------------------------------ *)
(* 4. Шифрование скользящим ключом XOR                                *)
(* ------------------------------------------------------------------ *)

let xor_words (w1:word64) (w2:word64) : word64 =
  init 64 (fun idx -> index w1 idx <> index w2 idx)

(** Теорема 2: Скользящий ключ инволютивен *)
val theorem_key_involution : w:word64 -> k:word64 ->
  Lemma (equal (xor_words (xor_words w k) k) w)
let theorem_key_involution w k =
  lemma_eq_intro (xor_words (xor_words w k) k) w

(* ------------------------------------------------------------------ *)
(* 5. Главная теорема 3: Полная обратимость зашифрованного кодека     *)
(* ------------------------------------------------------------------ *)

let encode (i:v_instr) (key:word64) : word64 =
  xor_words (pack i) key

let decode (raw:word64) (key:word64) : v_instr =
  let w = xor_words raw key in
  unpack w

val theorem_codec_roundtrip : i:v_instr -> key:word64 ->
  Lemma (decode (encode i key) key == i)
let theorem_codec_roundtrip i key =
  theorem_key_involution (pack i) key;
  lemma_eq_elim (xor_words (xor_words (pack i) key) key) (pack i);
  theorem_pack_unpack_roundtrip i

(* ------------------------------------------------------------------ *)
(* 6. Главная теорема 4: Тотальная безопасность парсера (No Panics)   *)
(* ------------------------------------------------------------------ *)

type parse_result =
  | Parse_Success : v_instr -> parse_result
  | Parse_Junk    : byte8 -> parse_result
  | Parse_Invalid : byte8 -> parse_result

let parse_word (raw:word64) (key:word64) (is_junk:byte8 -> bool) (is_valid:byte8 -> bool) : parse_result =
  let insn = decode raw key in
  if is_junk insn.v_op then Parse_Junk insn.v_op
  else if is_valid insn.v_op then Parse_Success insn
  else Parse_Invalid insn.v_op

(** Теорема: Парсер тотален и никогда не падает при любых 64-битных данных *)
val theorem_parser_total_safety :
  raw:word64 -> key:word64 -> is_junk:(byte8 -> bool) -> is_valid:(byte8 -> bool) ->
  Lemma (ensures (
    match parse_word raw key is_junk is_valid with
    | Parse_Success i -> is_valid i.v_op
    | Parse_Junk j    -> is_junk j
    | Parse_Invalid u -> not (is_junk u) /\ not (is_valid u)
  ))
let theorem_parser_total_safety raw key is_junk is_valid = ()
