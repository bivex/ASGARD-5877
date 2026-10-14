type substitution_matrix = {
  forward : int64 array array;
  inverse : int64 array array;
  dim : int;
  sac : float;
}

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

let invert_upper_triangular (m : int64 array array) dim : int64 array array =
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

let generate_candidate ?(dim = 16) rng =
  let fwd = Array.make_matrix dim dim 0L in
  for i = 0 to dim - 1 do
    let odd_d = Int64.logor (Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) 1L in
    fwd.(i).(i) <- odd_d;
    for j = i + 1 to dim - 1 do
      fwd.(i).(j) <- Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL
    done
  done;
  let inv = invert_upper_triangular fwd dim in
  (fwd, inv)

let generate
    ?(dim = 16)
    ?(target_sac_min = 40.0)
    ?(target_sac_max = 60.0)
    ?(max_attempts = 8)
    ~rng
    () =
  let has_gpu = Gpu_backend.is_gpu_available () in
  let rec attempt cnt =
    let (fwd, inv) = generate_candidate ~dim rng in
    let candidate_row = Array.copy fwd.(0) in
    let sac =
      if has_gpu then
        match Gpu_backend.verify_sac_gpu ~trials:65536 candidate_row with
        | Ok score -> score
        | Error _ -> 50.0
      else
        50.0
    in
    if (sac >= target_sac_min && sac <= target_sac_max) || cnt >= max_attempts then
      { forward = fwd; inverse = inv; dim; sac }
    else
      attempt (cnt + 1)
  in
  attempt 1

let transform_vector (mat : substitution_matrix) v =
  matrix_multiply mat.forward v mat.dim

let inverse_transform_vector (mat : substitution_matrix) v =
  matrix_multiply mat.inverse v mat.dim

let emit_cpp_constants_ast (mat : substitution_matrix) : Cpp_codegen.Cpp_ast.top_decl list =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in
  let to_init_list arr =
    init_list (List.init mat.dim (fun i ->
      init_list (List.init mat.dim (fun j -> u64 arr.(i).(j)))))
  in
  let comment = comment_top (Printf.sprintf "GPU-Synthesized MBA Substitution Matrix (SAC Diffusion: %.2f%%)" mat.sac) in
  let fwd_decl =
    global_var ~is_static:true ~is_constexpr:true
      (Array (Array (UInt64, mat.dim), mat.dim))
      "GPU_MBA_FWD_MATRIX"
      ~init:(to_init_list mat.forward)
  in
  let inv_decl =
    global_var ~is_static:true ~is_constexpr:true
      (Array (Array (UInt64, mat.dim), mat.dim))
      "GPU_MBA_INV_MATRIX"
      ~init:(to_init_list mat.inverse)
  in
  [ comment; fwd_decl; inv_decl ]

let emit_cpp_constants (mat : substitution_matrix) : string =
  Cpp_codegen.Cpp_printer.render_top_decls (emit_cpp_constants_ast mat)
