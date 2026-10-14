type matrix = int64 array array

type affine_bridge = {
  forward_matrix : matrix;
  inverse_matrix : matrix;
  dim : int;
  initial_digest : int64;
}

let initial_digest b = b.initial_digest
let dim b = b.dim

let rol64 v s =
  let s = s land 63 in
  Int64.logor (Int64.shift_left v s) (Int64.shift_right_logical v (64 - s))

let update_trace_digest prev_digest opcode vip =
  let k1 = rol64 prev_digest 13 in
  let golden = 0x9E3779B97F4A7C15L in
  let term = Int64.add opcode (Int64.mul vip golden) in
  Int64.logxor k1 term

let mod_inverse_64 a =
  if Int64.logand a 1L = 0L then
    invalid_arg "mod_inverse_64: even numbers are not invertible modulo 2^64"
  else
    let rec iter x i =
      if i >= 6 then x
      else
        let next_x = Int64.mul x (Int64.sub 2L (Int64.mul a x)) in
        iter next_x (i + 1)
    in
    iter 1L 0

let matrix_multiply m v dim =
  let res = Array.make dim 0L in
  for i = 0 to dim - 1 do
    let sum = ref 0L in
    for j = 0 to dim - 1 do
      sum := Int64.add !sum (Int64.mul m.(i).(j) v.(j))
    done;
    res.(i) <- !sum
  done;
  res

let invert_upper_triangular (m : matrix) dim : matrix =
  let inv = Array.make_matrix dim dim 0L in
  for i = 0 to dim - 1 do
    inv.(i).(i) <- mod_inverse_64 m.(i).(i)
  done;
  for i = dim - 1 downto 0 do
    for j = i + 1 to dim - 1 do
      let sum = ref 0L in
      for k = i + 1 to j do
        sum := Int64.add !sum (Int64.mul m.(i).(k) inv.(k).(j))
      done;
      inv.(i).(j) <- Int64.neg (Int64.mul inv.(i).(i) !sum)
    done
  done;
  inv

let generate_bridge ?(dim = 16) rng =
  let fwd = Array.make_matrix dim dim 0L in
  for i = 0 to dim - 1 do
    let odd_d = Int64.logor (Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) 1L in
    fwd.(i).(i) <- odd_d;
    for j = i + 1 to dim - 1 do
      fwd.(i).(j) <- Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL
    done
  done;
  let inv = invert_upper_triangular fwd dim in
  let initial_digest = Int64.logor (Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) 0x1337587700000000L in
  {
    forward_matrix = fwd;
    inverse_matrix = inv;
    dim;
    initial_digest;
  }

let forward_morph bridge v trace_digest =
  let dim = bridge.dim in
  let transformed = matrix_multiply bridge.forward_matrix v dim in
  let res = Array.make dim 0L in
  for i = 0 to dim - 1 do
    let mask = rol64 trace_digest (i * 3 + 7) in
    res.(i) <- Int64.logxor transformed.(i) mask
  done;
  res

let inverse_morph bridge v trace_digest =
  let dim = bridge.dim in
  let unmasked = Array.make dim 0L in
  for i = 0 to dim - 1 do
    let mask = rol64 trace_digest (i * 3 + 7) in
    unmasked.(i) <- Int64.logxor v.(i) mask
  done;
  matrix_multiply bridge.inverse_matrix unmasked dim

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl
open Cpp_codegen.Cpp_printer

let emit_cpp_bridge_code bridge =
  let dim = bridge.dim in
  let format_matrix name mat =
    let buf = Buffer.create 1024 in
    Buffer.add_string buf (Printf.sprintf "static const uint64_t %s[16][16] = {\n" name);
    for i = 0 to dim - 1 do
      Buffer.add_string buf "    { ";
      for j = 0 to dim - 1 do
        Buffer.add_string buf (Printf.sprintf "0x%016LXULL%s" mat.(i).(j) (if j = dim - 1 then "" else ", "));
      done;
      Buffer.add_string buf " },\n";
    done;
    Buffer.add_string buf "};";
    Buffer.contents buf
  in

  let fwd_mat_str = format_matrix "BRIDGE_FWD_MAT" bridge.forward_matrix in
  let inv_mat_str = format_matrix "BRIDGE_INV_MAT" bridge.inverse_matrix in

  let rol64_fn =
    func_decl
      ~attrs:[StaticFn; AlwaysInline]
      UInt64
      "bridge_rol64"
      [(UInt64, "v"); (Int32, "s")]
      [
        (var "s") &= i32 63;
        ret ((var "v" <<~ var "s") |~ (var "v" >>~ (i32 64 -~ var "s")));
      ]
  in

  let update_digest_fn =
    func_decl
      ~attrs:[StaticFn; AlwaysInline]
      UInt64
      "bridge_update_digest"
      [(UInt64, "prev"); (UInt64, "op"); (UInt64, "vip")]
      [
        let_u64 "k1" (call "bridge_rol64" [var "prev"; i32 13]);
        let_u64 "term" (var "op" +~ (var "vip" *~ u64 0x9E3779B97F4A7C15L));
        ret (var "k1" ^~ var "term");
      ]
  in

  let morph_math_to_flow_fn =
    func_decl
      ~attrs:[StaticFn; AlwaysInline]
      Void
      "in_place_morph_math_to_flow"
      [(Ptr UInt64, "math_regs"); (Ptr UInt64, "flow_stack"); (UInt64, "trace_digest")]
      [
        decl_var (Array (UInt64, 16)) "temp";
        for_range "i" (i32 0) (i32 16) [
          let_u64 "sum" (u64 0L);
          for_range "j" (i32 0) (i32 16) [
            var "sum" += (idx (idx (var "BRIDGE_FWD_MAT") (var "i")) (var "j") *~ idx (var "math_regs") (var "j"));
          ];
          idx (var "temp") (var "i") :=
            (var "sum" ^~ call "bridge_rol64" [var "trace_digest"; (var "i" *~ i32 3) +~ i32 7]);
        ];
        for_range "i" (i32 0) (i32 16) [
          idx (var "flow_stack") (var "i") := idx (var "temp") (var "i");
        ];
      ]
  in

  let morph_flow_to_math_fn =
    func_decl
      ~attrs:[StaticFn; AlwaysInline]
      Void
      "in_place_morph_flow_to_math"
      [(Ptr UInt64, "flow_stack"); (Ptr UInt64, "math_regs"); (UInt64, "trace_digest")]
      [
        decl_var (Array (UInt64, 16)) "unmasked";
        for_range "i" (i32 0) (i32 16) [
          idx (var "unmasked") (var "i") :=
            (idx (var "flow_stack") (var "i") ^~ call "bridge_rol64" [var "trace_digest"; (var "i" *~ i32 3) +~ i32 7]);
        ];
        for_range "i" (i32 0) (i32 16) [
          let_u64 "sum" (u64 0L);
          for_range "j" (i32 0) (i32 16) [
            var "sum" += (idx (idx (var "BRIDGE_INV_MAT") (var "i")) (var "j") *~ idx (var "unmasked") (var "j"));
          ];
          idx (var "math_regs") (var "i") := var "sum";
        ];
      ]
  in

  let decls = [
    comment_top "ASGARD-5877: ZERO-NATIVE IN-PLACE INTER-VM DISPATCH BRIDGE";
    comment_top "Affine GL_16(Z/2^64Z) State Morphing with Dynamic Trace Coupling";
    raw_top (Printf.sprintf "#define ASGARD_MULTI_VM_DIM %d" dim);
    raw_top (Printf.sprintf "static const uint64_t ASGARD_INITIAL_DIGEST = 0x%016LXULL;" bridge.initial_digest);
    raw_top fwd_mat_str;
    raw_top inv_mat_str;
    rol64_fn;
    update_digest_fn;
    morph_math_to_flow_fn;
    morph_flow_to_math_fn;
  ] in
  render_top_decls decls
