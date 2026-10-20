open Int64

type chameleon_weights = {
  w_xor  : int64;
  w_and  : int64;
  w_or   : int64;
  w_bias : int64;
}

type target_alu_sem =
  | SemAdd
  | SemSub
  | SemXor
  | SemAnd
  | SemOr

type delayed_pipeline_state = {
  mutable pending_reg  : int;
  mutable pending_val  : int64;
  mutable pending_mask : int64;
  mutable has_pending  : bool;
}

let create_pipeline_state () : delayed_pipeline_state = {
  pending_reg  = 0;
  pending_val  = 0L;
  pending_mask = 0L;
  has_pending  = false;
}

let rand_u64 (rng : Random.State.t) : int64 =
  let hi = Random.State.bits rng |> of_int in
  let mid = Random.State.bits rng |> of_int in
  let lo = Random.State.bits rng |> of_int in
  logor (shift_left hi 34) (logor (shift_left mid 4) (logand lo 0xFL))

(** Mathematical foundation of the Chameleon Handler:
    In the ring Z_{2^64} the fundamental linear identity always holds:
    (x | y) = (x ^ y) + (x & y)  <==>  (x ^ y) + (x & y) - (x | y) == 0!
    Therefore, if the base representation of the operation has the form:
      Op(x, y) = base_xor * (x ^ y) + base_and * (x & y)
    we can choose ANY random 64-bit number r \in Z_{2^64} and set:
      w_or  = r
      w_xor = base_xor - r
      w_and = base_and - r
    Then:
      w_xor*(x^y) + w_and*(x&y) + w_or*(x|y)
      = (base_xor - r)*(x^y) + (base_and - r)*(x&y) + r*((x^y) + (x&y))
      == base_xor*(x^y) + base_and*(x&y) (mod 2^64)!
    This gives 2^64 distinct representations for THE VERY SAME instruction within a single handler! *)
let synth_chameleon_weights (rng : Random.State.t) (sem : target_alu_sem) : chameleon_weights =
  let (base_xor, base_and) = match sem with
    | SemAdd -> (1L, 2L) (* x + y = 1*(x^y) + 2*(x&y) *)
    | SemXor -> (1L, 0L) (* x ^ y = 1*(x^y) + 0*(x&y) *)
    | SemAnd -> (0L, 1L) (* x & y = 0*(x^y) + 1*(x&y) *)
    | SemOr  -> (1L, 1L) (* x | y = 1*(x^y) + 1*(x&y) *)
    | SemSub ->
      (* For the subtraction x - y the handler receives the inverted y' = ~y,
         while the +1 offset is folded into bias: x - y = x + (~y) + 1 *)
      (1L, 2L)
  in
  let r_free = rand_u64 rng in
  let w_or   = r_free in
  let w_xor  = sub base_xor r_free in
  let w_and  = sub base_and r_free in
  let w_bias = rand_u64 rng in
  { w_xor; w_and; w_or; w_bias }

let eval_chameleon_kernel (w : chameleon_weights) (x : int64) (y : int64) : int64 =
  let t_xor = mul w.w_xor (logxor x y) in
  let t_and = mul w.w_and (logand x y) in
  let t_or  = mul w.w_or  (logor  x y) in
  let masked_sum = add (add (add t_xor t_and) t_or) w.w_bias in
  sub masked_sum w.w_bias

let step_delayed_commit_handler
    (st : delayed_pipeline_state)
    (regs : int64 array)
    ~(dst_reg : int)
    ~(new_result : int64)
    ~(next_mask : int64) : unit =
  (* 1. First commit the deferred result of the PREVIOUS virtual instruction (step T-1) *)
  if st.has_pending then begin
    let committed_val = logxor st.pending_val st.pending_mask in
    regs.(st.pending_reg) <- committed_val
  end;
  (* 2. Latch the result of the CURRENT instruction (step T) in masked form into the buffer *)
  st.pending_reg  <- dst_reg;
  st.pending_mask <- next_mask;
  st.pending_val  <- logxor new_result next_mask;
  st.has_pending  <- true

let flush_delayed_commit (st : delayed_pipeline_state) (regs : int64 array) : unit =
  if st.has_pending then begin
    regs.(st.pending_reg) <- logxor st.pending_val st.pending_mask;
    st.has_pending <- false
  end

let emit_chameleon_handlers_hpp (rng : Random.State.t) : string =
  let open Cpp_codegen.Cpp_ast in
  let open Cpp_codegen.Cpp_dsl in

  let chameleon_struct = StructDecl {
    align_as = Some 32;
    name     = "DelayedCommitCtx";
    fields   = [
      (Array (UInt64, 32), "regs");
      (UInt32, "pending_reg");
      (UInt32, "has_pending");
      (UInt64, "pending_val");
      (UInt64, "pending_mask");
    ];
  } in

  (* Universal chameleon core computing any boolean-arithmetic operation *)
  let chameleon_exec_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = "exec_chameleon_delayed_step";
    params   = [
      (Ref (StructType "DelayedCommitCtx"), "ctx");
      (UInt32, "dst_reg");
      (UInt64, "x");
      (UInt64, "y");
      (UInt64, "w_xor");
      (UInt64, "w_and");
      (UInt64, "w_or");
      (UInt64, "next_mask");
    ];
    body     = [
      Comment "1. Commit result of PREVIOUS instruction (T-1) to break single-handler I/O oracle";
      If (ne (Member (var "ctx", "has_pending")) (i32 0), [
        (Index (Member (var "ctx", "regs"), Member (var "ctx", "pending_reg"))) :=
          ((Member (var "ctx", "pending_val")) ^~ (Member (var "ctx", "pending_mask")));
      ], []);
      Comment "2. Evaluate universal polymorphic Chameleon ALU kernel for step T";
      let_u64 "tx" ((var "w_xor") *~ ((var "x") ^~ (var "y")));
      let_u64 "ta" ((var "w_and") *~ ((var "x") &~ (var "y")));
      let_u64 "to" ((var "w_or")  *~ ((var "x") |~ (var "y")));
      let_u64 "res" (((var "tx") +~ (var "ta")) +~ (var "to"));
      Comment "3. Latch masked result into delayed pipeline queue for step T+1";
      (Member (var "ctx", "pending_reg"))  := (var "dst_reg");
      (Member (var "ctx", "pending_mask")) := (var "next_mask");
      (Member (var "ctx", "pending_val"))  := ((var "res") ^~ (var "next_mask"));
      (Member (var "ctx", "has_pending"))  := (i32 1);
    ];
  } in

  let flush_fn = FuncDecl {
    attrs    = [AlwaysInline; NoExcept];
    ret_type = Void;
    name     = "flush_chameleon_pipeline";
    params   = [(Ref (StructType "DelayedCommitCtx"), "ctx")];
    body     = [
      If (ne (Member (var "ctx", "has_pending")) (i32 0), [
        (Index (Member (var "ctx", "regs"), Member (var "ctx", "pending_reg"))) :=
          ((Member (var "ctx", "pending_val")) ^~ (Member (var "ctx", "pending_mask")));
        (Member (var "ctx", "has_pending")) := (i32 0);
      ], []);
    ];
  } in

  let ast = [
    IncludeSys "cstdint";
    Namespace ("asgard::chameleon_vm", [
      chameleon_struct;
      chameleon_exec_fn;
      flush_fn;
    ]);
  ] in
  let scrambled = List.map (Cpp_codegen.Cpp_ast_obf.scramble_top_decl rng) ast in
  Cpp_codegen.Cpp_printer.render_header_unit scrambled
