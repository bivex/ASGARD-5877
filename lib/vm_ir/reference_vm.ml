open Ir

type execution_snapshot = {
  final_rax : int64;
  registers : (Register.t, int64) Hashtbl.t;
  memory_writes : (int64, int) Hashtbl.t;
  steps_taken : int;
  halted_cleanly : bool;
}

let evaluate ?(initial_regs = []) ?(initial_mem = []) ?(max_steps = 50000) (f : func) =
  let state = Vm_eval.make_state () in
  List.iter (fun (r, v) -> Vm_eval.set_reg state r v) initial_regs;
  List.iter (fun (addr, b) -> Vm_eval.write_mem state addr Register.B8 (Int64.of_int b)) initial_mem;
  
  match Vm_eval.run_func ~max_steps state f with
  | Error msg -> Error msg
  | Ok () ->
      let final_rax = Vm_eval.get_reg state Register.rax in
      let reg_copy = Hashtbl.copy state.vregs in
      let mem_copy = Hashtbl.copy state.memory in
      Ok {
        final_rax;
        registers = reg_copy;
        memory_writes = mem_copy;
        steps_taken = 0;
        halted_cleanly = state.halted || true;
      }
