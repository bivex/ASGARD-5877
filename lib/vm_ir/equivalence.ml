open Ir

type discrepancy = {
  trial_index : int;
  initial_regs : (Register.t * int64) list;
  expected_rax : int64;
  actual_rax : int64;
  details : string;
}

let generate_test_vector (rng : Random.State.t) =
  let make_rand64 () =
    let h = Int64.of_int (Random.State.bits rng) in
    let l = Int64.of_int (Random.State.bits rng) in
    Int64.logor (Int64.shift_left h 30) l
  in
  [
    (Register.rax, make_rand64 ());
    (Register.rcx, make_rand64 ());
    (Register.rdx, make_rand64 ());
    (Register.rbx, make_rand64 ());
    (Register.rsi, make_rand64 ());
    (Register.rdi, make_rand64 ());
  ]

let assert_equivalent ?(trials = 50) ?(seed = 0x58771337CAFEBABEL) (orig_f : func) (trans_f : func) =
  let rng = Seed.make_rng seed in
  let rec loop idx =
    if idx >= trials then Ok ()
    else
      let input_regs =
        if idx = 0 then
          [ (Register.rax, 0L); (Register.rcx, 0L); (Register.rdx, 0L); (Register.rbx, 0L); (Register.rsi, 0L); (Register.rdi, 0L) ]
        else if idx = 1 then
          [ (Register.rax, -1L); (Register.rcx, -1L); (Register.rdx, -1L); (Register.rbx, -1L); (Register.rsi, -1L); (Register.rdi, -1L) ]
        else
          generate_test_vector rng
      in
      match Reference_vm.evaluate ~initial_regs:input_regs orig_f with
      | Error msg ->
          Error {
            trial_index = idx;
            initial_regs = input_regs;
            expected_rax = 0L;
            actual_rax = 0L;
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
                details = Printf.sprintf "Transformed function evaluation error: %s" msg;
              }
          | Ok trans_snap ->
              if expected_snap.final_rax <> trans_snap.final_rax then
                Error {
                  trial_index = idx;
                  initial_regs = input_regs;
                  expected_rax = expected_snap.final_rax;
                  actual_rax = trans_snap.final_rax;
                  details = Printf.sprintf "Mismatch in return value RAX (expected 0x%LX, got 0x%LX)"
                    expected_snap.final_rax trans_snap.final_rax;
                }
              else
                loop (idx + 1)
  in
  loop 0
