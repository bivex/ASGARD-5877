(** Inter-Procedural Homomorphic Call Bridge (Step 4 Tier-4+):
    Translates the encoded registers of the calling VM (Caller, codec \phi_1)
    directly into the encoded registers of the called VM (Callee, codec \phi_2)
    without decrypting them into plaintext and without exiting to the native ABI (VM_EXIT). *)

open Mba_engine.Metamorphic_ring

type transition_morphism = {
  scale : int64;  (** M = a_callee * a_caller^{-1} mod 2^64 *)
  shift : int64;  (** S = b_callee - M * b_caller mod 2^64 *)
}

(** Compilation of the direct homomorphic transition between the Caller codec and the Callee codec.
    None of the keys a_1, b_1, a_2, b_2 reach the runtime — only the folded pair (M, S)! *)
val compile_bridge_morphism : caller:ring_codec -> callee:ring_codec -> transition_morphism

(** Application of the homomorphic bridge at runtime: \hat{x}_{callee} = M * \hat{x}_{caller} + S *)
val apply_bridge_morphism : transition_morphism -> int64 -> int64

(** Composition of two bridges (for example, VM_1 -> VM_2 -> VM_3): T_{1->3} = T_{2->3} \circ T_{1->2} *)
val compose_morphisms : first:transition_morphism -> second:transition_morphism -> transition_morphism

(** Construction of the C++20 AST of the seamless transition function between two VMs *)
val build_homomorphic_bridge_ast :
  bridge_name:string -> transition_morphism array -> Cpp_codegen.Cpp_ast.top_decl

(** Emission of the C++20 code of the seamless transition between two virtual machines *)
val emit_cpp20_homomorphic_bridge :
  bridge_name:string -> transition_morphism array -> string
