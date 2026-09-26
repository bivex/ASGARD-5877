open Vm_ir

type t = {
  reg_to_slot : (Register.t, int) Hashtbl.t;
  slot_to_reg : (int, Register.t) Hashtbl.t;
  mutable next_slot : int;
}

let canonical_reg reg =
  Register.with_width reg B64

let standard_registers =
  let gprs = [
    Register.rax; Register.rcx; Register.rdx; Register.rbx;
    Register.rsp; Register.rbp; Register.rsi; Register.rdi;
    Register.r8;  Register.r9;  Register.r10; Register.r11;
    Register.r12; Register.r13; Register.r14; Register.r15;
  ] in
  let vregs = [
    Register.vip; Register.vsp; Register.vkey;
    Register.vtmp0; Register.vtmp1; Register.vtmp2; Register.vtmp3;
    Register.vx18;  Register.vx19;  Register.vx20;  Register.vx21;
    Register.vx22;  Register.vx23;  Register.vx24;  Register.vx25;
    Register.vx26;
  ] in
  List.map canonical_reg (gprs @ vregs)

let shuffle_list rng list =
  let arr = Array.of_list list in
  let n = Array.length arr in
  for i = n - 1 downto 1 do
    let k = Random.State.int rng (i + 1) in
    let tmp = arr.(i) in
    arr.(i) <- arr.(k);
    arr.(k) <- tmp
  done;
  Array.to_list arr

let create ?(seed = 0x5877) ?(permute = false) () =
  let reg_to_slot = Hashtbl.create 64 in
  let slot_to_reg = Hashtbl.create 64 in
  let rng = Random.State.make [| seed |] in
  let initial_regs =
    if permute then shuffle_list rng standard_registers
    else standard_registers
  in
  let current_slot = ref 0 in
  List.iter (fun reg ->
    let slot = !current_slot in
    Hashtbl.replace reg_to_slot reg slot;
    Hashtbl.replace slot_to_reg slot reg;
    incr current_slot
  ) initial_regs;
  { reg_to_slot; slot_to_reg; next_slot = !current_slot }

let slot_of_reg ctx reg =
  let canon = canonical_reg reg in
  match Hashtbl.find_opt ctx.reg_to_slot canon with
  | Some s -> s
  | None ->
      let s = ctx.next_slot in
      ctx.next_slot <- s + 1;
      Hashtbl.replace ctx.reg_to_slot canon s;
      Hashtbl.replace ctx.slot_to_reg s canon;
      s

let reg_of_slot ctx slot =
  Hashtbl.find_opt ctx.slot_to_reg slot

let alloc_scratch ctx =
  let s = ctx.next_slot in
  ctx.next_slot <- s + 1;
  s

let total_slots ctx =
  ctx.next_slot

let dump_mapping ctx =
  let list = ref [] in
  Hashtbl.iter (fun slot reg ->
    list := (slot, Register.to_string reg) :: !list
  ) ctx.slot_to_reg;
  List.sort (fun (s1, _) (s2, _) -> compare s1 s2) !list
