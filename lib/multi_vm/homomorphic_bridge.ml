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

let emit_cpp20_homomorphic_bridge ~(bridge_name : string) (morphisms : transition_morphism array) : string =
  let buf = Buffer.create 512 in
  Buffer.add_string buf (Printf.sprintf
    "// AUTO-GENERATED HOMOMORPHIC VM-TO-VM BRIDGE (NO ABI EXPOSURE)\n\
     __attribute__((always_inline)) inline void %s(const uint64_t* caller_regs, uint64_t* callee_regs) noexcept {\n"
    bridge_name);
  Array.iteri (fun i m ->
    Buffer.add_string buf (Printf.sprintf
      "    callee_regs[%d] = caller_regs[%d] * 0x%016LxULL + 0x%016LxULL;\n"
      i i m.scale m.shift)
  ) morphisms;
  Buffer.add_string buf "}\n";
  Buffer.contents buf
