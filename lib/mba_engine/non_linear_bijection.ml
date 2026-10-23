open Vm_ir

type involution_params = {
  c : int64;
  c_inv : int64;
  shift : int;
}

let mod_inverse_64 c =
  (* Newton-Raphson inversion over Z_{2^64}: x_{k+1} = x_k * (2 - c * x_k) *)
  let two = 2L in
  let rec loop x steps =
    if steps >= 6 then x
    else
      let cx = Int64.mul c x in
      let term = Int64.sub two cx in
      let next_x = Int64.mul x term in
      loop next_x (steps + 1)
  in
  loop c 0

let make_params ?(shift = 33) c =
  let odd_c = Int64.logor c 1L in
  let c_inv = mod_inverse_64 odd_c in
  { c = odd_c; c_inv; shift }

let random_params ?(shift = 33) rng =
  let r = Random.State.int64 rng Int64.max_int in
  make_params ~shift r

let forward params x =
  let xc = Int64.mul x params.c in
  let shifted = Int64.shift_right_logical xc params.shift in
  Int64.logxor xc shifted

let inverse params y =
  let shifted = Int64.shift_right_logical y params.shift in
  let gy = Int64.logxor y shifted in
  Int64.mul gy params.c_inv

let emit_forward_ir ~params ~dst ~src =
  let tmp = Register.vtmp0 in
  [
    Ir.Mov { dst = Reg tmp; src = Reg src };
    Ir.Alu { op = Mul; dst = tmp; src1 = Reg tmp; src2 = Imm params.c; set_flags = false };
    Ir.Mov { dst = Reg dst; src = Reg tmp };
    Ir.Alu { op = Shr; dst = dst; src1 = Reg dst; src2 = Imm (Int64.of_int params.shift); set_flags = false };
    Ir.Alu { op = Xor; dst = dst; src1 = Reg dst; src2 = Reg tmp; set_flags = false };
  ]

let emit_inverse_ir ~params ~dst ~src =
  let tmp = Register.vtmp0 in
  [
    Ir.Mov { dst = Reg tmp; src = Reg src };
    Ir.Alu { op = Shr; dst = tmp; src1 = Reg tmp; src2 = Imm (Int64.of_int params.shift); set_flags = false };
    Ir.Alu { op = Xor; dst = tmp; src1 = Reg tmp; src2 = Reg src; set_flags = false };
    Ir.Alu { op = Mul; dst = dst; src1 = Reg tmp; src2 = Imm params.c_inv; set_flags = false };
  ]

let synth_xorshift_involution ~rng ~dst =
  let params = random_params ~shift:33 rng in
  let f_ir = emit_forward_ir ~params ~dst ~src:dst in
  let inv_ir = emit_inverse_ir ~params ~dst ~src:dst in
  f_ir @ inv_ir

let synth_nested_involution ~rng ~dst =
  (* 2-stage nested non-linear involution: f1_fwd @ f2_fwd @ f2_inv @ f1_inv.
     Separates the outer f1 forward and inverse with an independent inner
     non-linear transformation, defeating windowed peephole cancelers. *)
  let p1 = random_params ~shift:33 rng in
  let p2 = random_params ~shift:33 rng in
  let f1 = emit_forward_ir ~params:p1 ~dst ~src:dst in
  let f2 = emit_forward_ir ~params:p2 ~dst ~src:dst in
  let inv2 = emit_inverse_ir ~params:p2 ~dst ~src:dst in
  let inv1 = emit_inverse_ir ~params:p1 ~dst ~src:dst in
  f1 @ f2 @ inv2 @ inv1

let wrap_non_algebraic_mba ~rng ~dst body_instrs =
  body_instrs @ (synth_nested_involution ~rng ~dst)
