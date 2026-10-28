(* lib/stack_vm/stack_jit_chunker.ml
   ASGARD-5877: Stack JIT VM chunker (SJIT tier-1 lowering)

   Translates a straight-line Stack-IR trace into sealed-ready JIT chunks
   for the RD-JIT native tier (docs/STACK_JIT_VM_PROTOTYPE.md):

   - window layout: context slots [0..7], stack positions [8..15]
     (16-slot window; the top-of-stack suffix lives at 8 + depth);
   - fission by the Kolakoski word (OEIS A000002, run lengths scaled by 2);
   - dummy padding by Thue-Morse parity (OEIS A010060);
   - epilogue moves the final stack top to window slot 0 (the observable
     result register) when the trace ends with a non-empty stack.

   The translatable subset (verified against the handler semantics of
   stack_handlers_emitter.ml): PushImm, PushReg, PopReg, Add, Sub, Mul,
   Nand, Nor, Dup, Swap, AddImm, SubImm, AddImmImm, SubImmImm.  Sub pops
   b then a and pushes a - b; Nand/Nor are the negated binary forms,
   lowered to AND/OR followed by NOT.  Everything else (shifts, division,
   flags, branches, memory, escapes) is rejected with a reason and the
   caller falls back to another engine. *)

open Stack_ir

type jit_item = string * int * int * int64
(* (JIT_OP_* symbol, dst slot, src slot, immediate) *)

type translation = {
  chunks : jit_item list list; (* Kolakoski-fissioned, Thue-Morse padded *)
  final_depth : int;           (* net stack effect of the trace *)
  max_depth : int;             (* live-depth high-water mark *)
  real_instrs : int;           (* emitted instructions, dummies excluded *)
  dummy_instrs : int;          (* Thue-Morse dummies *)
}

let ctx_slots = 8
let stack_base = 8
let max_stack_depth = 8

let op_prefix = "asgard_rd_jit::JIT_OP_"

let jit op = op_prefix ^ op
let nop_item : jit_item = (jit "NOP", 0, 0, 0L)

let unsupported what =
  Error ("stack_jit: unsupported stack op: " ^ what)


(* ---- reference interpreter of the translatable subset ----------- *)

let reference_eval (regs : int64 array) (ops : stack_op list) : int64 list =
  let stk = ref [] in
  List.iter
    (fun op ->
      match op with
      | PushImm v -> stk := v :: !stk
      | PushReg r ->
          let v = if r >= 0 && r < Array.length regs then regs.(r) else 0L in
          stk := v :: !stk
      | PopReg r ->
          (match !stk with
           | v :: tl ->
               if r >= 0 && r < Array.length regs then regs.(r) <- v;
               stk := tl
           | [] -> failwith "stack_jit: stack underflow (reference)")
      | Add ->
          (match !stk with
           | b :: a :: tl -> stk := (Int64.add a b) :: tl
           | _ -> failwith "stack_jit: underflow on Add")
      | Sub ->
          (match !stk with
           | b :: a :: tl -> stk := (Int64.sub a b) :: tl
           | _ -> failwith "stack_jit: underflow on Sub")
      | Mul ->
          (match !stk with
           | b :: a :: tl -> stk := (Int64.mul a b) :: tl
           | _ -> failwith "stack_jit: underflow on Mul")
      | Nand ->
          (match !stk with
           | b :: a :: tl -> stk := Int64.lognot (Int64.logand a b) :: tl
           | _ -> failwith "stack_jit: underflow on Nand")
      | Nor ->
          (match !stk with
           | b :: a :: tl -> stk := Int64.lognot (Int64.logor a b) :: tl
           | _ -> failwith "stack_jit: underflow on Nor")
      | AddImm v ->
          (match !stk with
           | a :: tl -> stk := Int64.add a v :: tl
           | [] -> failwith "stack_jit: underflow on AddImm")
      | SubImm v ->
          (match !stk with
           | a :: tl -> stk := Int64.sub a v :: tl
           | [] -> failwith "stack_jit: underflow on SubImm")
      | AddImmImm (a, b) -> stk := Int64.add a b :: !stk
      | SubImmImm (a, b) -> stk := Int64.sub a b :: !stk
      | PushFlags -> ()
      | PopFlags -> ()
      | Exit -> ()
      | Dup ->
          (match !stk with
           | a :: tl -> stk := a :: a :: tl
           | [] -> failwith "stack_jit: underflow on Dup")
      | Swap ->
          (match !stk with
           | b :: a :: tl -> stk := a :: b :: tl
           | _ -> failwith "stack_jit: underflow on Swap")
      | other -> failwith (Printf.sprintf "stack_jit: reference: %s" (Stack_ir.op_to_string other)))
    ops;
  !stk

(* ---- chunk simulation on the 16-slot window --------------------- *)

let simulate_chunks (chunks : jit_item list list) (gprs : int64 array) : unit =
  Array.fill gprs 0 (Array.length gprs) 0L;
  let suffix op = String.sub op (String.length op_prefix) (String.length op - String.length op_prefix) in
  List.iter
    (fun chunk ->
      List.iter
        (fun (op, dst, src, imm) ->
          match suffix op with
          | "NOP" -> ()
          | "MOV_RR" -> gprs.(dst) <- gprs.(src)
          | "MOV_RI" -> gprs.(dst) <- imm
          | "ADD_RR" -> gprs.(dst) <- Int64.add gprs.(dst) gprs.(src)
          | "ADD_RI" -> gprs.(dst) <- Int64.add gprs.(dst) imm
          | "SUB_RR" -> gprs.(dst) <- Int64.sub gprs.(dst) gprs.(src)
          | "SUB_RI" -> gprs.(dst) <- Int64.sub gprs.(dst) imm
          | "MUL_RR" -> gprs.(dst) <- Int64.mul gprs.(dst) gprs.(src)
          | "MUL_RI" -> gprs.(dst) <- Int64.mul gprs.(dst) imm
          | "AND_RR" -> gprs.(dst) <- Int64.logand gprs.(dst) gprs.(src)
          | "OR_RR" -> gprs.(dst) <- Int64.logor gprs.(dst) gprs.(src)
          | "XOR_RR" -> gprs.(dst) <- Int64.logxor gprs.(dst) gprs.(src)
          | "NOT_R" -> gprs.(dst) <- Int64.lognot gprs.(dst)
          | "EXIT" -> ()
          | s -> failwith ("stack_jit: simulate: unknown op " ^ s))
        chunk)
    chunks

(* ---- translation ------------------------------------------------ *)

let translate_trace ?(scale = Rd_jit_vm.Nano_jit_slot.nano_kolakoski_scale) ()
    (ops : stack_op list) : (translation, string) result =
  let ( let* ) = Result.bind in
  let depth = ref 0 in
  let max_depth = ref 0 in
  let flags_depth = ref 0 in
  let ctx_map = Hashtbl.create 8 in
  let rev_map = Hashtbl.create 8 in
  let map_ctx_slot r =
    if r < 0 then Error (Printf.sprintf "stack_jit: negative context slot %d" r)
    else
      match Hashtbl.find_opt ctx_map r with
      | Some s -> Ok s
      | None ->
          let preferred =
            if r < ctx_slots && not (Hashtbl.mem rev_map r) then Some r
            else None
          in
          let s_opt =
            match preferred with
            | Some s -> Some s
            | None ->
                let rec find s =
                  if s >= ctx_slots then None
                  else if Hashtbl.mem rev_map s then find (s + 1)
                  else Some s
                in
                find 0
          in
          match s_opt with
          | Some s ->
              Hashtbl.replace ctx_map r s;
              Hashtbl.replace rev_map s r;
              Ok s
          | None ->
              Error (Printf.sprintf "stack_jit: trace uses too many distinct context slots (limit is %d)" ctx_slots)
  in
  let out = ref [] in
  let push_item item = out := item :: !out in
  let grow () =
    incr depth;
    if !depth > max_stack_depth then
      Error (Printf.sprintf "stack_jit: live depth %d exceeds the %d-slot stack window"
               !depth max_stack_depth)
    else (
      if !depth > !max_depth then max_depth := !depth;
      Ok ()
    )
  in
  let binary op =
    if !depth < 2 then Error ("stack_jit: underflow on " ^ op)
    else begin
      (* stack semantics: pops b (top), pops a (deeper), pushes a OP b;
         2-address form: dst = slot of a = stack_base + depth - 2. *)
      push_item (jit op, stack_base + !depth - 2, stack_base + !depth - 1, 0L);
      decr depth;
      Ok ()
    end
  in
  let rec walk = function
    | [] -> Ok ()
    | op :: rest ->
        let res =
          match op with
          | PushImm v ->
              let* () = grow () in
              push_item (jit "MOV_RI", stack_base + !depth - 1, 0, v);
              Ok ()
          | PushReg r ->
              let* s = map_ctx_slot r in
              let* () = grow () in
              push_item (jit "MOV_RR", stack_base + !depth - 1, s, 0L);
              Ok ()
          | PopReg r ->
              if !depth < 1 then Error "stack_jit: underflow on PopReg"
              else begin
                let* s = map_ctx_slot r in
                push_item (jit "MOV_RR", s, stack_base + !depth - 1, 0L);
                decr depth;
                Ok ()
              end
          | Add -> binary "ADD_RR"
          | Sub -> binary "SUB_RR"
          | Mul -> binary "MUL_RR"
          | Nand ->
              (* res = ~(a & b): AND then NOT, in place on a's slot. *)
              let* () = binary "AND_RR" in
              push_item (jit "NOT_R", stack_base + !depth - 1, 0, 0L);
              Ok ()
          | Nor ->
              let* () = binary "OR_RR" in
              push_item (jit "NOT_R", stack_base + !depth - 1, 0, 0L);
              Ok ()
          | AddImm v ->
              if !depth < 1 then Error "stack_jit: underflow on AddImm"
              else begin
                push_item (jit "ADD_RI", stack_base + !depth - 1, 0, v);
                Ok ()
              end
          | SubImm v ->
              if !depth < 1 then Error "stack_jit: underflow on SubImm"
              else begin
                push_item (jit "SUB_RI", stack_base + !depth - 1, 0, v);
                Ok ()
              end
          | AddImmImm (a, b) ->
              let* () = grow () in
              push_item (jit "MOV_RI", stack_base + !depth - 1, 0, Int64.add a b);
              Ok ()
          | SubImmImm (a, b) ->
              let* () = grow () in
              push_item (jit "MOV_RI", stack_base + !depth - 1, 0, Int64.sub a b);
              Ok ()
          | Dup ->
              if !depth < 1 then Error "stack_jit: underflow on Dup"
              else begin
                let* () = grow () in
                push_item (jit "MOV_RR", stack_base + !depth - 1, stack_base + !depth - 2, 0L);
                Ok ()
              end
          | Swap ->
              if !depth < 2 then Error "stack_jit: underflow on Swap"
              else begin
                (* a = top-1 slot, b = top slot; free temp = slot above top. *)
                let a = stack_base + !depth - 2
                and b = stack_base + !depth - 1
                and t = stack_base + !depth in
                push_item (jit "MOV_RR", t, b, 0L);
                push_item (jit "MOV_RR", b, a, 0L);
                push_item (jit "MOV_RR", a, t, 0L);
                Ok ()
              end
          | PushFlags ->
              incr flags_depth;
              Ok ()
          | PopFlags ->
              if !flags_depth <= 0 then Error "stack_jit: unbalanced PopFlags"
              else begin
                decr flags_depth;
                Ok ()
              end
          | Exit ->
              push_item (jit "EXIT", 0, 0, 0L);
              Ok ()
          | other -> unsupported (Stack_ir.op_to_string other)
        in
        match res with
        | Error e -> Error e
        | Ok () -> walk rest
  in
  let* () = walk ops in
  let* () =
    if !flags_depth <> 0 then Error "stack_jit: unclosed PushFlags at end of trace"
    else Ok ()
  in
  (* Epilogue: the observable result is the stack top, moved to slot 0. *)
  (if !depth > 0 then
     push_item (jit "MOV_RR", 0, stack_base + !depth - 1, 0L));
  let real = List.rev !out in
  (* OEIS A010060: dummy at output position n iff t_n = 1. *)
  let padded =
    let pos = ref 0 in
    let acc = ref [] in
    List.iter
      (fun item ->
        if Rd_jit_vm.Nano_jit_slot.thue_morse !pos then begin
          acc := nop_item :: !acc;
          incr pos
        end;
        acc := item :: !acc;
        incr pos)
      real;
    List.rev !acc
  in
  let dummies = List.length padded - List.length real in
  (* OEIS A000002: chunk targets are Kolakoski run lengths scaled by 2. *)
  let kolakoski_word = Rd_jit_vm.Nano_jit_slot.kolakoski 256 in
  let cap = Rd_jit_vm.Nano_jit_slot.nano_max_chunk_instrs in
  let chunks =
    let run_idx = ref 0 in
    let cur = ref [] in
    let acc = ref [] in
    let flush () =
      if !cur <> [] then begin
        acc := List.rev !cur :: !acc;
        cur := [];
        incr run_idx
      end
    in
    List.iter
      (fun item ->
        let target =
          kolakoski_word.(!run_idx mod Array.length kolakoski_word) * scale
        in
        if List.length !cur >= target || List.length !cur >= cap then flush ();
        Stdlib.(cur := item :: !cur))
      padded;
    flush ();
    List.rev !acc
  in
  Ok { chunks; final_depth = !depth; max_depth = !max_depth;
       real_instrs = List.length real; dummy_instrs = dummies }
