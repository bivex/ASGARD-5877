(** Inter-Procedural Homomorphic Call Bridge (Step 4 Tier-4+):
    Транслирует закодированные регистры вызывающей VM (Caller, кодек \phi_1)
    напрямую в закодированные регистры вызываемой VM (Callee, кодек \phi_2)
    без расшифровки в открытый вид и без выхода в нативный ABI (VM_EXIT). *)

open Mba_engine.Metamorphic_ring

type transition_morphism = {
  scale : int64;  (** M = a_callee * a_caller^{-1} mod 2^64 *)
  shift : int64;  (** S = b_callee - M * b_caller mod 2^64 *)
}

(** Компиляция прямого гомоморфного перехода между кодеком Caller и кодеком Callee.
    Никакие ключи a_1, b_1, a_2, b_2 в рантайм не попадают — только свернутая пара (M, S)! *)
val compile_bridge_morphism : caller:ring_codec -> callee:ring_codec -> transition_morphism

(** Применение гомоморфного моста в рантайме: \hat{x}_{callee} = M * \hat{x}_{caller} + S *)
val apply_bridge_morphism : transition_morphism -> int64 -> int64

(** Композиция двух мостов (например, VM_1 -> VM_2 -> VM_3): T_{1->3} = T_{2->3} \circ T_{1->2} *)
val compose_morphisms : first:transition_morphism -> second:transition_morphism -> transition_morphism

(** Построение C++20 AST функции бесшовного перехода между двумя VM *)
val build_homomorphic_bridge_ast :
  bridge_name:string -> transition_morphism array -> Cpp_codegen.Cpp_ast.top_decl

(** Эмиссия C++20 кода бесшовного перехода между двумя виртуальными машинами *)
val emit_cpp20_homomorphic_bridge :
  bridge_name:string -> transition_morphism array -> string
