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
    let code = 2 + Random.State.int rng 13 in
    let r = logor (Random.State.int64 rng max_int) 1L in
    let v00 = code land 1 in
    let v01 = (code lsr 1) land 1 in
    let v10 = (code lsr 2) land 1 in
    let v11 = (code lsr 3) land 1 in
    add_coeff code r;
    if v11 <> 0 then add_coeff 8 (neg r);
    if v10 <> 0 then add_coeff 4 (neg r);
    if v01 <> 0 then add_coeff 2 (neg r);
    if v00 <> 0 then add_coeff 1 (neg r);
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
  let terms = synth_minterm_zero ~rng ~terms_count:3 in
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
    let add_to_dst = [
      Ir.Alu { op = Add; dst; src1 = Reg dst; src2 = Reg scratch1; set_flags = false }
    ] in
    setup1 @ setup2 @ [ base_instr ] @ !noise_instrs @ add_to_dst
