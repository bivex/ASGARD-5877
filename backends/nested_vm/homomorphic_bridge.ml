open Int64
open Mba_engine.Metamorphic_ring

type transition_morphism = {
  scale : int64;
  shift : int64;
}

let compile_bridge_morphism ~(caller : ring_codec) ~(callee : ring_codec) : transition_morphism =
  (* \phi_2(\phi_1^{-1}(\hat{x})) = a_2 * (a_1^{-1} * (\hat{x} - b_1)) + b_2
     = (a_2 * a_1^{-1}) * \hat{x} + (b_2 - a_2 * a_1^{-1} * b_1) mod 2^64 *)
  let scale = mul callee.a caller.a_inv in
  let shift = sub callee.b (mul scale caller.b) in
  { scale; shift }

let apply_bridge_morphism (m : transition_morphism) (x_hat_caller : int64) : int64 =
  add (mul m.scale x_hat_caller) m.shift

let compose_morphisms ~(first : transition_morphism) ~(second : transition_morphism) : transition_morphism =
  (* second(first(x)) = s2 * (s1 * x + sh1) + sh2 = (s2*s1)*x + (s2*sh1 + sh2) *)
  let scale = mul second.scale first.scale in
  let shift = add (mul second.scale first.shift) second.shift in
  { scale; shift }

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl

let build_homomorphic_bridge_ast ~(bridge_name : string) (morphisms : transition_morphism array) : top_decl =
  let stmts = Array.to_list (Array.mapi (fun i m ->
    (idx (var "callee_regs") (i32 i)) :=
      ((idx (var "caller_regs") (i32 i)) *~ u64 m.scale) +~ u64 m.shift
  ) morphisms) in

  FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = bridge_name;
    params   = [(ConstPtr UInt64, "caller_regs"); (Ptr UInt64, "callee_regs")];
    body     = stmts;
  }

let emit_cpp20_homomorphic_bridge ~(bridge_name : string) (morphisms : transition_morphism array) : string =
  let fn = build_homomorphic_bridge_ast ~bridge_name morphisms in
  let buf = Buffer.create 512 in
  let fmt = Format.formatter_of_buffer buf in
  Format.fprintf fmt "// AUTO-GENERATED HOMOMORPHIC VM-TO-VM BRIDGE (NO ABI EXPOSURE)@,%a@."
    Cpp_codegen.Cpp_printer.pp_top_decl fn;
  Buffer.contents buf

