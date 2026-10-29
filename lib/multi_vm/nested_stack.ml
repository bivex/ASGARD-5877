(** Multi-VM Nested Stack (VM-in-VM):
    Combinatorial and number-theoretic primitives for nested virtual machine execution. *)

open Int64

(** {1 OEIS A000108: Catalan Numbers & Dyck Words} *)

let catalan (n : int) : int64 =
  if n < 0 then invalid_arg "Nested_stack.catalan: negative index"
  else if n = 0 || n = 1 then 1L
  else
    let res = ref 1L in
    for i = 2 to n do
      let num = mul !res (of_int (2 * ((2 * i) - 1))) in
      res := div num (of_int (i + 1))
    done;
    !res

let is_dyck (word : bool list) : bool =
  let rec loop height = function
    | [] -> height = 0
    | true :: rest -> loop (height + 1) rest
    | false :: rest -> if height <= 0 then false else loop (height - 1) rest
  in
  loop 0 word

(* Number of non-negative paths of length p from height h to 0 *)
let path_count_table : (int * int, int64) Hashtbl.t = Hashtbl.create 512

let rec path_count (p : int) (h : int) : int64 =
  if h < 0 || h > p then 0L
  else if p = 0 then (if h = 0 then 1L else 0L)
  else
    match Hashtbl.find_opt path_count_table (p, h) with
    | Some v -> v
    | None ->
        let v = add (path_count (p - 1) (h + 1)) (path_count (p - 1) (h - 1)) in
        Hashtbl.replace path_count_table (p, h) v;
        v

let dyck_rank (word : bool list) : int64 =
  if not (is_dyck word) then
    invalid_arg "Nested_stack.dyck_rank: input is not a valid Dyck word";
  let len = List.length word in
  let rank = ref 0L in
  let height = ref 0 in
  List.iteri
    (fun i is_open ->
      let rem = len - 1 - i in
      if not is_open then begin
        let paths_if_open = path_count rem (!height + 1) in
        rank := add !rank paths_if_open;
        height := !height - 1
      end else begin
        height := !height + 1
      end)
    word;
  !rank

(** {1 OEIS A004001: Hofstadter-Conway Tier Dispatch} *)

let precompute_a004001 (n : int) : int array =
  if n <= 0 then [||]
  else if n = 1 then [| 1 |]
  else
    let a = Array.make n 0 in
    a.(0) <- 1;
    a.(1) <- 1;
    for i = 2 to n - 1 do
      let term_num = i + 1 in
      let prev = a.(i - 1) in
      let left_idx = prev - 1 in
      let right_idx = term_num - prev - 1 in
      let left = if left_idx >= 0 && left_idx < i then a.(left_idx) else 1 in
      let right = if right_idx >= 0 && right_idx < i then a.(right_idx) else 1 in
      a.(i) <- left + right
    done;
    a

let a004001_table : int array = precompute_a004001 256

let dispatch_tier ~(depth : int) ~(step : int) : int =
  if depth <= 1 then 0
  else
    let idx = (Stdlib.abs step) mod 256 in
    a004001_table.(idx) mod depth

(** {1 OEIS A005228 / A030124: Hofstadter Figure-Figure Partition} *)

let figure_figure_lists (n : int) : int list * int list =
  if n <= 0 then ([], [])
  else
    let r_arr = Array.make n 0 in
    let s_arr = Array.make n 0 in
    let used = Hashtbl.create (n * 4) in
    r_arr.(0) <- 1;
    s_arr.(0) <- 2;
    Hashtbl.replace used 1 true;
    Hashtbl.replace used 2 true;
    let next_s = ref 3 in
    for k = 1 to n - 1 do
      let r_val = r_arr.(k - 1) + s_arr.(k - 1) in
      r_arr.(k) <- r_val;
      Hashtbl.replace used r_val true;
      while Hashtbl.mem used !next_s do
        incr next_s
      done;
      let s_val = !next_s in
      s_arr.(k) <- s_val;
      Hashtbl.replace used s_val true;
      incr next_s
    done;
    (Array.to_list r_arr, Array.to_list s_arr)

let precomputed_r_set : (int, bool) Hashtbl.t =
  let r_list, _ = figure_figure_lists 256 in
  let tbl = Hashtbl.create 256 in
  List.iter (fun x -> Hashtbl.replace tbl x true) r_list;
  tbl

let is_tier_slot (slot_idx : int) : bool =
  let positive_idx = (Stdlib.abs slot_idx) + 1 in
  Hashtbl.mem precomputed_r_set positive_idx

(** {1 OEIS A061775: Matula-Goebel Topology Digest} *)

type topology =
  | Leaf of int
  | Branch of int * topology list

(* Sieve first 1000 primes *)
let primes_table : int array =
  let max_prime_count = 1000 in
  let primes = Array.make max_prime_count 0 in
  let count = ref 0 in
  let candidate = ref 2 in
  let is_prime n =
    let rec check d =
      if d * d > n then true
      else if n mod d = 0 then false
      else check (d + 1)
    in
    check 2
  in
  while !count < max_prime_count do
    if is_prime !candidate then begin
      primes.(!count) <- !candidate;
      incr count
    end;
    incr candidate
  done;
  primes

let nth_prime (n : int) : int =
  if n <= 0 then 2
  else if n <= Array.length primes_table then primes_table.(n - 1)
  else
    primes_table.(Array.length primes_table - 1)

let rec matula_number = function
  | Leaf _ -> 1
  | Branch (_, children) ->
      if children = [] then 1
      else
        List.fold_left
          (fun acc child ->
            let m = matula_number child in
            let p = nth_prime m in
            acc * p)
          1 children

let topology_digest ?(salt = Random_visa_constants.Magic_numbers.nested_topology_salt)
    (t : topology) : int64 =
  let m = matula_number t in
  let z = logxor (of_int m) (mul salt Random_visa_constants.Magic_numbers.splitmix64_gamma) in
  let z = mul (logxor z (shift_right_logical z 30)) Random_visa_constants.Magic_numbers.splitmix64_mix in
  let z = mul (logxor z (shift_right_logical z 27)) 0x94D049BB133111EBL in
  logxor z (shift_right_logical z 31)

let rec chain_topology ~(depth : int) : topology =
  if depth <= 1 then Leaf 0
  else Branch (depth - 1, [ chain_topology ~depth:(depth - 1) ])

(** {1 OEIS A287654 / A249569: Meta-Fibonacci Handoff Jitter} *)

let handoff_jitter ~(seed : int64) ~(step : int) : int =
  let n = (Stdlib.abs step mod 128) + 3 in
  let rec a = function
    | 1 | 2 -> 1
    | k ->
        let prev1 = a (k - 1) in
        let prev2 = a (k - 2) in
        if prev1 < k && prev2 < k then
          a (k - prev1) + a (k - prev2)
        else
          ((prev1 + prev2) mod k) + 1
  in
  let raw = a (Stdlib.min n 16) in
  let mixed = logxor (of_int raw) seed in
  to_int (logand mixed 0x0FL)

(** {1 Configuration} *)

type nested_config = {
  enabled : bool;
  max_depth : int;
  salt : int64;
}

let default_nested_config = {
  enabled = false;
  max_depth = 4;
  salt = Random_visa_constants.Magic_numbers.nested_topology_salt;
}
