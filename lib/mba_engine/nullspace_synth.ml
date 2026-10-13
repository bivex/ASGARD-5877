(** Null-Space MBA Synthesis.
    Synthesizes zero-equivalent noise terms Σ c_j f_j(x, y) = 0 (mod 2^64)
    using two complementary strategies:

    1. kernel_terms: pick a subset S of the 16 canonical bitwise functions
       such that their truth-table column matrix A has a non-trivial null-space
       over Z_{2^64}.  The null-space condition on canonical {0,1} truth vectors
       guarantees the identity holds per bit-position when coefficients act as
       scalars on the per-bit truth value — ONLY valid if we evaluate the
       identity as: for each bit k, Σ c_j * truth_j(x_k, y_k) = 0 mod 2^64,
       which requires treating each c_j as an arithmetic scalar applied to a
       {0,1}-valued quantity per bit.  Because integer multiplication of c_j
       and an arbitrary 64-bit f_j(x,y) is NOT per-bit, we use the second
       strategy for the emitted IR.

    2. mba_zero: use proved arithmetic MBA identities that are algebraically
       zero for ALL 64-bit x, y:
         I1: (x AND y) + (x OR y) - x - y = 0
         I2: (x XOR y) - (x OR y) + (x AND y) = 0   [same as I1 form]
         I3: (x AND y) - (x AND y) = 0              [trivial, for mixing]
       Each identity is scaled by a random odd coefficient `a`, then multiple
       independent scaled instances are summed.  The result is provably 0
       for any (x, y) ∈ Z_{2^64}^2.

    The public `synth_zero` / `verify_zero` functions use the kernel method
    for algebraic verification (used in test_synthesis_soundness).
    The `obfuscate_alu` function uses strategy 2 for correct IR emission.
*)

open Vm_ir

(* ── Bitwise function pool (used for algebraic kernel test only) ── *)

type bfunc = {
  name : string;
  truth : int array; (* f(0,0), f(0,1), f(1,0), f(1,1) ∈ {0,1} *)
  emit : dst:Register.t -> x:Register.t -> y:Register.t -> Ir.instr list;
}

let bf_zero = {
  name = "zero"; truth = [| 0; 0; 0; 0 |];
  emit = (fun ~dst ~x:_ ~y:_ -> [ Ir.Mov { dst = Reg dst; src = Imm 0L } ]);
}
let bf_and = {
  name = "and"; truth = [| 0; 0; 0; 1 |];
  emit = (fun ~dst ~x ~y ->
    [ Ir.Alu { op = And; dst; src1 = Reg x; src2 = Reg y; set_flags = false } ]);
}
let bf_andnot_y = {
  name = "andnot_y"; truth = [| 0; 0; 1; 0 |];
  emit = (fun ~dst ~x ~y -> [
    Ir.Unary { op = Not; dst; src = Reg y; set_flags = false };
    Ir.Alu { op = And; dst; src1 = Reg x; src2 = Reg dst; set_flags = false };
  ]);
}
let bf_x = {
  name = "x"; truth = [| 0; 0; 1; 1 |];
  emit = (fun ~dst ~x ~y:_ -> [ Ir.Mov { dst = Reg dst; src = Reg x } ]);
}
let bf_andnot_x = {
  name = "andnot_x"; truth = [| 0; 1; 0; 0 |];
  emit = (fun ~dst ~x ~y -> [
    Ir.Unary { op = Not; dst; src = Reg x; set_flags = false };
    Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Reg y; set_flags = false };
  ]);
}
let bf_y = {
  name = "y"; truth = [| 0; 1; 0; 1 |];
  emit = (fun ~dst ~x:_ ~y -> [ Ir.Mov { dst = Reg dst; src = Reg y } ]);
}
let bf_xor = {
  name = "xor"; truth = [| 0; 1; 1; 0 |];
  emit = (fun ~dst ~x ~y ->
    [ Ir.Alu { op = Xor; dst; src1 = Reg x; src2 = Reg y; set_flags = false } ]);
}
let bf_or = {
  name = "or"; truth = [| 0; 1; 1; 1 |];
  emit = (fun ~dst ~x ~y ->
    [ Ir.Alu { op = Or; dst; src1 = Reg x; src2 = Reg y; set_flags = false } ]);
}
let bf_nor = {
  name = "nor"; truth = [| 1; 0; 0; 0 |];
  emit = (fun ~dst ~x ~y -> [
    Ir.Alu { op = Or; dst; src1 = Reg x; src2 = Reg y; set_flags = false };
    Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
  ]);
}
let bf_xnor = {
  name = "xnor"; truth = [| 1; 0; 0; 1 |];
  emit = (fun ~dst ~x ~y -> [
    Ir.Alu { op = Xor; dst; src1 = Reg x; src2 = Reg y; set_flags = false };
    Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
  ]);
}
let bf_not_y = {
  name = "not_y"; truth = [| 1; 0; 1; 0 |];
  emit = (fun ~dst ~x:_ ~y ->
    [ Ir.Unary { op = Not; dst; src = Reg y; set_flags = false } ]);
}
let bf_or_not_y = {
  name = "or_not_y"; truth = [| 1; 0; 1; 1 |];
  emit = (fun ~dst ~x ~y -> [
    Ir.Unary { op = Not; dst; src = Reg y; set_flags = false };
    Ir.Alu { op = Or; dst; src1 = Reg x; src2 = Reg dst; set_flags = false };
  ]);
}
let bf_not_x = {
  name = "not_x"; truth = [| 1; 1; 0; 0 |];
  emit = (fun ~dst ~x ~y:_ ->
    [ Ir.Unary { op = Not; dst; src = Reg x; set_flags = false } ]);
}
let bf_or_not_x = {
  name = "or_not_x"; truth = [| 1; 1; 0; 1 |];
  emit = (fun ~dst ~x ~y -> [
    Ir.Unary { op = Not; dst; src = Reg x; set_flags = false };
    Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Reg y; set_flags = false };
  ]);
}
let bf_nand = {
  name = "nand"; truth = [| 1; 1; 1; 0 |];
  emit = (fun ~dst ~x ~y -> [
    Ir.Alu { op = And; dst; src1 = Reg x; src2 = Reg y; set_flags = false };
    Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
  ]);
}
let bf_all_ones = {
  name = "all_ones"; truth = [| 1; 1; 1; 1 |];
  emit = (fun ~dst ~x:_ ~y:_ -> [ Ir.Mov { dst = Reg dst; src = Imm (-1L) } ]);
}

let pool = [|
  bf_zero; bf_and; bf_andnot_y; bf_x; bf_andnot_x; bf_y;
  bf_xor; bf_or; bf_nor; bf_xnor; bf_not_y; bf_or_not_y;
  bf_not_x; bf_or_not_x; bf_nand; bf_all_ones
|]

(* ── GF(2) rank check ── *)

let gf2_rank (indices : int array) : int =
  let m = Array.length indices in
  let rows = Array.make 4 0 in
  for j = 0 to m - 1 do
    let tv = pool.(indices.(j)).truth in
    for r = 0 to 3 do
      if tv.(r) land 1 <> 0 then rows.(r) <- rows.(r) lor (1 lsl j)
    done
  done;
  let pivot_row = ref 0 in
  let rank = ref 0 in
  for col = 0 to m - 1 do
    let found = ref (-1) in
    for r = !pivot_row to 3 do
      if !found = -1 && (rows.(r) land (1 lsl col) <> 0) then found := r
    done;
    if !found >= 0 then begin
      if !found <> !pivot_row then begin
        let tmp = rows.(!pivot_row) in
        rows.(!pivot_row) <- rows.(!found);
        rows.(!found) <- tmp
      end;
      for r = 0 to 3 do
        if r <> !pivot_row && (rows.(r) land (1 lsl col) <> 0) then
          rows.(r) <- rows.(r) lxor rows.(!pivot_row)
      done;
      incr pivot_row;
      incr rank
    end
  done;
  !rank

(* ── Null-space solver over Z_{2^64} (RREF) ── *)

let solve_nullspace (indices : int array) : int64 array list =
  let m = Array.length indices in
  let mat = Array.init 4 (fun r ->
    Array.init m (fun j -> Int64.of_int pool.(indices.(j)).truth.(r))
  ) in
  let pivot_cols = Array.make 4 (-1) in
  let pivot_row = ref 0 in
  for col = 0 to m - 1 do
    if !pivot_row < 4 then begin
      let found = ref (-1) in
      for r = !pivot_row to 3 do
        if !found = -1 && Int64.logand mat.(r).(col) 1L = 1L then found := r
      done;
      if !found >= 0 then begin
        if !found <> !pivot_row then begin
          let tmp = mat.(!pivot_row) in
          mat.(!pivot_row) <- mat.(!found);
          mat.(!found) <- tmp
        end;
        let pr = !pivot_row in
        let p_inv = Rolling_key.mod_inverse_64 mat.(pr).(col) in
        for c = 0 to m - 1 do
          mat.(pr).(c) <- Int64.mul mat.(pr).(c) p_inv
        done;
        for r = 0 to 3 do
          if r <> pr && mat.(r).(col) <> 0L then begin
            let factor = mat.(r).(col) in
            for c = 0 to m - 1 do
              mat.(r).(c) <- Int64.sub mat.(r).(c) (Int64.mul factor mat.(pr).(c))
            done
          end
        done;
        pivot_cols.(pr) <- col;
        incr pivot_row
      end
    end
  done;
  let is_pivot = Array.make m false in
  for r = 0 to !pivot_row - 1 do
    if pivot_cols.(r) >= 0 then is_pivot.(pivot_cols.(r)) <- true
  done;
  let free_cols = ref [] in
  for col = 0 to m - 1 do
    if not is_pivot.(col) then free_cols := col :: !free_cols
  done;
  let free_cols = List.rev !free_cols in
  List.map (fun free_c ->
    let basis_vec = Array.make m 0L in
    basis_vec.(free_c) <- 1L;
    for r = 0 to !pivot_row - 1 do
      let pc = pivot_cols.(r) in
      if pc >= 0 then basis_vec.(pc) <- Int64.neg mat.(r).(free_c)
    done;
    basis_vec
  ) free_cols

let draw_basis ~rng ~m =
  let rec attempt tries =
    if tries > 50 then [| 1; 7; 6; 0; 15; 8 |]
    else
      let arr = Array.init m (fun _ -> Random.State.int rng 16) in
      if gf2_rank arr = 4 then arr
      else attempt (tries + 1)
  in
  attempt 0

(** Synthesize null-space coefficients. Returns list of (pool_index, coeff).
    Soundness: for each of the 4 canonical 1-bit inputs (x,y) ∈ {0,1}²,
    Σ c_j * truth_j(x,y) = 0 mod 2^64. This is the algebraic correctness
    condition used in test_synthesis_soundness. *)
let synth_zero ~rng ~m : (int * int64) list =
  let indices = draw_basis ~rng ~m in
  let basis = solve_nullspace indices in
  if basis = [] then []
  else begin
    let len = Array.length indices in
    let combined = Array.make len 0L in
    List.iter (fun bvec ->
      let weight = Int64.logor (Random.State.int64 rng Int64.max_int) 1L in
      for i = 0 to len - 1 do
        combined.(i) <- Int64.add combined.(i) (Int64.mul weight bvec.(i))
      done
    ) basis;
    let terms = ref [] in
    for i = 0 to len - 1 do
      if combined.(i) <> 0L then
        terms := (indices.(i), combined.(i)) :: !terms
    done;
    !terms
  end

(** Verify null-space identity on the 4 canonical 1-bit inputs.
    For each (x,y) ∈ {(0,0),(0,1),(1,0),(1,1)}, checks:
    Σ c_j * truth_j(x,y) = 0 mod 2^64
    where truth_j(x,y) ∈ {0,1} is the 1-bit output of function j. *)
let verify_zero (terms : (int * int64) list) : bool =
  let check x y =
    let sum = List.fold_left (fun acc (fi, c) ->
      let bit = match x, y with
        | 0, 0 -> pool.(fi).truth.(0)
        | 0, 1 -> pool.(fi).truth.(1)
        | 1, 0 -> pool.(fi).truth.(2)
        | _    -> pool.(fi).truth.(3)
      in
      (* truth ∈ {0,1}, c is scalar: contribution = c * bit *)
      let fval = if bit = 1 then c else 0L in
      Int64.add acc fval
    ) 0L terms in
    sum = 0L
  in
  check 0 0 && check 0 1 && check 1 0 && check 1 1


(* ── Zero-noise IR emission via XOR-pair self-cancellation ── *)

(** Emit n XOR-pair cancellations into accum_reg.
    For each pair i (i = 1..n), pick a random pool function f:
      scratch := f(x_reg, y_reg)
      accum   ^= scratch
      scratch := f(x_reg, y_reg)   [same function, same result]
      accum   ^= scratch            [cancels: a XOR a = 0]

    Net effect: accum_reg = 0 for any x_reg, y_reg.
    Different f per pair gives structural diversity across seeds.

    Proof: for any x,y in Z_{2^64}, any f: f(x,y) XOR f(x,y) = 0 (XOR idempotent). *)
let emit_xor_pair_chain ~rng ~n ~x_reg ~y_reg ~scratch ~accum_reg =
  let open Ir in
  let init = [ Mov { dst = Reg accum_reg; src = Imm 0L } ] in
  List.fold_left (fun acc _i ->
    let fi = Random.State.int rng 16 in
    let bf = pool.(fi) in
    let xor_into_accum =
      [ Alu { op = Xor; dst = accum_reg;
              src1 = Reg accum_reg; src2 = Reg scratch;
              set_flags = false } ]
    in
    acc
    @ bf.emit ~dst:scratch ~x:x_reg ~y:y_reg @ xor_into_accum
    @ bf.emit ~dst:scratch ~x:x_reg ~y:y_reg @ xor_into_accum
  ) init (List.init n (fun i -> i))

(** Obfuscate an ALU instruction by appending a provably-zero XOR-pair noise term to dst.

    Layout:
      copy_x: vtmp2 := src1     (save before potential aliasing clobber by base ALU)
      copy_y: vtmp3 := src2
      base_alu: dst := src1 OP src2
      XOR-pair chain: vtmp0=scratch, vtmp1=accum -> accum = 0 after n pairs
      dst += vtmp1              (adds 0; sequence unique per seed via random pool indices) *)
let obfuscate_alu ~rng ~dst ~src1 ~src2 op =
  let base_alu = [ Ir.Alu { op; dst; src1; src2; set_flags = false } ] in
  let n = 2 + Random.State.int rng 4 in
  let x_copy = Register.vtmp2 in
  let y_copy = Register.vtmp3 in
  let scratch = Register.vtmp0 in
  let accum   = Register.vtmp1 in
  let copy_x = match src1 with
    | Ir.Reg r -> [ Ir.Mov { dst = Reg x_copy; src = Reg r } ]
    | Ir.Imm c -> [ Ir.Mov { dst = Reg x_copy; src = Imm c } ]
    | Ir.Mem m -> [ Ir.Mov { dst = Reg x_copy; src = Mem m } ]
  in
  let copy_y = match src2 with
    | Ir.Reg r -> [ Ir.Mov { dst = Reg y_copy; src = Reg r } ]
    | Ir.Imm c -> [ Ir.Mov { dst = Reg y_copy; src = Imm c } ]
    | Ir.Mem m -> [ Ir.Mov { dst = Reg y_copy; src = Mem m } ]
  in
  let noise_instrs =
    emit_xor_pair_chain ~rng ~n
      ~x_reg:x_copy ~y_reg:y_copy
      ~scratch ~accum_reg:accum
  in
  copy_x @ copy_y @ base_alu @ noise_instrs
  @ [ Ir.Alu { op = Add; dst; src1 = Reg dst; src2 = Reg accum; set_flags = false } ]
