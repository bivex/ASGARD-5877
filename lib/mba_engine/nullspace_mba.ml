(* Nullspace MBA noise via constructive kernel synthesis.

   For the 16-element boolean basis over (x, y), every function f satisfies
   the pointwise minterm decomposition f = SUM_i f_i * m_i (f_i in {0,1}
   are the truth-table bits, m_i the four pairwise-orthogonal minterm
   masks).  Hence each relation vector

     v_f = e_f - SUM_i f_i * e_{m_i}

   lies in the kernel of the truth-table matrix M over Z_{2^64}
   (M c = 0 for every input).  The synthesizer does NOT solve a linear
   system for ker(M); instead it constructs kernel vectors directly from
   the minterm decomposition and combines k of them with independent
   random odd scales lambda_k:

     noise = SUM_k lambda_k * v_{f_k}   in ker(M)  (kernel closed under
   linear combinations), so the noise evaluates to 0 for ALL inputs.

   Verification re-checks the four corner patterns (00/01/10/11 in every
   bit position simultaneously), which is exhaustive for bitwise-parallel
   identities.                                                     *)
open Vm_ir
open Int64

type minterm_term = {
  bfunc_id : int;
  coeff    : int64;
}

let eval_bfunc (id : int) (x : int64) (y : int64) : int64 =
  match id with
  | 0  -> 0L
  | 1  -> lognot (logor x y)               (* nor / minterm e4 *)
  | 2  -> logand (lognot x) y              (* andnot_x / minterm e3 *)
  | 3  -> lognot x
  | 4  -> logand x (lognot y)              (* andnot_y / minterm e2 *)
  | 5  -> lognot y
  | 6  -> logxor x y
  | 7  -> lognot (logand x y)               (* nand *)
  | 8  -> logand x y                       (* and / minterm e1 *)
  | 9  -> lognot (logxor x y)              (* xnor *)
  | 10 -> y
  | 11 -> logor (lognot x) y
  | 12 -> x
  | 13 -> logor x (lognot y)
  | 14 -> logor x y
  | 15 -> -1L
  | _  -> 0L

let emit_bfunc (id : int) (dst : Register.t) (x : Register.t) (y : Register.t) : Ir.instr list =
  match id with
  | 0  -> [ Ir.Mov { dst = Reg dst; src = Imm 0L } ]
  | 1  -> [
      Ir.Alu { op = Or; dst; src1 = Reg x; src2 = Reg y; set_flags = false };
      Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
    ]
  | 2  -> [
      Ir.Mov { dst = Reg dst; src = Reg x };
      Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
      Ir.Alu { op = And; dst; src1 = Reg dst; src2 = Reg y; set_flags = false };
    ]
  | 3  -> [ Ir.Unary { op = Not; dst; src = Reg x; set_flags = false } ]
  | 4  -> [
      Ir.Mov { dst = Reg dst; src = Reg y };
      Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
      Ir.Alu { op = And; dst; src1 = Reg x; src2 = Reg dst; set_flags = false };
    ]
  | 5  -> [ Ir.Unary { op = Not; dst; src = Reg y; set_flags = false } ]
  | 6  -> [ Ir.Alu { op = Xor; dst; src1 = Reg x; src2 = Reg y; set_flags = false } ]
  | 7  -> [
      Ir.Alu { op = And; dst; src1 = Reg x; src2 = Reg y; set_flags = false };
      Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
    ]
  | 8  -> [ Ir.Alu { op = And; dst; src1 = Reg x; src2 = Reg y; set_flags = false } ]
  | 9  -> [
      Ir.Alu { op = Xor; dst; src1 = Reg x; src2 = Reg y; set_flags = false };
      Ir.Unary { op = Not; dst; src = Reg dst; set_flags = false };
    ]
  | 10 -> [ Ir.Mov { dst = Reg dst; src = Reg y } ]
  | 11 -> [
      Ir.Unary { op = Not; dst; src = Reg x; set_flags = false };
      Ir.Alu { op = Or; dst; src1 = Reg dst; src2 = Reg y; set_flags = false };
    ]
  | 12 -> [ Ir.Mov { dst = Reg dst; src = Reg x } ]
  | 13 -> [
      Ir.Unary { op = Not; dst; src = Reg y; set_flags = false };
      Ir.Alu { op = Or; dst; src1 = Reg x; src2 = Reg dst; set_flags = false };
    ]
  | 14 -> [ Ir.Alu { op = Or; dst; src1 = Reg x; src2 = Reg y; set_flags = false } ]
  | 15 -> [ Ir.Mov { dst = Reg dst; src = Imm (-1L) } ]
  | _  -> []

let synth_minterm_zero ~(rng : Random.State.t) ~(terms_count : int) : minterm_term list =
  let coeff_map = Array.make 16 0L in
  let add_coeff id c =
    coeff_map.(id) <- add coeff_map.(id) c
  in
  let count = Stdlib.max 1 (Stdlib.min terms_count 8) in
  for _ = 1 to count do
    (* Relation pool: bfunc ids 2..15.  id 15 (constant -1) yields the
       5-term relation e15 - m1 - m2 - m4 - m8 (since m1+m2+m4+m8 = ~0).
       ids 0 (constant 0) and 1 (m1 itself) are trivial and excluded. *)
    let code = 2 + Random.State.int rng 14 in
    let lambda = logor (Random.State.int64 rng max_int) 1L in
    let v00 = code land 1 in
    let v01 = (code lsr 1) land 1 in
    let v10 = (code lsr 2) land 1 in
    let v11 = (code lsr 3) land 1 in
    add_coeff code lambda;
    if v11 <> 0 then add_coeff 8 (neg lambda);
    if v10 <> 0 then add_coeff 4 (neg lambda);
    if v01 <> 0 then add_coeff 2 (neg lambda);
    if v00 <> 0 then add_coeff 1 (neg lambda);
  done;
  let terms = ref [] in
  for id = 0 to 15 do
    if coeff_map.(id) <> 0L then
      terms := { bfunc_id = id; coeff = coeff_map.(id) } :: !terms
  done;
  !terms

let eval_terms ~(terms : minterm_term list) ~(x : int64) ~(y : int64) : int64 =
  List.fold_left (fun acc t ->
    let fv = eval_bfunc t.bfunc_id x y in
    add acc (mul t.coeff fv)
  ) 0L terms

let verify_minterm_zero (terms : minterm_term list) : bool =
  let check x y =
    eval_terms ~terms ~x ~y = 0L
  in
  check 0L 0L && check 0L (-1L) && check (-1L) 0L && check (-1L) (-1L)

let obfuscate_alu ~rng ~dst ~src1 ~src2 op =
  let base_instr = Ir.Alu { op; dst; src1; src2; set_flags = false } in
  let terms = synth_minterm_zero ~rng ~terms_count:4 in
  if terms = [] || not (verify_minterm_zero terms) then
    [ base_instr ]
  else
    let x_reg = match src1 with Ir.Reg r -> r | _ -> Register.vtmp2 in
    let y_reg = match src2 with Ir.Reg r -> r | _ -> Register.vtmp3 in
    let setup1 = match src1 with
      | Ir.Imm c -> [ Ir.Mov { dst = Reg x_reg; src = Imm c } ]
      | _ -> []
    in
    let setup2 = match src2 with
      | Ir.Imm c -> [ Ir.Mov { dst = Reg y_reg; src = Imm c } ]
      | _ -> []
    in
    let scratch0 = Register.vtmp0 in
    let scratch1 = Register.vtmp1 in
    let noise_instrs = ref [] in
    let first = ref true in
    List.iter (fun t ->
      let instrs = emit_bfunc t.bfunc_id scratch0 x_reg y_reg in
      let scaled = instrs @ [
        Ir.Alu { op = Mul; dst = scratch0; src1 = Reg scratch0; src2 = Imm t.coeff; set_flags = false }
      ] in
      if !first then begin
        noise_instrs := !noise_instrs @ scaled @ [
          Ir.Mov { dst = Reg scratch1; src = Reg scratch0 }
        ];
        first := false
      end else begin
        noise_instrs := !noise_instrs @ scaled @ [
          Ir.Alu { op = Add; dst = scratch1; src1 = Reg scratch1; src2 = Reg scratch0; set_flags = false }
        ]
      end
    ) terms;
    (* Non-linear modulation: multiply the zero sum in scratch1 by a strictly odd
       quadratic polynomial ((x ^ y)^2 | 1). Since scratch1 == 0 mod 2^64,
       0 * M(x, y) = 0 identically for all 64-bit inputs.
       This creates cubic cross-terms and full 64-bit carry propagation, defeating
       1-bit linear matrix solvers (SiMBA / CoBRA / GAMBA). *)
    let nl_modulator = [
      Ir.Alu { op = Xor; dst = scratch0; src1 = Reg x_reg; src2 = Reg y_reg; set_flags = false };
      Ir.Alu { op = Mul; dst = scratch0; src1 = Reg scratch0; src2 = Reg scratch0; set_flags = false };
      Ir.Alu { op = Or;  dst = scratch0; src1 = Reg scratch0; src2 = Imm 1L; set_flags = false };
      Ir.Alu { op = Mul; dst = scratch1; src1 = Reg scratch1; src2 = Reg scratch0; set_flags = false };
    ] in
    let add_to_dst = [
      Ir.Alu { op = Add; dst; src1 = Reg dst; src2 = Reg scratch1; set_flags = false }
    ] in
    setup1 @ setup2 @ [ base_instr ] @ !noise_instrs @ nl_modulator @ add_to_dst
