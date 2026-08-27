type matrix = int64 array array

type affine_bridge = {
  forward_matrix : matrix;
  inverse_matrix : matrix;
  dim : int;
  initial_digest : int64;
}

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
    failwith "mod_inverse_64: even numbers are not invertible modulo 2^64"
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

let emit_cpp_bridge_code bridge =
  let buf = Buffer.create 2048 in
  let dim = bridge.dim in
  Buffer.add_string buf "// =========================================================================\n";
  Buffer.add_string buf "// ASGARD-5877: ZERO-NATIVE IN-PLACE INTER-VM DISPATCH BRIDGE\n";
  Buffer.add_string buf "// Affine GL_16(Z/2^64Z) State Morphing with Dynamic Trace Coupling\n";
  Buffer.add_string buf "// =========================================================================\n\n";

  Buffer.add_string buf (Printf.sprintf "#define ASGARD_MULTI_VM_DIM %d\n" dim);
  Buffer.add_string buf (Printf.sprintf "static const uint64_t ASGARD_INITIAL_DIGEST = 0x%016LXULL;\n\n" bridge.initial_digest);

  Buffer.add_string buf "static const uint64_t BRIDGE_FWD_MAT[16][16] = {\n";
  for i = 0 to dim - 1 do
    Buffer.add_string buf "    { ";
    for j = 0 to dim - 1 do
      Buffer.add_string buf (Printf.sprintf "0x%016LXULL%s" bridge.forward_matrix.(i).(j) (if j = dim - 1 then "" else ", "));
    done;
    Buffer.add_string buf " },\n";
  done;
  Buffer.add_string buf "};\n\n";

  Buffer.add_string buf "static const uint64_t BRIDGE_INV_MAT[16][16] = {\n";
  for i = 0 to dim - 1 do
    Buffer.add_string buf "    { ";
    for j = 0 to dim - 1 do
      Buffer.add_string buf (Printf.sprintf "0x%016LXULL%s" bridge.inverse_matrix.(i).(j) (if j = dim - 1 then "" else ", "));
    done;
    Buffer.add_string buf " },\n";
  done;
  Buffer.add_string buf "};\n\n";

  Buffer.add_string buf {|
static inline uint64_t bridge_rol64(uint64_t v, int s) {
    s &= 63;
    return (v << s) | (v >> (64 - s));
}

static inline uint64_t bridge_update_digest(uint64_t prev, uint64_t op, uint64_t vip) {
    uint64_t k1 = bridge_rol64(prev, 13);
    uint64_t term = op + (vip * 0x9E3779B97F4A7C15ULL);
    return k1 ^ term;
}

static inline void in_place_morph_math_to_flow(uint64_t* math_regs, uint64_t* flow_stack, uint64_t trace_digest) {
    uint64_t temp[16];
    for (int i = 0; i < 16; ++i) {
        uint64_t sum = 0;
        for (int j = 0; j < 16; ++j) {
            sum += BRIDGE_FWD_MAT[i][j] * math_regs[j];
        }
        temp[i] = sum ^ bridge_rol64(trace_digest, i * 3 + 7);
    }
    // In-place zero-bridge write directly into flow stack slots
    for (int i = 0; i < 16; ++i) {
        flow_stack[i] = temp[i];
    }
}

static inline void in_place_morph_flow_to_math(uint64_t* flow_stack, uint64_t* math_regs, uint64_t trace_digest) {
    uint64_t unmasked[16];
    for (int i = 0; i < 16; ++i) {
        unmasked[i] = flow_stack[i] ^ bridge_rol64(trace_digest, i * 3 + 7);
    }
    for (int i = 0; i < 16; ++i) {
        uint64_t sum = 0;
        for (int j = 0; j < 16; ++j) {
            sum += BRIDGE_INV_MAT[i][j] * unmasked[j];
        }
        math_regs[i] = sum;
    }
}
|};
  Buffer.contents buf
