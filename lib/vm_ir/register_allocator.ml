open Ir
open Register

type strategy =
  | LinearScan
  | Randomized
  | PressureAware

let strategy_to_string = function
  | LinearScan -> "LinearScan"
  | Randomized -> "Randomized"
  | PressureAware -> "PressureAware"

let build_register_map (strategy : strategy) (seed : Seed.t) =
  let map = Hashtbl.create 16 in
  let rng = Seed.make_rng seed.register_seed in
  match strategy with
  | LinearScan ->
      for i = 0 to 15 do
        Hashtbl.replace map i i
      done;
      map
  | Randomized ->
      let scratch = Array.init 8 (fun i -> i + 8) in
      for i = 7 downto 1 do
        let j = Random.State.int rng (i + 1) in
        let tmp = scratch.(i) in
        scratch.(i) <- scratch.(j);
        scratch.(j) <- tmp
      done;
      for i = 0 to 7 do
        Hashtbl.replace map i i;
        Hashtbl.replace map (i + 8) scratch.(i)
      done;
      map
  | PressureAware ->
      for i = 0 to 15 do
        Hashtbl.replace map i (i mod 8)
      done;
      map

let remap_register (map : (int, int) Hashtbl.t) (r : Register.t) : Register.t =
  match r with
  | Gpr (g, w) ->
      let idx = Register.gpr_index g in
      (match Hashtbl.find_opt map idx with
      | Some new_idx ->
          (match Register.gpr_of_index new_idx with
          | Ok new_g -> Gpr (new_g, w)
          | Error _ -> r)
      | None -> r)
  | Vreg _ -> r

let remap_operand (map : (int, int) Hashtbl.t) = function
  | Reg r -> Reg (remap_register map r)
  | Mem m ->
      let new_base = Option.map (remap_register map) m.base in
      let new_index = Option.map (fun (r, sc) -> (remap_register map r, sc)) m.index in
      Mem { m with base = new_base; index = new_index }
  | Imm _ as imm -> imm

let remap_instr (map : (int, int) Hashtbl.t) (instr : instr) : instr =
  match instr with
  | Mov { dst; src } -> Mov { dst = remap_operand map dst; src = remap_operand map src }
  | Lea { dst; addr } ->
      let new_base = Option.map (remap_register map) addr.base in
      let new_index = Option.map (fun (r, sc) -> (remap_register map r, sc)) addr.index in
      Lea { dst = remap_register map dst; addr = { addr with base = new_base; index = new_index } }
  | Push op -> Push (remap_operand map op)
  | Pop op -> Pop (remap_operand map op)
  | Xchg (a, b) -> Xchg (remap_operand map a, remap_operand map b)
  | Alu { op; dst; src1; src2; set_flags } ->
      Alu { op; dst = remap_register map dst; src1 = remap_operand map src1; src2 = remap_operand map src2; set_flags }
  | Unary { op; dst; src; set_flags } ->
      Unary { op; dst = remap_register map dst; src = remap_operand map src; set_flags }
  | Cmp { src1; src2 } -> Cmp { src1 = remap_operand map src1; src2 = remap_operand map src2 }
  | Test { src1; src2 } -> Test { src1 = remap_operand map src1; src2 = remap_operand map src2 }
  | Setcc { cond; dst } -> Setcc { cond; dst = remap_operand map dst }
  | Cmov { cond; dst; src } -> Cmov { cond; dst = remap_register map dst; src = remap_operand map src }
  | Jmp _ | Jcc _ | Call _ | Ret | Vm_enter | Vm_exit | Trap _ | Nop -> instr

let allocate ~(strategy : strategy) ~(seed : Seed.t) (f : func) : func =
  let reg_map = build_register_map strategy seed in
  let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
  Hashtbl.iter (fun id b ->
    let new_instrs = List.map (remap_instr reg_map) b.instrs in
    Hashtbl.replace new_blocks id { b with instrs = new_instrs }
  ) f.cfg.blocks;
  { f with cfg = { f.cfg with blocks = new_blocks } }
