(* test/test_stack_jit_fuzz.ml
   Deterministic QCheck fuzzers for the Stack-JIT chunker
   (lib/stack_vm/stack_jit_chunker.ml), the SJIT tier-1 lowering of the
   JIT stack machine.

   Every property is driven by Random.State.make [| seed |] so any failure
   is exactly reproducible from the counterexample seed; the offending
   Stack-IR trace is printed with the mismatch.

   - stack_jit_fuzz_differential_trace_vs_chunks: a generated well-formed
     straight-line trace (no underflow, live depth within the 4-slot
     window, identity-mapped context registers) must translate without
     error, and simulate_chunks must agree with reference_eval on the
     observable window: result slot 0, context slots 1..ctx_slots-1, and
     the bottom-of-stack window slots.  Each trace runs at three
     Kolakoski scales - chunk fission and Thue-Morse padding must never
     change semantics.  Translation bookkeeping is checked alongside:
     real/dummy instruction accounting, chunk capacity, A001511
     invalidation schedule length and final/max depth match an independent
     depth model of the trace.
   - stack_jit_fuzz_program_jump_patch_targets: random multi-block
     programs (JmpRel / JccRel+JmpRel terminals) translate whole and every
     patched JMP/JCC immediate lands inside the chunk index space.
   - stack_jit_fuzz_translate_total_robustness: arbitrary op soup (every
     constructor, out-of-range and negative registers, branches, escapes)
     never raises out of translate_trace, and simulate_chunks never
     raises on chunks that carry no control flow. *)

open Stack_vm
open Stack_ir
open Vm_ir

module C = Stack_jit_chunker

let op_prefix = "asgard_rd_jit::JIT_OP_"

let suffix (op : string) : string =
  String.sub op (String.length op_prefix) (String.length op - String.length op_prefix)

let window_size = C.stack_base + C.max_stack_depth

(* ------------------------------------------------------------------ *)
(* PRNG value pools                                                    *)
(* ------------------------------------------------------------------ *)

let conds =
  [| Flags.E; Flags.NE; Flags.B; Flags.AE; Flags.BE; Flags.A; Flags.S; Flags.NS;
     Flags.P; Flags.NP; Flags.L; Flags.GE; Flags.LE; Flags.G; Flags.O; Flags.NO;
     Flags.ALWAYS |]

let interesting_imms =
  [| 0L; 1L; -1L; 2L; 63L; 64L; 65L; 127L; 255L; 256L; 0xFFFFL; 0xFFFFFFFFL;
     0x100000000L; 0x7FFFFFFFFFFFFFFFL; 0x8000000000000000L;
     0xFFFFFFFFFFFFFFFFL; 0xDEADBEEFL; 0x1234567890ABCDEFL; 0xF0F0F0F0F0F0F0F0L |]

let shift_counts = [| 0L; 1L; 7L; 31L; 32L; 63L; 64L; 65L; 127L; -1L |]

let rand_full64 (rng : Random.State.t) : int64 =
  let v = Random.State.int64 rng Int64.max_int in
  if Random.State.bool rng then v else Int64.neg v

let imm (rng : Random.State.t) : int64 =
  if Random.State.bool rng then rand_full64 rng
  else interesting_imms.(Random.State.int rng (Array.length interesting_imms))

let shift_count (rng : Random.State.t) : int64 =
  if Random.State.bool rng then Int64.of_int (Random.State.int rng 130)
  else shift_counts.(Random.State.int rng (Array.length shift_counts))

let reg (rng : Random.State.t) : int =
  let r = Random.State.int rng (C.ctx_slots - 1) in
  if r >= 4 then r + 1 else r

let cond (rng : Random.State.t) : Flags.condition =
  conds.(Random.State.int rng (Array.length conds))

let width (rng : Random.State.t) : int =
  [| 1; 2; 4; 8 |].(Random.State.int rng 4)

(* ------------------------------------------------------------------ *)
(* Independent depth model (mirrors translate_trace's vdepth rules)    *)
(* ------------------------------------------------------------------ *)

(* (net delta, transient pushes above the resting depth).  Setcc pushes a
   zero destination plus a scratch one and pops the scratch: resting +1,
   transient +1.  Rot keeps depth at three live elements (rotation) and
   pops the count at two (rotate-right). *)
let op_effect (d : int) (op : stack_op) : int * int =
  match op with
  | PushImm _ | PushReg _ | ResolveSym _ | AddImmImm _ | SubImmImm _
  | AddRegImm _ | Dup | CallExtern _ -> (1, 0)
  | Dup2 -> (2, 0)
  | Setcc _ -> (1, 1)
  | PopReg _ | Cmov _ -> (-1, 0)
  | Add | Sub | Mul | Mulh | Imulh | Nand | Nor | Shl | Shr | Sar | Div | Idiv ->
      (-1, 0)
  | Cmp | Test | WriteMem _ -> (-2, 0)
  | Rot -> if d >= 3 then (0, 0) else (-1, 0)
  | Swap | ReadMem _ | AddImm _ | SubImm _ | Bswap | Clz | Ctz | Rbit | Popcnt
  | SetRegImm _ | Exit -> (0, 0)
  | PushFlags -> (1, 0)
  | PopFlags -> (-1, 0)
  | JmpRel _ | JccRel _ | KeyAdjust _ | KeyFeedback _ | NativeEscape _
  | EnterVM _ | ExitVM _ ->
      (0, 0)

let depth_model_from (d0 : int) (ops : stack_op list) : int * int =
  let d = ref d0 and mx = ref d0 in
  List.iter
    (fun op ->
      let delta, transient = op_effect !d op in
      d := !d + delta;
      mx := max !mx (!d + transient))
    ops;
  (!d, !mx)

let depth_model (ops : stack_op list) : int * int = depth_model_from 0 ops

(* A step fits the translator's window iff the depth never goes negative
   and never exceeds max_stack_depth, counting transient pushes. *)
let fits_window (d0 : int) (ops : stack_op list) : bool =
  let d = ref d0 and ok = ref true in
  List.iter
    (fun op ->
      if !ok then begin
        let delta, transient = op_effect !d op in
        d := !d + delta;
        if !d < 0 || !d + transient > C.max_stack_depth then ok := false
      end)
    ops;
  !ok

(* ------------------------------------------------------------------ *)
(* Well-formed trace generator                                         *)
(* ------------------------------------------------------------------ *)

let binary_op (rng : Random.State.t) : stack_op =
  match Random.State.int rng 11 with
  | 0 -> Add | 1 -> Sub | 2 -> Mul | 3 -> Mulh | 4 -> Imulh | 5 -> Nand
  | 6 -> Nor | 7 -> Div | 8 -> Idiv | 9 -> Shl | 10 -> Shr | _ -> Sar

(* [push count; shift-or-rot]: drives the immediate-peephole folds
   (SHL_RI/SHR_RI/SAR_RI/ROR_RI/CMP_RI) as well as the register forms. *)
let shift_unit (rng : Random.State.t) : stack_op list =
  let op =
    match Random.State.int rng 5 with
    | 0 -> Shl | 1 -> Shr | 2 -> Sar | 3 -> Rot | _ -> Div
  in
  [ PushImm (shift_count rng); op ]

(* (min start depth, max start depth, step generator). *)
let choice_pool : (int * int * (Random.State.t -> stack_op list)) array =
  [| (0, 3, fun r -> [ PushImm (imm r) ]);
     (0, 3, fun r -> [ PushImm (imm r) ]);
     (0, 3, fun r -> [ PushImm (imm r) ]);
     (0, 3, fun r -> [ PushReg (reg r) ]);
     (0, 3, fun r -> [ AddImmImm (imm r, imm r) ]);
     (0, 3, fun r -> [ SubImmImm (imm r, imm r) ]);
     (0, 3, fun r -> [ AddRegImm (reg r, imm r) ]);
     (0, 3, fun r -> [ ResolveSym (Random.State.int r 16) ]);
     (0, 2, fun r -> [ Setcc (cond r) ]);
     (1, 3, fun _r -> [ Dup ]);
     (2, 2, fun _r -> [ Dup2 ]);
     (0, 3, fun r -> [ CallExtern (Random.State.int r 16) ]);
     (1, 4, fun r -> [ PopReg (reg r) ]);
     (1, 4, fun r -> [ Cmov (cond r, reg r) ]);
     (1, 4, fun r -> [ AddImm (imm r) ]);
     (1, 4, fun r -> [ SubImm (imm r) ]);
     (1, 4, fun _r -> [ Bswap ]);
     (1, 4, fun _r -> [ Clz ]);
     (1, 4, fun _r -> [ Ctz ]);
     (1, 4, fun _r -> [ Rbit ]);
     (1, 4, fun _r -> [ Popcnt ]);
     (1, 4, fun r -> [ ReadMem (width r) ]);
     (2, 4, fun r -> [ binary_op r ]);
     (2, 4, fun _r -> [ Swap ]);
     (2, 4, fun _r -> [ Rot ]);
     (2, 4, fun _r -> [ Cmp ]);
     (2, 4, fun _r -> [ Test ]);
     (2, 4, fun r -> [ WriteMem (width r) ]);
     (1, 3, fun r -> shift_unit r);
     (0, 4, fun r -> [ SetRegImm (reg r, imm r) ]);
     (0, 4, fun _r -> [ Exit ]);
     (0, 3, fun _r -> [ PushFlags ]);
     (1, 4, fun _r -> [ PopFlags ]) |]

let flags_delta (op : stack_op) : int =
  match op with PushFlags -> 1 | PopFlags -> -1 | _ -> 0

let gen_step ~(flags_open : int) (rng : Random.State.t) (d : int) : stack_op list option =
  let pool =
    Array.of_list
      (List.filter (fun (mn, mx, _) -> d >= mn && d <= mx)
         (Array.to_list choice_pool))
  in
  let attempts = ref 0 in
  let rec go () =
    if !attempts > 16 then None
    else begin
      incr attempts;
      let (_, _, gen) = pool.(Random.State.int rng (Array.length pool)) in
      let step = gen rng in
      let opens = List.fold_left (fun a op -> a + flags_delta op) 0 step in
      let d', _ = depth_model_from d step in
      if flags_open + opens < 0 || flags_open + opens > 2
         || d' < flags_open + opens
         || not (fits_window d step)
      then go ()
      else Some step
    end
  in
  go ()

let gen_ops (rng : Random.State.t) ~(len : int) : stack_op list =
  let ops = ref [] and d = ref 0 and flags_open = ref 0 and emitted = ref 0 in
  while !emitted < len do
    match gen_step ~flags_open:!flags_open rng !d with
    | None -> incr emitted
    | Some step ->
        ops := List.rev_append step !ops;
        let d', _ = depth_model_from !d step in
        d := d';
        flags_open := !flags_open + List.fold_left (fun a op -> a + flags_delta op) 0 step;
        emitted := !emitted + List.length step
  done;
  (* close any open PushFlags: an unbalanced trace must not be generated *)
  let closers = List.init !flags_open (fun _ -> PopFlags) in
  List.rev !ops @ closers

(* ------------------------------------------------------------------ *)
(* Failure reporting                                                   *)
(* ------------------------------------------------------------------ *)

let trace_to_string (ops : stack_op list) : string =
  String.concat "; " (List.map Stack_ir.op_to_string ops)

let verify ~(seed : int) ~(ctx : string) (checks : (string * bool * string) list) : bool =
  let failed = List.filter (fun (_, ok, _) -> not ok) checks in
  if failed = [] then true
  else begin
    Printf.eprintf "[stack-jit-fuzz] seed=%d %s FAILED\n" seed ctx;
    List.iter
      (fun (name, _, detail) -> Printf.eprintf "  - %s: %s\n" name detail)
      failed;
    false
  end

(* ------------------------------------------------------------------ *)
(* Property 1: differential + bookkeeping, per scale                   *)
(* ------------------------------------------------------------------ *)

let check_translation ~(seed : int) ~(tag : string) (ops : stack_op list)
    (regs : int64 array) (ref_stk : int64 list) (tr : C.translation) : bool =
  let items = List.concat tr.chunks in
  let depth = List.length ref_stk in
  let model_final, model_max = depth_model ops in
  let sim =
    try
      let g = Array.make window_size 0L in
      C.simulate_chunks tr.chunks g;
      Ok g
    with e ->
      Printf.eprintf "[stack-jit-fuzz] seed=%d scale=%s simulate_chunks raised %s\n  ops=[%s]\n"
        seed tag (Printexc.to_string e) (trace_to_string ops);
      Error ()
  in
  match sim with
  | Error () -> false
  | Ok gprs ->
      let i64_eq a b = Int64.compare a b = 0 in
      let exp_r0 = match ref_stk with top :: _ -> top | [] -> regs.(0) in
      let reg_bad =
        let bad = ref [] in
        for r = 1 to C.ctx_slots - 1 do
          if not (i64_eq gprs.(r) regs.(r)) then bad := (r, gprs.(r), regs.(r)) :: !bad
        done;
        List.rev !bad
      in
      let win_bad =
        let n = min C.max_stack_depth depth in
        let bad = ref [] in
        for k = 0 to n - 1 do
          let want = List.nth ref_stk (depth - 1 - k) in
          if not (i64_eq gprs.(C.stack_base + k) want) then
            bad := (C.stack_base + k, gprs.(C.stack_base + k), want) :: !bad
        done;
        List.rev !bad
      in
      let slot_dump (slots : (int * int64 * int64) list) =
        String.concat ", "
          (List.map
             (fun (s, got, want) -> Printf.sprintf "slot%d got=0x%Lx want=0x%Lx" s got want)
             slots)
      in
      let n_dummy_items =
        List.length (List.filter (fun (op, _, _, _) -> suffix op = "NOP") items)
      in
      let cap = Rd_jit_vm.Nano_jit_slot.nano_max_chunk_instrs in
      let chunk_bad =
        List.filter (fun c -> c = [] || List.length c > cap) tr.chunks
      in
      verify ~seed ~ctx:("differential scale=" ^ tag)
        [ ("result-slot0", i64_eq gprs.(0) exp_r0,
           Printf.sprintf "got=0x%Lx want=0x%Lx" gprs.(0) exp_r0);
          ("context-regs", reg_bad = [], "mismatches: " ^ slot_dump reg_bad);
          ("stack-window", win_bad = [], "mismatches: " ^ slot_dump win_bad);
          ( "final-depth",
            tr.final_depth = depth && tr.final_depth = model_final,
            Printf.sprintf "translation=%d reference=%d model=%d" tr.final_depth depth model_final );
          ( "max-depth",
            tr.max_depth = model_max,
            Printf.sprintf "translation=%d model=%d" tr.max_depth model_max );
          ( "item-accounting",
            List.length items = tr.real_instrs + tr.dummy_instrs
            && n_dummy_items = tr.dummy_instrs,
            Printf.sprintf "items=%d real=%d dummy=%d nop-items=%d"
              (List.length items) tr.real_instrs tr.dummy_instrs n_dummy_items );
          ( "schedule",
            Array.length tr.invalidation_schedule = List.length tr.chunks,
            Printf.sprintf "schedule=%d chunks=%d"
              (Array.length tr.invalidation_schedule) (List.length tr.chunks) );
          ( "chunks",
            chunk_bad = [],
            Printf.sprintf "%d chunk(s) empty or over cap %d" (List.length chunk_bad) cap ) ]

let run_differential ~(seed : int) (ops : stack_op list) : bool =
  let regs = Array.make C.ctx_slots 0L in
  let ref_stk =
    try C.reference_eval regs ops
    with e ->
      Printf.eprintf "[stack-jit-fuzz] seed=%d reference_eval raised %s\n  ops=[%s]\n"
        seed (Printexc.to_string e) (trace_to_string ops);
      raise e
  in
  let scales : (string * (C.translation, string) result) list =
    [ ("1", C.translate_trace ~scale:1 () ops);
      ("3", C.translate_trace ~scale:3 () ops);
      ("default", C.translate_trace () ops) ]
  in
  let all_ok =
    List.for_all
      (fun (tag, res) ->
         match res with
         | Error e ->
             Printf.eprintf
               "[stack-jit-fuzz] seed=%d scale=%s well-formed trace rejected: %s\n  ops=[%s]\n"
               seed tag e (trace_to_string ops);
             false
         | Ok tr -> check_translation ~seed ~tag ops regs ref_stk tr)
      scales
  in
  if not all_ok then
    Printf.eprintf "  repro: seed=%d\n  ops=[%s]\n" seed (trace_to_string ops);
  all_ok

let trace_of_seed (seed : int) : stack_op list =
  let rng = Random.State.make [| seed |] in
  gen_ops rng ~len:(8 + Random.State.int rng 40)

let prop_differential =
  QCheck.Test.make
    ~name:"stack_jit_fuzz_differential_trace_vs_chunks" ~count:1000 QCheck.int
    (fun seed -> run_differential ~seed (trace_of_seed seed))

(* ------------------------------------------------------------------ *)
(* Property 2: multi-block program jump patching                       *)
(* ------------------------------------------------------------------ *)

let gen_program (rng : Random.State.t) : Stack_ir.program =
  let n_blocks = 1 + Random.State.int rng 4 in
  let blocks = Hashtbl.create 4 in
  for id = 0 to n_blocks - 1 do
    let body = gen_ops rng ~len:(Random.State.int rng 12) in
    let terminal =
      match Random.State.int rng 5 with
      | 0 -> [ JmpRel (Random.State.int rng n_blocks) ]
      | 1 ->
          [ JccRel (Random.State.int rng n_blocks, cond rng);
            JmpRel (Random.State.int rng n_blocks) ]
      | 2 -> [ Exit ]
      | _ -> []
    in
    Hashtbl.replace blocks id
      (Stack_ir.make_block id (Printf.sprintf "b%d" id) (body @ terminal))
  done;
  { entry_id = 0; blocks; context_slots = C.ctx_slots }

let prop_program =
  QCheck.Test.make
    ~name:"stack_jit_fuzz_program_jump_patch_targets_in_range" ~count:400 QCheck.int
    (fun seed ->
      let rng = Random.State.make [| seed |] in
      let prog = gen_program rng in
      match C.translate_program () prog with
      | Error e ->
          Printf.eprintf "[stack-jit-fuzz] seed=%d program rejected: %s\n" seed e;
          false
      | Ok tr ->
          let n = List.length tr.chunks in
          let items = List.concat tr.chunks in
          (* Patched targets are global chunk indices in [0, n]: an empty
             target block contributes no chunks and its offset - like the
             next-chunk fallback - is n, the arena's past-the-end halt
             (execute_sealed_function guards the loop with k < num_chunks,
             nano_jit_slot.ml). *)
          let target_bad = ref [] in
          List.iter
            (fun (op, _, _, imm) ->
               match suffix op with
               | "JMP" ->
                   let t = Int64.to_int imm in
                   if not (0 <= t && t <= n) then target_bad := (op, t) :: !target_bad
               | "JCC" ->
                   let t = Int64.to_int (Int64.logand imm 0xFFFFFFFFL) in
                   let f =
                     Int64.to_int
                       (Int64.logand (Int64.shift_right_logical imm 32) 0xFFFFL)
                   in
                   if not (0 <= t && t <= n && 0 <= f && f <= n) then
                     target_bad := (op, t) :: !target_bad
               | _ -> ())
            items;
          let cap = Rd_jit_vm.Nano_jit_slot.nano_max_chunk_instrs in
          let chunk_bad = List.filter (fun c -> c = [] || List.length c > cap) tr.chunks in
          verify ~seed ~ctx:"program"
            [ ( "jump-patch-targets",
                !target_bad = [],
                Printf.sprintf "n_chunks=%d bad=%s" n
                  (String.concat ", "
                     (List.map
                        (fun (op, t) -> Printf.sprintf "%s->%d" op t)
                        !target_bad)) );
              ( "schedule",
                Array.length tr.invalidation_schedule = n,
                Printf.sprintf "schedule=%d chunks=%d"
                  (Array.length tr.invalidation_schedule) n );
              ( "chunks",
                chunk_bad = [],
                Printf.sprintf "%d chunk(s) empty or over cap %d"
                  (List.length chunk_bad) cap ) ])

(* ------------------------------------------------------------------ *)
(* Property 3: total robustness on arbitrary op soup                   *)
(* ------------------------------------------------------------------ *)

let any_reg (rng : Random.State.t) : int =
  match Random.State.int rng 4 with
  | 0 -> -(1 + Random.State.int rng 4)
  | 1 -> Random.State.int rng 40
  | _ -> Random.State.int rng C.ctx_slots

let any_op (rng : Random.State.t) : stack_op =
  match Random.State.int rng 45 with
  | 0 -> PushImm (imm rng)
  | 1 -> PushReg (any_reg rng)
  | 2 -> PopReg (any_reg rng)
  | 3 -> ReadMem (width rng)
  | 4 -> WriteMem (width rng)
  | 5 -> Add
  | 6 -> Sub
  | 7 -> Mul
  | 8 -> Mulh
  | 9 -> Imulh
  | 10 -> Nor
  | 11 -> Nand
  | 12 -> Shl
  | 13 -> Shr
  | 14 -> Sar
  | 15 -> Div
  | 16 -> Idiv
  | 17 -> Dup
  | 18 -> Dup2
  | 19 -> Rot
  | 20 -> Swap
  | 21 -> PushFlags
  | 22 -> PopFlags
  | 23 -> JmpRel (Random.State.int rng 8 - 2)
  | 24 -> JccRel (Random.State.int rng 8 - 2, cond rng)
  | 25 -> KeyAdjust (imm rng)
  | 26 -> Exit
  | 27 -> CallExtern (Random.State.int rng 8)
  | 28 -> ResolveSym (Random.State.int rng 8 - 2)
  | 29 -> Setcc (cond rng)
  | 30 -> Cmov (cond rng, any_reg rng)
  | 31 -> Cmp
  | 32 -> Test
  | 33 -> SetRegImm (any_reg rng, imm rng)
  | 34 -> AddRegImm (any_reg rng, imm rng)
  | 35 -> AddImm (imm rng)
  | 36 -> SubImm (imm rng)
  | 37 -> AddImmImm (imm rng, imm rng)
  | 38 -> SubImmImm (imm rng, imm rng)
  | 39 -> KeyFeedback (any_reg rng, imm rng)
  | 40 -> Bswap
  | 41 -> Clz
  | 42 -> Ctz
  | 43 -> Rbit
  | 44 -> Popcnt
  | _ -> NativeEscape (Random.State.int rng 4, any_reg rng, any_reg rng, any_reg rng, [])

(* translate_trace must always answer with a result - rejections are
   Error strings, never exceptions; accepted chunks must simulate without
   raising whenever they carry no control flow (JMP/JCC, which the
   straight-line simulator deliberately does not execute). *)
let robust_case ~(seed : int) ~(label : string) ~(allow_branches : bool)
    (ops : stack_op list) : bool =
  let res =
    try
      Ok
        (if allow_branches then C.translate_trace ~allow_branches:true () ops
         else C.translate_trace () ops)
    with e ->
      Printf.eprintf "[stack-jit-fuzz] seed=%d %s translate_trace raised %s\n  ops=[%s]\n"
        seed label (Printexc.to_string e) (trace_to_string ops);
      Error ()
  in
  match res with
  | Error () -> false
  | Ok (Error _) -> true
  | Ok (Ok tr) ->
      let has_cf =
        List.exists
          (fun (op, _, _, _) ->
             let s = suffix op in s = "JMP" || s = "JCC")
          (List.concat tr.chunks)
      in
      if has_cf then true
      else (
        try
          C.simulate_chunks tr.chunks (Array.make window_size 0L);
          true
        with e ->
          Printf.eprintf
            "[stack-jit-fuzz] seed=%d %s simulate_chunks raised %s\n  ops=[%s]\n"
            seed label (Printexc.to_string e) (trace_to_string ops);
          false)

let prop_robustness =
  QCheck.Test.make
    ~name:"stack_jit_fuzz_translate_total_robustness" ~count:1000 QCheck.int
    (fun seed ->
      let rng = Random.State.make [| seed |] in
      let ops = List.init (Random.State.int rng 25) (fun _ -> any_op rng) in
      robust_case ~seed ~label:"default" ~allow_branches:false ops
      && robust_case ~seed ~label:"allow_branches" ~allow_branches:true ops)

(* ------------------------------------------------------------------ *)
(* Deterministic regression replay                                     *)
(* ------------------------------------------------------------------ *)

(* QCheck samples a fresh random seed per run, so a counterexample is
   only observable through the seed printed in the failure output.  These
   handwritten traces pin each bug the campaign found (they go red if any
   fix is reverted), the seed list replays every counterexample seed
   captured during the campaign, and SJIT_FUZZ_REPLAY="s1,s2,..." replays
   any newly reported seed exactly:

     SJIT_FUZZ_REPLAY=<seed> run_tests.exe test "Stack-JIT" 19           *)

let pin_traces : (string * stack_op list) list =
  [ ( "addregimm-pushes-and-leaves-register",
      (* fused PushReg+AddImm: stack [22; 15], register 1 stays 10 *)
      [ SetRegImm (1, 10L); AddRegImm (1, 5L); AddRegImm (1, 7L) ] );
    ( "callextern-returns-zero-into-slot0",
      (* reg0 <- 0xF0..F0, call clobbers slot 0 with 0 and pushes it,
         so the Add yields 0xF0..F0 + 0, not 2 * 0xF0..F0 *)
      [ PushImm 0xF0F0F0F0F0F0F0F0L; Cmov (Flags.ALWAYS, 0); CallExtern 0;
        PushReg 0; Add ] );
    ( "shift-by-register-count",
      (* count comes from a register: SHL_RR with count & 63 = 4 *)
      [ SetRegImm (2, 4L); PushImm 0xFFL; PushReg 2; Shl ] ) ]

(* A jump to a trailing empty block patches to chunk index n_chunks - the
   arena's past-the-end halt (execute_sealed_function, k < num_chunks). *)
let pin_program () : Stack_ir.program =
  let blocks = Hashtbl.create 3 in
  Hashtbl.replace blocks 0 (Stack_ir.make_block 0 "b0" [ PushImm 5L; JmpRel 2 ]);
  Hashtbl.replace blocks 1 (Stack_ir.make_block 1 "b1" [ Exit ]);
  Hashtbl.replace blocks 2 (Stack_ir.make_block 2 "b2" []);
  { entry_id = 0; blocks; context_slots = C.ctx_slots }

(* Every seed that produced a counterexample during the fuzz campaign
   (AddRegImm depth corruption, CallExtern slot-0 staleness, program
   JMP/JCC past-the-end halt). *)
let regression_seeds : int list =
  [ 2859343975888491635; 1429671987944245818; 1250962989451215091;
    625481494725607546; 312740747362803773; 273648153942453302;
    3200443008385864437; 3200443006895542026; (-1255454074270668600);
    3402412065866005812; (-553988316402202730); (-2895258771272862432);
    (-2158051594160398426); 275362227604612325;
    2737435048197119166; 2736098409989991667; 2736098409988747434;
    3261261766892098765; 3261261766880234364; 3159347336665227041 ]

let replay_seed (seed : int) : bool =
  let ok_diff = run_differential ~seed (trace_of_seed seed) in
  let rng = Random.State.make [| seed |] in
  let ok_prog =
    match C.translate_program () (gen_program rng) with
    | Ok _ -> true
    | Error e ->
        Printf.eprintf "[stack-jit-fuzz] replay seed=%d program rejected: %s\n" seed e;
        false
  in
  let rng = Random.State.make [| seed |] in
  let soup = List.init (Random.State.int rng 25) (fun _ -> any_op rng) in
  ok_diff && ok_prog
  && robust_case ~seed ~label:"replay-default" ~allow_branches:false soup
  && robust_case ~seed ~label:"replay-branches" ~allow_branches:true soup

let test_regression_replay () =
  let pin_ok =
    List.for_all
      (fun (name, ops) ->
         if run_differential ~seed:0 ops then true
         else begin
           Printf.eprintf "[stack-jit-fuzz] regression pin failed: %s\n  ops=[%s]\n"
             name (trace_to_string ops);
           false
         end)
      pin_traces
  in
  let halt_ok =
    match C.translate_program () (pin_program ()) with
    | Error e ->
        Printf.eprintf "[stack-jit-fuzz] halt-pin program rejected: %s\n" e;
        false
    | Ok tr ->
        let n = List.length tr.chunks in
        let jmps =
          List.filter
            (fun (op, _, _, _) -> suffix op = "JMP")
            (List.concat tr.chunks)
        in
        let halt_encoded =
          match jmps with
          | [ (_, _, _, imm) ] -> Int64.to_int imm = n
          | _ -> false
        in
        if not halt_encoded then
          Printf.eprintf
            "[stack-jit-fuzz] halt-pin: expected JMP -> n_chunks=%d, got %d jump(s)\n"
            n (List.length jmps);
        halt_encoded
  in
  let extra =
    match Sys.getenv_opt "SJIT_FUZZ_REPLAY" with
    | Some s when String.trim s <> "" ->
        List.map (fun x -> int_of_string (String.trim x)) (String.split_on_char ',' s)
    | _ -> []
  in
  let bad =
    List.filter (fun seed -> not (replay_seed seed)) (regression_seeds @ extra)
  in
  Alcotest.(check bool) "regression pins green" true pin_ok;
  Alcotest.(check bool) "past-the-end halt pin green" true halt_ok;
  Alcotest.(check bool) "replay seeds green" true (bad = []);
  if bad <> [] then
    Printf.eprintf "[stack-jit-fuzz] replay failed for seeds: %s\n"
      (String.concat ", " (List.map string_of_int bad))

let tests =
  List.map QCheck_alcotest.to_alcotest [ prop_differential; prop_program; prop_robustness ]
  @ [ Alcotest.test_case "stack_jit_fuzz_regression_replay" `Quick test_regression_replay ]
