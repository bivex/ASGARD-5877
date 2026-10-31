(* Cross-backend integer sequence generators (OEIS catalogue, see
   docs/OEIS_MATHEMATICAL_SEQUENCES.md).  Pure functions shared by the JIT
   arena (backends/jit_vm) and the stack chunker (backends/stack_vm); both
   backends must draw chunk boundaries from the same generators so that
   traces stay comparable. *)

(** OEIS A000002 - Kolakoski self-describing word 1,2,2,1,1,2,1,2,2,1,...
    whose run lengths equal the word itself. *)
let kolakoski (n : int) : int array =
  if n <= 0 then [||]
  else if n = 1 then [| 1 |]
  else
    let buf = Array.make (Stdlib.max n 16) 0 in
    buf.(0) <- 1;
    buf.(1) <- 2;
    buf.(2) <- 2;
    let r = ref 2 in
    let i = ref 3 in
    while !i < n do
      let v = if !r mod 2 = 0 then 1 else 2 in
      let len = buf.(!r) in
      for _ = 1 to len do
        if !i < n then begin
          buf.(!i) <- v;
          incr i
        end
      done;
      incr r
    done;
    Array.sub buf 0 n

(** Scale applied to Kolakoski run lengths to obtain chunk fission sizes. *)
let kolakoski_scale = 2

(** OEIS A010060 - Thue-Morse: t_n = popcount(n) mod 2. *)
let thue_morse (n : int) : bool =
  let rec bits x acc =
    if x = 0 then acc
    else bits (x land (x - 1)) (acc lxor 1)  (* clear the lowest set bit *)
  in
  bits n 0 = 1
