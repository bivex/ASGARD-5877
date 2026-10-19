(** Invariant guard for the protection pipeline.

    Every phase of the Stack-VM packager rewrites the program, and a
    rewrite that breaks an invariant is not a crash: the pipeline happily
    emits a protected binary that is unrunnable, or whose bytecode
    decrypts into garbage.  Nothing in the build noticed, because the
    invariant checker of [Stack_invariants] was never called on the
    pipeline itself.

    [check_phase_invariants] closes that hole.  It is called after every
    phase of the packager and classifies the violations:

    - control-flow violations (missing entry block, missing jump target,
      missing terminator, a context slot outside the declared range) and
      rolling-key violations (the key disagrees at a merge point) are
      FATAL: no later phase repairs them, and the binary would be
      broken for good;

    - stack-effect violations (an underflow, a non-zero exit delta) are
      reported but not fatal in the intermediate phases, because the
      balance pass at the end of the pipeline exists precisely to repair
      them.  In the FINAL phase they are fatal as well.

    A fatal violation raises [Failure] with a readable report, so the
    build stops instead of shipping a broken binary. *)

open Stack_ir

let report errs = String.concat "\n      " errs

let check_phase_invariants ~(phase : string) ~(final : bool) (prog : program) : unit =
  let cfg_errs =
    match Stack_invariants.check_cfg_invariants prog with
    | Ok () -> []
    | Error errs ->
        List.map
          (fun v ->
            Stack_invariants.violation_to_string (Stack_invariants.CfgViolation v))
          errs
  in
  let key_errs =
    match Stack_invariants.check_key_invariants prog with
    | Ok () -> []
    | Error errs ->
        List.map
          (fun v ->
            Stack_invariants.violation_to_string (Stack_invariants.KeyViolation v))
          errs
  in
  let stack_errs =
    match Stack_invariants.check_stack_invariants prog with
    | Ok () -> []
    | Error errs ->
        List.map
          (fun v ->
            Stack_invariants.violation_to_string (Stack_invariants.StackViolation v))
          errs
  in
  if cfg_errs <> [] || key_errs <> [] then begin
    let parts =
      (if cfg_errs = [] then [] else [ "control flow: " ^ report cfg_errs ])
      @ (if key_errs = [] then [] else [ "rolling key: " ^ report key_errs ])
    in
    let msg =
      Printf.sprintf "[asgard] phase %s broke the program invariants:\n      %s"
        phase (String.concat "\n      " parts)
    in
    prerr_endline msg;
    failwith msg
  end;
  if stack_errs <> [] then begin
    let msg =
      Printf.sprintf
        "[asgard] phase %s: stack invariant violations%s:\n      %s"
        phase
        (if final then " (fatal)" else " (repaired by the balance pass)")
        (report stack_errs)
    in
    prerr_endline msg;
    if final then failwith msg
  end
