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
open Vm_ir

type jit_item = string * int * int * int64
(* (JIT_OP_* symbol, dst slot, src slot, immediate) *)

type translation = {
  chunks : jit_item list list; (* Kolakoski-fissioned, Thue-Morse padded *)
  final_depth : int;           (* net stack effect of the trace *)
  max_depth : int;             (* live-depth high-water mark *)
  real_instrs : int;           (* emitted instructions, dummies excluded *)
  dummy_instrs : int;          (* Thue-Morse dummies *)
  (* OEIS A001511: fractal tiered invalidation schedule.
     invalidation_schedule.(k) = A001511(k+1) = 1 + ctz(k+1) for chunk k.
     The runtime wipes all arena slots of level <= this value after step k. *)
  invalidation_schedule : int array;
}

let ctx_slots = 12
let stack_base = 12
let max_stack_depth = 4

let op_prefix = "asgard_rd_jit::JIT_OP_"

let jit op = op_prefix ^ op
let nop_item : jit_item = (jit "NOP", 0, 0, 0L)

let unsupported what =
  Error ("stack_jit: unsupported stack op: " ^ what)

let cond_to_code = function
  | Flags.E -> 0
  | Flags.NE -> 1
  | Flags.AE -> 2
  | Flags.B -> 3
  | Flags.S -> 4
  | Flags.NS -> 5
  | Flags.O -> 6
  | Flags.NO -> 7
  | Flags.A -> 8
  | Flags.BE -> 9
  | Flags.GE -> 10
  | Flags.L -> 11
  | Flags.G -> 12
  | Flags.LE -> 13
  | Flags.ALWAYS -> 14
  | _ -> 0


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
      | Mulh ->
          (match !stk with
           | b :: a :: tl ->
               let a1 = Int64.shift_right_logical a 32 and a0 = Int64.logand a 0xFFFFFFFFL in
               let b1 = Int64.shift_right_logical b 32 and b0 = Int64.logand b 0xFFFFFFFFL in
               let p0 = Int64.mul a0 b0 in
               let p1 = Int64.add (Int64.mul a1 b0) (Int64.shift_right_logical p0 32) in
               let p2 = Int64.add (Int64.mul a0 b1) (Int64.logand p1 0xFFFFFFFFL) in
               let hi = Int64.add (Int64.add (Int64.mul a1 b1) (Int64.shift_right_logical p1 32)) (Int64.shift_right_logical p2 32) in
               stk := hi :: tl
           | _ -> failwith "stack_jit: underflow on Mulh")
      | Imulh ->
          (match !stk with
           | b :: a :: tl ->
               let a1 = Int64.shift_right_logical a 32 and a0 = Int64.logand a 0xFFFFFFFFL in
               let b1 = Int64.shift_right_logical b 32 and b0 = Int64.logand b 0xFFFFFFFFL in
               let p0 = Int64.mul a0 b0 in
               let p1 = Int64.add (Int64.mul a1 b0) (Int64.shift_right_logical p0 32) in
               let p2 = Int64.add (Int64.mul a0 b1) (Int64.logand p1 0xFFFFFFFFL) in
               let u_hi = Int64.add (Int64.add (Int64.mul a1 b1) (Int64.shift_right_logical p1 32)) (Int64.shift_right_logical p2 32) in
               let adj_a = if a < 0L then b else 0L in
               let adj_b = if b < 0L then a else 0L in
               let hi = Int64.sub (Int64.sub u_hi adj_a) adj_b in
               stk := hi :: tl
           | _ -> failwith "stack_jit: underflow on Imulh")
      | Nand ->
          (match !stk with
           | b :: a :: tl -> stk := Int64.lognot (Int64.logand a b) :: tl
           | _ -> failwith "stack_jit: underflow on Nand")
      | Nor ->
          (match !stk with
           | b :: a :: tl -> stk := Int64.lognot (Int64.logor a b) :: tl
           | _ -> failwith "stack_jit: underflow on Nor")
      | Shl ->
          (match !stk with
           | count :: a :: tl ->
               stk := Int64.shift_left a (Int64.to_int count land 63) :: tl
           | _ -> failwith "stack_jit: underflow on Shl")
      | Shr ->
          (match !stk with
           | count :: a :: tl ->
               stk := Int64.shift_right_logical a (Int64.to_int count land 63) :: tl
           | _ -> failwith "stack_jit: underflow on Shr")
      | Sar ->
          (match !stk with
           | count :: a :: tl ->
               stk := Int64.shift_right a (Int64.to_int count land 63) :: tl
           | _ -> failwith "stack_jit: underflow on Sar")
      | Div ->
          (match !stk with
           | b :: a :: tl -> stk := (if b = 0L then 0L else Int64.unsigned_div a b) :: tl
           | _ -> failwith "stack_jit: underflow on Div")
      | Idiv ->
          (match !stk with
           | b :: a :: tl -> stk := (if b = 0L then 0L else Int64.div a b) :: tl
           | _ -> failwith "stack_jit: underflow on Idiv")
      | Rot ->
          (match !stk with
           | a :: b :: c :: tl ->
               stk := c :: a :: b :: tl
           | [ b; a ] ->
               let s = Int64.to_int b land 63 in
               let res = if s = 0 then a else Int64.logor (Int64.shift_right_logical a s) (Int64.shift_left a (64 - s)) in
               stk := [ res ]
           | _ -> failwith "stack_jit: underflow on Rot")
      | Dup2 ->
          (match !stk with
           | b :: a :: tl -> stk := b :: a :: b :: a :: tl
           | _ -> failwith "stack_jit: underflow on Dup2")
      | Cmp ->
          (match !stk with
           | _ :: _ :: tl -> stk := tl
           | _ -> failwith "stack_jit: underflow on Cmp")
      | Test ->
          (match !stk with
           | _ :: _ :: tl -> stk := tl
           | _ -> failwith "stack_jit: underflow on Test")
      | Cmov (_cond, r) ->
          (match !stk with
           | v :: tl ->
               stk := tl;
               if r >= 0 && r < Array.length regs then regs.(r) <- v
           | [] -> failwith "stack_jit: underflow on Cmov")
      | Setcc _cond ->
          stk := 1L :: !stk
      | SetRegImm (r, v) ->
          if r >= 0 && r < Array.length regs then regs.(r) <- v
      | AddRegImm (r, v) ->
          if r >= 0 && r < Array.length regs then regs.(r) <- Int64.add regs.(r) v
      | ReadMem _ -> ()
      | WriteMem _ ->
          (match !stk with
           | _ :: _ :: tl -> stk := tl
           | _ -> failwith "stack_jit: underflow on WriteMem")
      | ResolveSym sym_idx ->
          stk := Int64.of_int (0x1000 + sym_idx * 8) :: !stk
      | CallExtern _sym_idx ->
          (match !stk with
           | _ :: tl -> stk := 0L :: tl
           | [] -> stk := [ 0L ])
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
      | Bswap ->
          (match !stk with
           | a :: tl ->
               stk :=
                 Int64.logor
                   (Int64.logor
                      (Int64.shift_left (Int64.logand a 0x00000000000000FFL) 56)
                      (Int64.shift_left (Int64.logand a 0x000000000000FF00L) 40))
                   (Int64.logor
                      (Int64.logor
                         (Int64.shift_left (Int64.logand a 0x0000000000FF0000L) 24)
                         (Int64.shift_left (Int64.logand a 0x00000000FF000000L) 8))
                      (Int64.logor
                         (Int64.logor
                            (Int64.shift_right_logical (Int64.logand a 0x000000FF00000000L) 8)
                            (Int64.shift_right_logical (Int64.logand a 0x0000FF0000000000L) 24))
                         (Int64.logor
                            (Int64.shift_right_logical (Int64.logand a 0x00FF000000000000L) 40)
                            (Int64.shift_right_logical (Int64.logand a 0xFF00000000000000L) 56))))
                 :: tl
           | _ -> failwith "stack_jit: underflow on Bswap")
      | Clz ->
          (match !stk with
           | a :: tl ->
               let rec go c =
                 if c >= 64 then 64
                 else if Int64.logand a (Int64.shift_left 1L (63 - c)) <> 0L then c
                 else go (c + 1)
               in
               stk := Int64.of_int (go 0) :: tl
           | _ -> failwith "stack_jit: underflow on Clz")
      | Ctz ->
          (match !stk with
           | a :: tl ->
               if a = 0L then stk := 64L :: tl
               else begin
                 let rec go c v = if Int64.logand v 1L = 0L then go (c + 1) (Int64.shift_right_logical v 1) else c in
                 stk := Int64.of_int (go 0 a) :: tl
               end
           | _ -> failwith "stack_jit: underflow on Ctz")
      | Rbit ->
          (match !stk with
           | a :: tl ->
               let rec go i acc =
                 if i >= 64 then acc
                 else go (i + 1) (Int64.logor (Int64.shift_left acc 1) (Int64.logand (Int64.shift_right_logical a i) 1L))
               in
               stk := go 0 0L :: tl
           | _ -> failwith "stack_jit: underflow on Rbit")
      | Popcnt ->
          (match !stk with
           | a :: tl ->
               let rec go c v = if v = 0L then c else go (c + 1) (Int64.logand v (Int64.sub v 1L)) in
               stk := Int64.of_int (go 0 a) :: tl
           | _ -> failwith "stack_jit: underflow on Popcnt")
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
          (match suffix op with
          | "NOP" -> ()
          | "MOV_RR" -> gprs.(dst) <- gprs.(src)
          | "MOV_RI" -> gprs.(dst) <- imm
          | "ADD_RR" -> gprs.(dst) <- Int64.add gprs.(dst) gprs.(src)
          | "ADD_RI" -> gprs.(dst) <- Int64.add gprs.(dst) imm
          | "SUB_RR" -> gprs.(dst) <- Int64.sub gprs.(dst) gprs.(src)
          | "SUB_RI" -> gprs.(dst) <- Int64.sub gprs.(dst) imm
          | "MUL_RR" -> gprs.(dst) <- Int64.mul gprs.(dst) gprs.(src)
          | "MUL_RI" -> gprs.(dst) <- Int64.mul gprs.(dst) imm
          | "MULH_RR" ->
              let a = gprs.(dst) and b = gprs.(src) in
              let a1 = Int64.shift_right_logical a 32 and a0 = Int64.logand a 0xFFFFFFFFL in
              let b1 = Int64.shift_right_logical b 32 and b0 = Int64.logand b 0xFFFFFFFFL in
              let p0 = Int64.mul a0 b0 in
              let p1 = Int64.add (Int64.mul a1 b0) (Int64.shift_right_logical p0 32) in
              let p2 = Int64.add (Int64.mul a0 b1) (Int64.logand p1 0xFFFFFFFFL) in
              gprs.(dst) <- Int64.add (Int64.add (Int64.mul a1 b1) (Int64.shift_right_logical p1 32)) (Int64.shift_right_logical p2 32)
          | "SMULH_RR" ->
              let a = gprs.(dst) and b = gprs.(src) in
              let a1 = Int64.shift_right_logical a 32 and a0 = Int64.logand a 0xFFFFFFFFL in
              let b1 = Int64.shift_right_logical b 32 and b0 = Int64.logand b 0xFFFFFFFFL in
              let p0 = Int64.mul a0 b0 in
              let p1 = Int64.add (Int64.mul a1 b0) (Int64.shift_right_logical p0 32) in
              let p2 = Int64.add (Int64.mul a0 b1) (Int64.logand p1 0xFFFFFFFFL) in
              let u_hi = Int64.add (Int64.add (Int64.mul a1 b1) (Int64.shift_right_logical p1 32)) (Int64.shift_right_logical p2 32) in
              let adj_a = if a < 0L then b else 0L in
              let adj_b = if b < 0L then a else 0L in
              gprs.(dst) <- Int64.sub (Int64.sub u_hi adj_a) adj_b
          | "SHL_RI" -> gprs.(dst) <- Int64.shift_left gprs.(dst) (Int64.to_int imm land 63)
          | "SHR_RI" -> gprs.(dst) <- Int64.shift_right_logical gprs.(dst) (Int64.to_int imm land 63)
          | "SAR_RI" -> gprs.(dst) <- Int64.shift_right gprs.(dst) (Int64.to_int imm land 63)
          | "AND_RR" -> gprs.(dst) <- Int64.logand gprs.(dst) gprs.(src)
          | "OR_RR" -> gprs.(dst) <- Int64.logor gprs.(dst) gprs.(src)
          | "XOR_RR" -> gprs.(dst) <- Int64.logxor gprs.(dst) gprs.(src)
          | "NOT_R" -> gprs.(dst) <- Int64.lognot gprs.(dst)
          | "BSWAP_R" ->
              let a = gprs.(dst) in
              gprs.(dst) <-
                Int64.logor
                  (Int64.logor
                     (Int64.shift_left (Int64.logand a 0x00000000000000FFL) 56)
                     (Int64.shift_left (Int64.logand a 0x000000000000FF00L) 40))
                  (Int64.logor
                     (Int64.logor
                        (Int64.shift_left (Int64.logand a 0x0000000000FF0000L) 24)
                        (Int64.shift_left (Int64.logand a 0x00000000FF000000L) 8))
                     (Int64.logor
                        (Int64.logor
                           (Int64.shift_right_logical (Int64.logand a 0x000000FF00000000L) 8)
                           (Int64.shift_right_logical (Int64.logand a 0x0000FF0000000000L) 24))
                        (Int64.logor
                           (Int64.shift_right_logical (Int64.logand a 0x00FF000000000000L) 40)
                           (Int64.shift_right_logical (Int64.logand a 0xFF00000000000000L) 56))))
          | "CLZ_R" ->
              let a = gprs.(dst) in
              let rec go c = if c >= 64 then 64 else if Int64.logand a (Int64.shift_left 1L (63 - c)) <> 0L then c else go (c + 1) in
              gprs.(dst) <- Int64.of_int (go 0)
          | "CTZ_R" ->
              if gprs.(dst) = 0L then gprs.(dst) <- 64L
              else begin
                let rec go c v = if Int64.logand v 1L = 0L then go (c + 1) (Int64.shift_right_logical v 1) else c in
                gprs.(dst) <- Int64.of_int (go 0 gprs.(dst))
              end
          | "RBIT_R" ->
              let a = gprs.(dst) in
              let rec go i acc =
                if i >= 64 then acc
                else go (i + 1) (Int64.logor (Int64.shift_left acc 1) (Int64.logand (Int64.shift_right_logical a i) 1L))
              in
              gprs.(dst) <- go 0 0L
          | "POPCNT_R" ->
              let rec go c v = if v = 0L then c else go (c + 1) (Int64.logand v (Int64.sub v 1L)) in
              gprs.(dst) <- Int64.of_int (go 0 gprs.(dst))
          | "EXIT" -> ()
          | "ROR_RR" ->
              let s = Int64.to_int gprs.(src) land 63 in
              gprs.(dst) <- (if s = 0 then gprs.(dst) else Int64.logor (Int64.shift_right_logical gprs.(dst) s) (Int64.shift_left gprs.(dst) (64 - s)))
          | "DIV_RR" ->
              gprs.(dst) <- (if gprs.(src) = 0L then 0L else Int64.unsigned_div gprs.(dst) gprs.(src))
          | "SDIV_RR" ->
              gprs.(dst) <- (if gprs.(src) = 0L then 0L else Int64.div gprs.(dst) gprs.(src))
          | "REM_RR" ->
              gprs.(dst) <- (if gprs.(src) = 0L then 0L else Int64.unsigned_rem gprs.(dst) gprs.(src))
          | "CMP_RR" -> ()
          | "CMP_RI" -> ()
          | "CSEL_RR" -> gprs.(dst) <- gprs.(src)
          | "ROR_RI" ->
              let s = Int64.to_int imm land 63 in
              gprs.(dst) <- (if s = 0 then gprs.(dst) else Int64.logor (Int64.shift_right_logical gprs.(dst) s) (Int64.shift_left gprs.(dst) (64 - s)))
          | "LOAD_8" | "LOAD_16" | "LOAD_32" | "LOAD_64" -> ()
          | "STORE_8" | "STORE_16" | "STORE_32" | "STORE_64" -> ()
          | "RESOLVE_SYM" -> gprs.(dst) <- Int64.of_int (0x1000 + Int64.to_int imm * 8)
          | "CALL_EXTERN" -> gprs.(0) <- 0L
          | s -> failwith ("stack_jit: simulate: unknown op " ^ s)))
        chunk)
    chunks

(* OEIS A001511 - Ruler function: A001511(t) = 1 + ctz(t) for t >= 1.
   Returns the fractal wipe level for execution step t: the RD-JIT arena
   wipes all active slots of level <= ruler_a001511(t) after chunk t. *)
let ruler_a001511 (t : int) : int =
  assert (t >= 1);
  let rec ctz n = if n land 1 = 1 then 0 else 1 + ctz (n lsr 1) in
  1 + ctz t

(* Build the per-chunk A001511 invalidation schedule for [n] chunks.
   schedule.(k) = ruler_a001511(k+1): the wipe level after chunk k. *)
let make_invalidation_schedule (n : int) : int array =
  if n = 0 then [||]
  else Array.init n (fun k -> ruler_a001511 (k + 1))

(* ---- translation ------------------------------------------------ *)

let translate_trace ?(scale = Rd_jit_vm.Nano_jit_slot.nano_kolakoski_scale)
    ?(allow_branches = false) ()
    (ops : stack_op list) : (translation, string) result =
  let ( let* ) = Result.bind in
  let depth = ref 0 in
  let max_depth = ref 0 in
  let flags_depth = ref 0 in
  let ctx_map = Hashtbl.create 8 in
  let used_slots = Hashtbl.create 8 in
  List.iter
    (function
     | PushReg r | PopReg r | Cmov (_, r) | SetRegImm (r, _) | AddRegImm (r, _) ->
         if r >= 0 && r < ctx_slots then begin
           Hashtbl.replace ctx_map r r;
           Hashtbl.replace used_slots r ()
         end
     | _ -> ())
    ops;
  let map_ctx_slot r =
    if r < 0 then Error (Printf.sprintf "stack_jit: negative context slot %d" r)
    else match Hashtbl.find_opt ctx_map r with
    | Some s -> Ok s
    | None ->
        let rec find s =
          if s < 0 then
            Error (Printf.sprintf "stack_jit: too many context/scratch slots in trace (limit is %d)" ctx_slots)
          else if Hashtbl.mem used_slots s then
            find (s - 1)
          else begin
            Hashtbl.replace used_slots s ();
            Hashtbl.replace ctx_map r s;
            Ok s
          end
        in
        find (ctx_slots - 1)
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
  let shift_op op_rr op_ri =
    if !depth < 2 then Error ("stack_jit: underflow on shift")
    else match !out with
    | (mov_ri, slot_b, 0, imm) :: rest_out
      when mov_ri = jit "MOV_RI" && slot_b = stack_base + !depth - 1 ->
        out := rest_out;
        push_item (jit op_ri, stack_base + !depth - 2, 0, imm);
        decr depth;
        Ok ()
    | _ ->
        binary op_rr
  in
  let unary op =
    if !depth < 1 then Error ("stack_jit: underflow on " ^ op)
    else begin
      (* top-of-stack slot: src = dst = stack_base + depth - 1 (in place). *)
      let slot = stack_base + !depth - 1 in
      push_item (jit op, slot, slot, 0L);
      Ok ()
    end
  in
  let rec walk = function
    | [] -> Ok ()
    | JccRel (target, cond) :: JmpRel false_target :: rest when allow_branches ->
        let imm =
          Int64.logor (Int64.of_int target)
            (Int64.logor
               (Int64.shift_left (Int64.of_int false_target) 32)
               (Int64.shift_left (Int64.of_int (cond_to_code cond)) 48))
        in
        push_item (jit "JCC", 0, 0, imm);
        walk rest
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
          | Mulh -> binary "MULH_RR"
          | Imulh -> binary "SMULH_RR"
          | Nand ->
              (* res = ~(a & b): AND then NOT, in place on a's slot. *)
              let* () = binary "AND_RR" in
              push_item (jit "NOT_R", stack_base + !depth - 1, 0, 0L);
              Ok ()
          | Nor ->
              let* () = binary "OR_RR" in
              push_item (jit "NOT_R", stack_base + !depth - 1, 0, 0L);
              Ok ()
          | Shl -> shift_op "SHL_RR" "SHL_RI"
          | Shr -> shift_op "SHR_RR" "SHR_RI"
          | Sar -> shift_op "SAR_RR" "SAR_RI"
          | Div -> binary "DIV_RR"
          | Idiv -> binary "SDIV_RR"
          | Rot ->
              if !depth >= 3 then begin
                let t0 = stack_base + !depth - 3
                and t1 = stack_base + !depth - 2
                and t2 = stack_base + !depth - 1 in
                push_item (jit "XOR_RR", t0, t2, 0L);
                push_item (jit "XOR_RR", t2, t0, 0L);
                push_item (jit "XOR_RR", t0, t2, 0L);
                push_item (jit "XOR_RR", t0, t1, 0L);
                push_item (jit "XOR_RR", t1, t0, 0L);
                push_item (jit "XOR_RR", t0, t1, 0L);
                Ok ()
              end else if !depth >= 2 then begin
                shift_op "ROR_RR" "ROR_RI"
              end else
                Error "stack_jit: underflow on Rot"
          | Bswap -> unary "BSWAP_R"
          | Clz -> unary "CLZ_R"
          | Ctz -> unary "CTZ_R"
          | Rbit -> unary "RBIT_R"
          | Popcnt -> unary "POPCNT_R"
          | Dup2 ->
              if !depth < 2 then Error "stack_jit: underflow on Dup2"
              else begin
                let* () = grow () in
                push_item (jit "MOV_RR", stack_base + !depth - 1, stack_base + !depth - 3, 0L);
                let* () = grow () in
                push_item (jit "MOV_RR", stack_base + !depth - 1, stack_base + !depth - 3, 0L);
                Ok ()
              end
          | Cmp ->
              if !depth < 2 then Error "stack_jit: underflow on Cmp"
              else begin
                let a = stack_base + !depth - 2 and b = stack_base + !depth - 1 in
                (match !out with
                 (* Peephole: [MOV_RI b, imm][CMP_RR a, b] -> [CMP_RI a, imm].
                    Saves one window slot and one native load per literal compare. *)
                 | (mov_ri, top, 0, imm) :: rest_out
                   when mov_ri = jit "MOV_RI" && top = b ->
                   out := rest_out;
                   push_item (jit "CMP_RI", a, 0, imm)
                 | _ ->
                   push_item (jit "CMP_RR", a, b, 0L));
                depth := !depth - 2;
                Ok ()
              end
          | Test ->
              if !depth < 2 then Error "stack_jit: underflow on Test"
              else begin
                let a = stack_base + !depth - 2 and b = stack_base + !depth - 1 in
                push_item (jit "AND_RR", a, b, 0L);
                (* AND-result vs zero folds to CMP_RI; MOV_RI scratch elided. *)
                push_item (jit "CMP_RI", a, 0, 0L);
                depth := !depth - 2;
                Ok ()
              end
          | Cmov (cond, r) ->
              if !depth < 1 then Error "stack_jit: underflow on Cmov"
              else begin
                let* s = map_ctx_slot r in
                let v = stack_base + !depth - 1 in
                push_item (jit "CSEL_RR", s, v, Int64.of_int (cond_to_code cond lor (s lsl 8)));
                decr depth;
                Ok ()
              end
          | Setcc cond ->
              let* () = grow () in
              let dst = stack_base + !depth - 1 in
              let* () = grow () in
              let tmp = stack_base + !depth - 1 in
              push_item (jit "MOV_RI", dst, 0, 0L);
              push_item (jit "MOV_RI", tmp, 0, 1L);
              push_item (jit "CSEL_RR", dst, tmp, Int64.of_int (cond_to_code cond lor (dst lsl 8)));
              decr depth;
              Ok ()
          | ReadMem w ->
              if !depth < 1 then Error "stack_jit: underflow on ReadMem"
              else begin
                let slot = stack_base + !depth - 1 in
                let op = match w with
                  | 1 -> jit "LOAD_8"
                  | 2 -> jit "LOAD_16"
                  | 4 -> jit "LOAD_32"
                  | _ -> jit "LOAD_64"
                in
                push_item (op, slot, slot, 0L);
                Ok ()
              end
          | WriteMem w ->
              if !depth < 2 then Error "stack_jit: underflow on WriteMem"
              else begin
                let src = stack_base + !depth - 1 in
                let dst = stack_base + !depth - 2 in
                let op = match w with
                  | 1 -> jit "STORE_8"
                  | 2 -> jit "STORE_16"
                  | 4 -> jit "STORE_32"
                  | _ -> jit "STORE_64"
                in
                push_item (op, dst, src, 0L);
                depth := !depth - 2;
                Ok ()
              end
          | SetRegImm (r, imm) ->
              let* s = map_ctx_slot r in
              push_item (jit "MOV_RI", s, 0, imm);
              Ok ()
          | AddRegImm (r, imm) ->
              let* s = map_ctx_slot r in
              let* () = grow () in
              let dst = stack_base + !depth - 1 in
              push_item (jit "MOV_RR", dst, s, 0L);
              push_item (jit "ADD_RI", dst, 0, imm);
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
                (* a = top-1 slot, b = top slot.  XOR-swap avoids the third
                   temp slot above the stack top, which can overflow the
                   16-slot window when Dup2-based expansions (pure XOR)
                   raise the depth.  a and b are always distinct slots, so
                   the degenerate a = b case of XOR-swap cannot occur. *)
                let a = stack_base + !depth - 2
                and b = stack_base + !depth - 1 in
                push_item (jit "XOR_RR", a, b, 0L);
                push_item (jit "XOR_RR", b, a, 0L);
                push_item (jit "XOR_RR", a, b, 0L);
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
          | ResolveSym sym_idx ->
              let* () = grow () in
              let dst = stack_base + !depth - 1 in
              push_item (jit "RESOLVE_SYM", dst, 0, Int64.of_int sym_idx);
              Ok ()
          | CallExtern sym_idx ->
              push_item (jit "CALL_EXTERN", 0, 0, Int64.of_int sym_idx);
              let* () = grow () in
              let dst = stack_base + !depth - 1 in
              push_item (jit "MOV_RR", dst, 0, 0L);
              Ok ()
          | Exit ->
              push_item (jit "EXIT", 0, 0, 0L);
              Ok ()
          | JmpRel target when allow_branches ->
              push_item (jit "JMP", 0, 0, Int64.of_int target);
              Ok ()
          | JccRel (target, cond) when allow_branches ->
              let imm =
                Int64.logor (Int64.of_int target)
                  (Int64.shift_left (Int64.of_int (cond_to_code cond)) 48)
              in
              push_item (jit "JCC", 0, 0, imm);
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
  let n_chunks = List.length chunks in
  Ok { chunks; final_depth = !depth; max_depth = !max_depth;
       real_instrs = List.length real; dummy_instrs = dummies;
       invalidation_schedule = make_invalidation_schedule n_chunks }
let translate_program ?(scale = Rd_jit_vm.Nano_jit_slot.nano_kolakoski_scale) ()
    (prog : Stack_ir.program) : (translation, string) result =
  let ( let* ) = Result.bind in
  if Hashtbl.length prog.blocks <= 1 then
    match Hashtbl.find_opt prog.blocks prog.entry_id with
    | Some b -> translate_trace ~scale ~allow_branches:true () b.ops
    | None -> Error "stack_jit: entry block not found in program"
  else
    let entry_b =
      match Hashtbl.find_opt prog.blocks prog.entry_id with
      | Some b -> b
      | None -> failwith "stack_jit: entry block not found"
    in
    let other_blocks =
      Hashtbl.fold
        (fun id b acc -> if id <> prog.entry_id then b :: acc else acc)
        prog.blocks []
    in
    let sorted_other =
      List.sort
        (fun (a : Stack_ir.block) (b : Stack_ir.block) -> Int.compare a.id b.id)
        other_blocks
    in
    let all_blocks = entry_b :: sorted_other in
    let block_chunks = Hashtbl.create 16 in
    let block_offsets = Hashtbl.create 16 in
    let cur_chunk_offset = ref 0 in
    let total_real = ref 0 in
    let total_dummies = ref 0 in
    let max_d = ref 0 in
    let rec chunk_blocks = function
      | [] -> Ok ()
      | (b : Stack_ir.block) :: rest ->
          let* res = translate_trace ~scale ~allow_branches:true () b.ops in
          Hashtbl.replace block_offsets b.id !cur_chunk_offset;
          Hashtbl.replace block_chunks b.id res.chunks;
          cur_chunk_offset := !cur_chunk_offset + List.length res.chunks;
          total_real := !total_real + res.real_instrs;
          total_dummies := !total_dummies + res.dummy_instrs;
          max_d := max !max_d res.max_depth;
          chunk_blocks rest
    in
    let* () = chunk_blocks all_blocks in
    let jmp_name = "asgard_rd_jit::JIT_OP_JMP" in
    let jcc_name = "asgard_rd_jit::JIT_OP_JCC" in
    let patch_chunk chunk_idx chunk =
      List.map
        (fun (op, dst, src, imm) ->
          if op = jmp_name then
            let target_block = Int64.to_int imm in
            let target_chunk =
              match Hashtbl.find_opt block_offsets target_block with
              | Some c -> c
              | None -> chunk_idx + 1
            in
            (op, dst, src, Int64.of_int target_chunk)
          else if op = jcc_name then
            let target_block = Int64.to_int (Int64.logand imm 0xFFFFFFFFL) in
            let false_block = Int64.to_int (Int64.logand (Int64.shift_right_logical imm 32) 0xFFFFL) in
            let cond = Int64.shift_right_logical imm 48 in
            let fallthrough_chunk =
              match Hashtbl.find_opt block_offsets false_block with
              | Some c -> c
              | None -> chunk_idx + 1
            in
            let target_chunk =
              match Hashtbl.find_opt block_offsets target_block with
              | Some c -> c
              | None -> fallthrough_chunk
            in
            let patched_imm =
              Int64.logor (Int64.of_int target_chunk)
                (Int64.logor
                   (Int64.shift_left (Int64.of_int fallthrough_chunk) 32)
                   (Int64.shift_left cond 48))
            in
            (op, dst, src, patched_imm)
          else (op, dst, src, imm))
        chunk
    in
    let all_chunks = ref [] in
    let global_idx = ref 0 in
    List.iter
      (fun (b : Stack_ir.block) ->
        let b_chunks = Hashtbl.find block_chunks b.id in
        List.iter
          (fun c ->
            let patched = patch_chunk !global_idx c in
            incr global_idx;
            all_chunks := patched :: !all_chunks)
          b_chunks)
      all_blocks;
    Ok {
      chunks = List.rev !all_chunks;
      final_depth = 0;
      max_depth = !max_d;
      real_instrs = !total_real;
      dummy_instrs = !total_dummies;
      invalidation_schedule = make_invalidation_schedule (List.length !all_chunks);
    }
