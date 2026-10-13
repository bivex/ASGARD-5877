open Ir

type discrepancy_kind =
  | RegMismatch of { reg : Register.t; expected : int64; actual : int64 }
  | CalleeSavedClobbered of { reg : Register.t; initial : int64; actual : int64 }
  | FlagsMismatch of { expected_flags : int64; actual_flags : int64; details : string }
  | MemoryMismatch of { addr : int64; expected_byte : int; actual_byte : int }
  | TrapMismatch of { expected_trap : string option; actual_trap : string option }
  | EvalError of string

type discrepancy = {
  trial_index : int;
  initial_regs : (Register.t * int64) list;
  expected_rax : int64;
  actual_rax : int64;
  kind : discrepancy_kind;
  details : string;
}

let corner_cases = [|
  0L;
  1L;
  -1L;
  2L;
  42L;
  1337L;
  0x7FFFFFFFFFFFFFFFL;
  0x8000000000000000L;
  0x7FFFFFFFL;
  0x80000000L;
  0xFFFFFFFFL;
  0xFFFFL;
  0x8000L;
  0xFFL;
  0x80L;
  0x5555555555555555L;
  Int64.lognot 0x5555555555555555L;
|]

let make_full_rand64 (rng : Random.State.t) : int64 =
  let w0 = Int64.of_int (Random.State.bits rng) in
  let w1 = Int64.of_int (Random.State.bits rng) in
  let w2 = Int64.of_int (Random.State.bits rng land 0xF) in
  let v = Int64.logor (Int64.shift_left w0 34) (Int64.logor (Int64.shift_left w1 4) w2) in
  if Random.State.bool rng then Int64.logor v 0x8000000000000000L else v

let rand_val (rng : Random.State.t) : int64 =
  if Random.State.int rng 4 = 0 then
    corner_cases.(Random.State.int rng (Array.length corner_cases))
  else
    make_full_rand64 rng

let all_gprs = [
  Register.rax; Register.rcx; Register.rdx; Register.rbx;
  Register.rsi; Register.rdi; Register.rbp;
  Register.r8;  Register.r9;  Register.r10; Register.r11;
  Register.r12; Register.r13; Register.r14; Register.r15;
]

let callee_saved_regs = [
  Register.rbx; Register.rbp;
  Register.r12; Register.r13; Register.r14; Register.r15;
]

let default_stack_base = 0x7FFFFFFF0000L

let generate_test_vector (rng : Random.State.t) (idx : int) : (Register.t * int64) list =
  let rsp_val = Int64.sub default_stack_base (Int64.of_int ((Random.State.int rng 16) * 16)) in
  if idx = 0 then
    (Register.rsp, default_stack_base) :: List.map (fun r -> (r, 0L)) all_gprs
  else if idx = 1 then
    (Register.rsp, default_stack_base) :: List.map (fun r -> (r, -1L)) all_gprs
  else if idx = 2 then
    (Register.rsp, default_stack_base) :: List.mapi (fun i r ->
      (r, if i mod 2 = 0 then 0x7FFFFFFFFFFFFFFFL else 0x8000000000000000L)) all_gprs
  else if idx = 3 then
    (Register.rsp, default_stack_base) :: List.mapi (fun i r ->
      (r, if i mod 2 = 0 then 0x5555555555555555L else Int64.lognot 0x5555555555555555L)) all_gprs
  else
    (Register.rsp, rsp_val) :: List.map (fun r -> (r, rand_val rng)) all_gprs

let find_reg (regs : (Register.t, int64) Hashtbl.t) (r : Register.t) : int64 =
  match Hashtbl.find_opt regs r with
  | Some v -> v
  | None -> 0L

let assert_equivalent
    ?(trials = 50)
    ?(seed = 0x58771337CAFEBABEL)
    ?(check_callee_saved = true)
    ?(check_flags = false)
    ?(check_memory = true)
    (orig_f : func)
    (trans_f : func) =
  let rng = Seed.make_rng seed in
  let rec loop idx =
    if idx >= trials then Ok ()
    else
      let input_regs = generate_test_vector rng idx in
      let init_reg_map = Hashtbl.create 16 in
      List.iter (fun (r, v) -> Hashtbl.replace init_reg_map r v) input_regs;
      match Reference_vm.evaluate ~initial_regs:input_regs orig_f with
      | Error msg ->
          Error {
            trial_index = idx;
            initial_regs = input_regs;
            expected_rax = 0L;
            actual_rax = 0L;
            kind = EvalError msg;
            details = Printf.sprintf "Original function evaluation error: %s" msg;
          }
      | Ok expected_snap ->
          match Reference_vm.evaluate ~initial_regs:input_regs trans_f with
          | Error msg ->
              Error {
                trial_index = idx;
                initial_regs = input_regs;
                expected_rax = expected_snap.final_rax;
                actual_rax = 0L;
                kind = EvalError msg;
                details = Printf.sprintf "Transformed function evaluation error: %s" msg;
              }
          | Ok trans_snap ->
              (* 1. Check traps / halts *)
              if expected_snap.final_trapped <> trans_snap.final_trapped then
                Error {
                  trial_index = idx;
                  initial_regs = input_regs;
                  expected_rax = expected_snap.final_rax;
                  actual_rax = trans_snap.final_rax;
                  kind = TrapMismatch {
                    expected_trap = expected_snap.final_trapped;
                    actual_trap = trans_snap.final_trapped;
                  };
                  details = Printf.sprintf "Trap status mismatch (expected %s, got %s)"
                    (Option.value ~default:"None" expected_snap.final_trapped)
                    (Option.value ~default:"None" trans_snap.final_trapped);
                }
              (* 2. Check RAX (primary return value) *)
              else if expected_snap.final_rax <> trans_snap.final_rax then
                Error {
                  trial_index = idx;
                  initial_regs = input_regs;
                  expected_rax = expected_snap.final_rax;
                  actual_rax = trans_snap.final_rax;
                  kind = RegMismatch {
                    reg = Register.rax;
                    expected = expected_snap.final_rax;
                    actual = trans_snap.final_rax;
                  };
                  details = Printf.sprintf "Mismatch in return value RAX (expected 0x%016LX, got 0x%016LX)"
                    expected_snap.final_rax trans_snap.final_rax;
                }
              else
                (* 3. Check callee-saved registers *)
                let callee_err =
                  if not check_callee_saved then None
                  else
                    List.find_map (fun r ->
                      let init_v = match Hashtbl.find_opt init_reg_map r with Some v -> v | None -> 0L in
                      let exp_v = find_reg expected_snap.registers r in
                      let act_v = find_reg trans_snap.registers r in
                      if exp_v = init_v && act_v <> init_v then
                        Some (CalleeSavedClobbered { reg = r; initial = init_v; actual = act_v },
                              Printf.sprintf "Callee-saved register %s clobbered (initial 0x%016LX, got 0x%016LX)"
                                (Register.to_string r) init_v act_v)
                      else if exp_v <> act_v then
                        Some (RegMismatch { reg = r; expected = exp_v; actual = act_v },
                              Printf.sprintf "Register %s mismatch (expected 0x%016LX, got 0x%016LX)"
                                (Register.to_string r) exp_v act_v)
                      else None
                    ) callee_saved_regs
                in
                match callee_err with
                | Some (kind, details) ->
                    Error {
                      trial_index = idx;
                      initial_regs = input_regs;
                      expected_rax = expected_snap.final_rax;
                      actual_rax = trans_snap.final_rax;
                      kind;
                      details;
                    }
                | None ->
                    (* 4. Check memory writes *)
                    let mem_err =
                      if not check_memory then None
                      else
                        let mismatch = ref None in
                        Hashtbl.iter (fun addr exp_b ->
                          if Option.is_none !mismatch then
                            let act_b = match Hashtbl.find_opt trans_snap.memory_writes addr with
                              | Some b -> b
                              | None -> -1
                            in
                            if act_b <> exp_b then
                              mismatch := Some (addr, exp_b, act_b)
                        ) expected_snap.memory_writes;
                        match !mismatch with
                        | Some (addr, exp_b, act_b) ->
                            Some (MemoryMismatch { addr; expected_byte = exp_b; actual_byte = act_b },
                                  Printf.sprintf "Memory mismatch at [0x%016LX]: expected byte 0x%02X, got 0x%02X"
                                    addr exp_b act_b)
                        | None -> None
                    in
                    match mem_err with
                    | Some (kind, details) ->
                        Error {
                          trial_index = idx;
                          initial_regs = input_regs;
                          expected_rax = expected_snap.final_rax;
                          actual_rax = trans_snap.final_rax;
                          kind;
                          details;
                        }
                    | None ->
                        (* 5. Check flags if requested *)
                        if check_flags && expected_snap.final_rflags <> trans_snap.final_rflags then
                          Error {
                            trial_index = idx;
                            initial_regs = input_regs;
                            expected_rax = expected_snap.final_rax;
                            actual_rax = trans_snap.final_rax;
                            kind = FlagsMismatch {
                              expected_flags = expected_snap.final_rflags;
                              actual_flags = trans_snap.final_rflags;
                              details = Printf.sprintf "Flags mismatch: expected RFLAGS 0x%016LX, got 0x%016LX"
                                expected_snap.final_rflags trans_snap.final_rflags;
                            };
                            details = Printf.sprintf "Flags mismatch: expected RFLAGS 0x%016LX, got 0x%016LX"
                              expected_snap.final_rflags trans_snap.final_rflags;
                          }
                        else
                          loop (idx + 1)
  in
  loop 0

