(** Flag liveness analysis for stack programs
    ────────────────────────────────────────────
    Several VM ops write architectural flags (Add/Sub/Nor/.../Cmp/Test) and
    several consume them (JccRel/Setcc/Cmov/PushFlags). Obfuscation passes
    that inject flag-writing junk (ghost Arith, MBA synthesis) or rewrite
    instructions must not do so while a previously produced flag value is
    still live, or the consumer observes corrupted flags.

    The analysis is intra-block only. That is sound for this pipeline:
    lowering keeps Cmp/Test directly attached to their branch consumer in
    the same block, and the CFF pass (which moves terminators around) runs
    last, after ghost/MBA. *)

open Stack_ir

(** Ops that overwrite the flag state in this VM.
    Mul/Div/Idiv are flag-neutral (they do not touch flags);
    PopFlags kills liveness by overwriting the whole register. *)
let produces_flags = function
  | Add | Sub | Nor | Nand | Shl | Shr | Sar | Cmp | Test | PopFlags -> true
  | _ -> false

(** Ops that read the current flag state. *)
let consumes_flags = function
  | JccRel _ | Setcc _ | Cmov _ | PushFlags -> true
  | _ -> false

(** [analyze_arr arr] where [arr.(i)] is the i-th op of a block.
    Result [live.(i)] is [true] when the flags entering instruction [i]
    are still needed by a later consumer; [live.(n)] (after the last op)
    is [false] — flags never live across block boundaries. *)
let analyze_arr arr =
  let n = Array.length arr in
  let live = Array.make (n + 1) false in
  for i = n - 1 downto 0 do
    live.(i) <-
      if produces_flags arr.(i) then false
      else if consumes_flags arr.(i) then true
      else live.(i + 1)
  done;
  live

let analyze_list ops = analyze_arr (Array.of_list ops)
