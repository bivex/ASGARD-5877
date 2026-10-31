open Vm_ir
open Mba_engine.Mba

type gpu_mba_pool = {
  solutions : int64 array;
  gpu_active : bool;
}

let mod_inv64 (k : int64) : int64 =
  let odd_k = Int64.logor k 1L in
  let rec iter x iters =
    if iters = 0 then x
    else
      let kx = Int64.mul odd_k x in
      let two_minus_kx = Int64.sub 2L kx in
      let next_x = Int64.mul x two_minus_kx in
      iter next_x (iters - 1)
  in
  iter odd_k 6

let create_pool ?(seed = 0x58771337CAFEBABE_L) ?(max_results = 256) ~rng () =
  let has_gpu = Gpu_backend.is_gpu_available () in
  if has_gpu then
    match Gpu_backend.synthesize_mba_gpu ~max_results seed with
    | Ok sols when Array.length sols > 0 ->
        { solutions = sols; gpu_active = true }
    | _ ->
        let fallback_sols = Array.init max_results (fun _ ->
          Int64.logor (Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) 1L) in
        { solutions = fallback_sols; gpu_active = false }
  else
    let fallback_sols = Array.init max_results (fun _ ->
      Int64.logor (Random.State.int64 rng 0x7FFFFFFFFFFFFFFFL) 1L) in
    { solutions = fallback_sols; gpu_active = false }

let pool_size pool = Array.length pool.solutions
let is_gpu_backed pool = pool.gpu_active

let get_seed pool rng =
  let idx = Random.State.int rng (Array.length pool.solutions) in
  pool.solutions.(idx)

(* Non-Linear Multiplicative Invariant: (a & b)*(a | b) + (a & ~b)*(~a & b) - (a * b) == 0 *)
let zero_inv_nl a b =
  Sub (
    Add (
      Mul (And (a, b), Or (a, b)),
      Mul (And (a, Not b), And (Not a, b))
    ),
    Mul (a, b)
  )

(* Linear Invariant: (a | b) + (a & b) - (a + b) == 0 *)
let zero_inv_lin a b =
  Sub (Add (Or (a, b), And (a, b)), Add (a, b))

let synthesize_gpu_add ~pool ~rng a b =
  let s = get_seed pool rng in
  match Random.State.int rng 4 with
  | 0 ->
      (* (a ^ b) + 2*(a & b) + Z_nl(a, b) *)
      Add (Add (Xor (a, b), Mul (Const 2L, And (a, b))), zero_inv_nl a b)
  | 1 ->
      (* (a | b) + (a & b) + Z_lin(a, b) *)
      Add (Add (Or (a, b), And (a, b)), zero_inv_lin a b)
  | 2 ->
      (* Mask partition with GPU seed bitmask *)
      let m = Const (Int64.logor s 0x5555555555555555L) in
      let not_m = Const (Int64.lognot (Int64.logor s 0x5555555555555555L)) in
      Add (
        Add (And (a, m), And (b, m)),
        Add (And (a, not_m), And (b, not_m))
      )
  | _ ->
      (* Modular scaling with GPU inverse *)
      let k = Int64.logor s 1L in
      let inv_k = mod_inv64 k in
      Add (
        Mul (Mul (a, Const k), Const inv_k),
        b
      )

let synthesize_gpu_sub ~pool ~rng a b =
  let s = get_seed pool rng in
  match Random.State.int rng 3 with
  | 0 ->
      (* (a ^ b) - 2*(~a & b) *)
      Sub (Xor (a, b), Mul (Const 2L, And (Not a, b)))
  | 1 ->
      (* 2*(a & ~b) - (a ^ b) *)
      Sub (Mul (Const 2L, And (a, Not b)), Xor (a, b))
  | _ ->
      (* a + ~b + 1 *)
      let k = Int64.logor s 1L in
      let inv_k = mod_inv64 k in
      Add (
        Add (a, Add (Not b, Const 1L)),
        Sub (Mul (Const k, Const inv_k), Const 1L)
      )

let synthesize_gpu_xor ~pool ~rng a b =
  let _s = get_seed pool rng in
  match Random.State.int rng 3 with
  | 0 ->
      (* (a | b) - (a & b) + Z_nl(a, b) *)
      Add (Sub (Or (a, b), And (a, b)), zero_inv_nl a b)
  | 1 ->
      (* (a + b) - 2*(a & b) *)
      Sub (Add (a, b), Mul (Const 2L, And (a, b)))
  | _ ->
      (* (a & ~b) | (~a & b) *)
      Or (And (a, Not b), And (Not a, b))

let synthesize_gpu_and ~pool ~rng a b =
  ignore pool;
  match Random.State.int rng 3 with
  | 0 ->
      (* (a + b) - (a | b) *)
      Sub (Add (a, b), Or (a, b))
  | 1 ->
      (* (a | b) - (a ^ b) *)
      Sub (Or (a, b), Xor (a, b))
  | _ ->
      (* a - (a & ~b) *)
      Sub (a, And (a, Not b))

let synthesize_gpu_or ~pool ~rng a b =
  ignore pool;
  match Random.State.int rng 3 with
  | 0 ->
      (* (a ^ b) + (a & b) *)
      Add (Xor (a, b), And (a, b))
  | 1 ->
      (* (a + b) - (a & b) *)
      Sub (Add (a, b), And (a, b))
  | _ ->
      (* (a ^ b) ^ (a & b) *)
      Xor (Xor (a, b), And (a, b))

let synthesize_gpu_mul ~pool ~rng a b =
  ignore pool;
  match Random.State.int rng 2 with
  | 0 ->
      (* NLMBA: (a & b)*(a | b) + (a & ~b)*(~a & b) *)
      Add (
        Mul (And (a, b), Or (a, b)),
        Mul (And (a, Not b), And (Not a, b))
      )
  | _ ->
      (* NLMBA form 2 *)
      Sub (
        Add (
          Mul (And (a, b), Add (a, b)),
          Mul (And (a, Not b), And (Not a, b))
        ),
        Mul (And (a, b), And (a, b))
      )

let obfuscate_alu ~pool ~rng ~dst ~src1 ~src2 op =
  let va = Var "a" in
  let vb = Var "b" in
  let expr_opt =
    match op with
    | Ir.Add -> Some (synthesize_gpu_add ~pool ~rng va vb)
    | Ir.Sub -> Some (synthesize_gpu_sub ~pool ~rng va vb)
    | Ir.Xor -> Some (synthesize_gpu_xor ~pool ~rng va vb)
    | Ir.And -> Some (synthesize_gpu_and ~pool ~rng va vb)
    | Ir.Or  -> Some (synthesize_gpu_or  ~pool ~rng va vb)
    | Ir.Imul -> Some (synthesize_gpu_mul ~pool ~rng va vb)
    | _ -> None
  in
  match expr_opt with
  | Some expr ->
      lower_to_ir ~dst ~env:[ ("a", src1); ("b", src2) ] expr
  | None ->
      [ Ir.Alu { op; dst; src1; src2; set_flags = false } ]
