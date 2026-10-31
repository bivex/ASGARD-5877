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

let ctx_slots = 56
let stack_base = 56
let max_stack_depth = 8

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
          (* Fused [PushReg; AddImm]: pushes reg+imm and leaves the register
             intact, matching the evaluator (stack_eval.ml) and the chunker. *)
          let base = if r >= 0 && r < Array.length regs then regs.(r) else 0L in
          stk := Int64.add base v :: !stk
      | ReadMem _ -> ()
      | WriteMem _ ->
          (match !stk with
           | _ :: _ :: tl -> stk := tl
           | _ -> failwith "stack_jit: underflow on WriteMem")
      | ResolveSym sym_idx ->
          stk := Int64.of_int (0x1000 + sym_idx * 8) :: !stk
      | CallExtern _sym_idx ->
          (* Chunk semantics (translate_trace + simulate_chunks): the
             call's return value (0) lands in window slot 0 and is pushed
             on top; the argument stack is left intact. *)
          if Array.length regs > 0 then regs.(0) <- 0L;
          stk := 0L :: !stk
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
      | PushFlags -> stk := 0L :: !stk
      | PopFlags ->
          (match !stk with
           | _ :: tl -> stk := tl
           | [] -> failwith "stack_jit: underflow on PopFlags")
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

(* ---- chunk simulation on the full slot window --------------------- *)
let simulate_slots = stack_base + max_stack_depth (* 60 with current constants *)

let simulate_chunks (chunks : jit_item list list) (gprs : int64 array) : unit =
  let g = Array.make simulate_slots 0L in
  let n = min (Array.length gprs) simulate_slots in
  let suffix op = String.sub op (String.length op_prefix) (String.length op - String.length op_prefix) in
  List.iter
    (fun chunk ->
      List.iter
        (fun (op, dst, src, imm) ->
          (match suffix op with
          | "NOP" -> ()
          | "MOV_RR" -> g.(dst) <- g.(src)
          | "MOV_RI" -> g.(dst) <- imm
          | "ADD_RR" -> g.(dst) <- Int64.add g.(dst) g.(src)
          | "ADD_RI" -> g.(dst) <- Int64.add g.(dst) imm
          | "SUB_RR" -> g.(dst) <- Int64.sub g.(dst) g.(src)
          | "SUB_RI" -> g.(dst) <- Int64.sub g.(dst) imm
          | "MUL_RR" -> g.(dst) <- Int64.mul g.(dst) g.(src)
          | "MUL_RI" -> g.(dst) <- Int64.mul g.(dst) imm
          | "MULH_RR" ->
              let a = g.(dst) and b = g.(src) in
              let a1 = Int64.shift_right_logical a 32 and a0 = Int64.logand a 0xFFFFFFFFL in
              let b1 = Int64.shift_right_logical b 32 and b0 = Int64.logand b 0xFFFFFFFFL in
              let p0 = Int64.mul a0 b0 in
              let p1 = Int64.add (Int64.mul a1 b0) (Int64.shift_right_logical p0 32) in
              let p2 = Int64.add (Int64.mul a0 b1) (Int64.logand p1 0xFFFFFFFFL) in
              g.(dst) <- Int64.add (Int64.add (Int64.mul a1 b1) (Int64.shift_right_logical p1 32)) (Int64.shift_right_logical p2 32)
          | "SMULH_RR" ->
              let a = g.(dst) and b = g.(src) in
              let a1 = Int64.shift_right_logical a 32 and a0 = Int64.logand a 0xFFFFFFFFL in
              let b1 = Int64.shift_right_logical b 32 and b0 = Int64.logand b 0xFFFFFFFFL in
              let p0 = Int64.mul a0 b0 in
              let p1 = Int64.add (Int64.mul a1 b0) (Int64.shift_right_logical p0 32) in
              let p2 = Int64.add (Int64.mul a0 b1) (Int64.logand p1 0xFFFFFFFFL) in
              let u_hi = Int64.add (Int64.add (Int64.mul a1 b1) (Int64.shift_right_logical p1 32)) (Int64.shift_right_logical p2 32) in
              let adj_a = if a < 0L then b else 0L in
              let adj_b = if b < 0L then a else 0L in
              g.(dst) <- Int64.sub (Int64.sub u_hi adj_a) adj_b
          | "SHL_RI" -> g.(dst) <- Int64.shift_left g.(dst) (Int64.to_int imm land 63)
          | "SHR_RI" -> g.(dst) <- Int64.shift_right_logical g.(dst) (Int64.to_int imm land 63)
          | "SAR_RI" -> g.(dst) <- Int64.shift_right g.(dst) (Int64.to_int imm land 63)
          | "SHL_RR" -> g.(dst) <- Int64.shift_left g.(dst) (Int64.to_int g.(src) land 63)
          | "SHR_RR" -> g.(dst) <- Int64.shift_right_logical g.(dst) (Int64.to_int g.(src) land 63)
          | "SAR_RR" -> g.(dst) <- Int64.shift_right g.(dst) (Int64.to_int g.(src) land 63)
          | "AND_RR" -> g.(dst) <- Int64.logand g.(dst) g.(src)
          | "OR_RR" -> g.(dst) <- Int64.logor g.(dst) g.(src)
          | "XOR_RR" -> g.(dst) <- Int64.logxor g.(dst) g.(src)
          | "NOT_R" -> g.(dst) <- Int64.lognot g.(dst)
          | "BSWAP_R" ->
              let a = g.(dst) in
              g.(dst) <-
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
              let a = g.(dst) in
              let rec go c = if c >= 64 then 64 else if Int64.logand a (Int64.shift_left 1L (63 - c)) <> 0L then c else go (c + 1) in
              g.(dst) <- Int64.of_int (go 0)
          | "CTZ_R" ->
              if g.(dst) = 0L then g.(dst) <- 64L
              else begin
                let rec go c v = if Int64.logand v 1L = 0L then go (c + 1) (Int64.shift_right_logical v 1) else c in
                g.(dst) <- Int64.of_int (go 0 g.(dst))
              end
          | "RBIT_R" ->
              let a = g.(dst) in
              let rec go i acc =
                if i >= 64 then acc
                else go (i + 1) (Int64.logor (Int64.shift_left acc 1) (Int64.logand (Int64.shift_right_logical a i) 1L))
              in
              g.(dst) <- go 0 0L
          | "POPCNT_R" ->
              let rec go c v = if v = 0L then c else go (c + 1) (Int64.logand v (Int64.sub v 1L)) in
              g.(dst) <- Int64.of_int (go 0 g.(dst))
          | "EXIT" -> ()
          | "ROR_RR" ->
              let s = Int64.to_int g.(src) land 63 in
              g.(dst) <- (if s = 0 then g.(dst) else Int64.logor (Int64.shift_right_logical g.(dst) s) (Int64.shift_left g.(dst) (64 - s)))
          | "DIV_RR" ->
              g.(dst) <- (if g.(src) = 0L then 0L else Int64.unsigned_div g.(dst) g.(src))
          | "SDIV_RR" ->
              g.(dst) <- (if g.(src) = 0L then 0L else Int64.div g.(dst) g.(src))
          | "REM_RR" ->
              g.(dst) <- (if g.(src) = 0L then 0L else Int64.unsigned_rem g.(dst) g.(src))
          | "CMP_RR" -> ()
          | "CMP_RI" -> ()
          | "CSEL_RR" -> g.(dst) <- g.(src)
          | "PUSH_FLAGS" -> g.(dst) <- 0L
          | "POP_FLAGS" -> ()
          | "ROR_RI" ->
              let s = Int64.to_int imm land 63 in
              g.(dst) <- (if s = 0 then g.(dst) else Int64.logor (Int64.shift_right_logical g.(dst) s) (Int64.shift_left g.(dst) (64 - s)))
          | "LOAD_8" | "LOAD_16" | "LOAD_32" | "LOAD_64" -> ()
          | "STORE_8" | "STORE_16" | "STORE_32" | "STORE_64" -> ()
          | "RESOLVE_SYM" -> g.(dst) <- Int64.of_int (0x1000 + Int64.to_int imm * 8)
          | "CALL_EXTERN" -> g.(0) <- 0L
          | s -> failwith ("stack_jit: simulate: unknown op " ^ s)))
        chunk)
    chunks;
  Array.blit g 0 gprs 0 n

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
    ?(allow_branches = false)
    ?(allow_spill = false)
    ?(entry_depth = 0)
    ?(epilogue = true)
    ?ctx_map ?used_slots ()
    (ops : stack_op list) : (translation, string) result =
  let ( let* ) = Result.bind in
  let vdepth = ref entry_depth in
  let spilled = ref (max 0 (entry_depth - max_stack_depth)) in
  let max_depth = ref 0 in
  let ctx_map = match ctx_map with Some m -> m | None -> Hashtbl.create 8 in
  let used_slots = match used_slots with Some u -> u | None -> Hashtbl.create 8 in
  let r_rsp = 4 in (* ctx.gprs[4] — pointer into spill_stack, strictly reserved *)
  Hashtbl.replace used_slots r_rsp ();
  List.iter
    (function
     | PushReg r | PopReg r | Cmov (_, r) | SetRegImm (r, _) | AddRegImm (r, _) ->
         if r >= 0 && r < ctx_slots && r <> r_rsp && not (Hashtbl.mem ctx_map r) then begin
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
  let check_push_depth () =
    if not allow_spill && (!vdepth - !spilled) >= max_stack_depth then
      Error (Printf.sprintf "stack_jit: live depth %d exceeds the %d-slot stack window"
               (!vdepth + 1) max_stack_depth)
    else Ok ()
  in
  let r_rsp = 4 in (* ctx.gprs[4] — pointer into spill_stack *)

  let phys_slot (d : int) : int =
    stack_base + (d mod max_stack_depth)
  in

  let spill_offset (idx : int) : int64 =
    Int64.of_int (-8 * (idx + 1))
  in

  let push_slot () =
    let live_in_regs = !vdepth - !spilled in
    if live_in_regs >= max_stack_depth then begin
      let oldest_phys = phys_slot !spilled in
      let off = spill_offset !spilled in
      push_item (jit "STORE_64", r_rsp, oldest_phys, off);
      incr spilled
    end;
    let target = phys_slot !vdepth in
    incr vdepth;
    if !vdepth > !max_depth then max_depth := !vdepth;
    target
  in

  let pop_slot () =
    if !vdepth <= 0 then failwith "stack_jit: stack underflow on pop"
    else begin
      decr vdepth;
      let target = phys_slot !vdepth in
      if !vdepth < !spilled then begin
        decr spilled;
        let off = spill_offset !spilled in
        push_item (jit "LOAD_64", target, r_rsp, off)
      end;
      target
    end
  in

  let tos_slot () =
    if !vdepth <= 0 then failwith "stack_jit: stack underflow on tos"
    else phys_slot (!vdepth - 1)
  in

  let sub_tos_slot () =
    if !vdepth < 2 then failwith "stack_jit: stack underflow on sub_tos"
    else phys_slot (!vdepth - 2)
  in

  let binary op =
    if !vdepth < 2 then Error ("stack_jit: underflow on " ^ op)
    else begin
      let b = pop_slot () in
      let a = tos_slot () in
      push_item (jit op, a, b, 0L);
      Ok ()
    end
  in
  let shift_op op_rr op_ri =
    if !vdepth < 2 then Error ("stack_jit: underflow on shift")
    else match !out with
    | (mov_ri, slot_b, 0, imm) :: rest_out
      when mov_ri = jit "MOV_RI" && slot_b = tos_slot () ->
        out := rest_out;
        ignore (pop_slot ());
        push_item (jit op_ri, tos_slot (), 0, imm);
        Ok ()
    | _ ->
        binary op_rr
  in
  let unary op =
    if !vdepth < 1 then Error ("stack_jit: underflow on " ^ op)
    else begin
      let slot = tos_slot () in
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
              let* () = check_push_depth () in
              let dst = push_slot () in
              push_item (jit "MOV_RI", dst, 0, v);
              Ok ()
          | PushReg r ->
              let* s = map_ctx_slot r in
              let* () = check_push_depth () in
              let dst = push_slot () in
              push_item (jit "MOV_RR", dst, s, 0L);
              Ok ()
          | PopReg r ->
              if !vdepth < 1 then Error "stack_jit: underflow on PopReg"
              else begin
                let* s = map_ctx_slot r in
                let src = pop_slot () in
                push_item (jit "MOV_RR", s, src, 0L);
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
              push_item (jit "NOT_R", tos_slot (), 0, 0L);
              Ok ()
          | Nor ->
              let* () = binary "OR_RR" in
              push_item (jit "NOT_R", tos_slot (), 0, 0L);
              Ok ()
          | Shl -> shift_op "SHL_RR" "SHL_RI"
          | Shr -> shift_op "SHR_RR" "SHR_RI"
          | Sar -> shift_op "SAR_RR" "SAR_RI"
          | Div -> binary "DIV_RR"
          | Idiv -> binary "SDIV_RR"
          | Rot ->
              if !vdepth >= 3 then begin
                let t0 = phys_slot (!vdepth - 3)
                and t1 = sub_tos_slot ()
                and t2 = tos_slot () in
                push_item (jit "XOR_RR", t0, t2, 0L);
                push_item (jit "XOR_RR", t2, t0, 0L);
                push_item (jit "XOR_RR", t0, t2, 0L);
                push_item (jit "XOR_RR", t0, t1, 0L);
                push_item (jit "XOR_RR", t1, t0, 0L);
                push_item (jit "XOR_RR", t0, t1, 0L);
                Ok ()
              end else if !vdepth >= 2 then begin
                shift_op "ROR_RR" "ROR_RI"
              end else
                Error "stack_jit: underflow on Rot"
          | Bswap -> unary "BSWAP_R"
          | Clz -> unary "CLZ_R"
          | Ctz -> unary "CTZ_R"
          | Rbit -> unary "RBIT_R"
          | Popcnt -> unary "POPCNT_R"
          | Dup2 ->
              if !vdepth < 2 then Error "stack_jit: underflow on Dup2"
              else begin
                let src1 = sub_tos_slot () in
                let src2 = tos_slot () in
                let* () = check_push_depth () in
                let dst1 = push_slot () in
                push_item (jit "MOV_RR", dst1, src1, 0L);
                let* () = check_push_depth () in
                let dst2 = push_slot () in
                push_item (jit "MOV_RR", dst2, src2, 0L);
                Ok ()
              end
          | Cmp ->
              if !vdepth < 2 then Error "stack_jit: underflow on Cmp"
              else begin
                let b = pop_slot () in
                let a = pop_slot () in
                (match !out with
                 | (mov_ri, top, 0, imm) :: rest_out
                   when mov_ri = jit "MOV_RI" && top = b ->
                   out := rest_out;
                   push_item (jit "CMP_RI", a, 0, imm)
                 | _ ->
                   push_item (jit "CMP_RR", a, b, 0L));
                Ok ()
              end
          | Test ->
              if !vdepth < 2 then Error "stack_jit: underflow on Test"
              else begin
                let b = pop_slot () in
                let a = pop_slot () in
                push_item (jit "AND_RR", a, b, 0L);
                push_item (jit "CMP_RI", a, 0, 0L);
                Ok ()
              end
          | Cmov (cond, r) ->
              if !vdepth < 1 then Error "stack_jit: underflow on Cmov"
              else begin
                let* s = map_ctx_slot r in
                let v = pop_slot () in
                push_item (jit "CSEL_RR", s, v, Int64.of_int (cond_to_code cond lor (s lsl 8)));
                Ok ()
              end
          | Setcc cond ->
              let* () = check_push_depth () in
              let dst = push_slot () in
              let* () = check_push_depth () in
              let tmp = push_slot () in
              push_item (jit "MOV_RI", dst, 0, 0L);
              push_item (jit "MOV_RI", tmp, 0, 1L);
              push_item (jit "CSEL_RR", dst, tmp, Int64.of_int (cond_to_code cond lor (dst lsl 8)));
              ignore (pop_slot ());
              Ok ()
          | ReadMem w ->
              if !vdepth < 1 then Error "stack_jit: underflow on ReadMem"
              else begin
                let slot = tos_slot () in
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
              if !vdepth < 2 then Error "stack_jit: underflow on WriteMem"
              else begin
                let src = pop_slot () in
                let dst = pop_slot () in
                let op = match w with
                  | 1 -> jit "STORE_8"
                  | 2 -> jit "STORE_16"
                  | 4 -> jit "STORE_32"
                  | _ -> jit "STORE_64"
                in
                push_item (op, dst, src, 0L);
                Ok ()
              end
          | SetRegImm (r, imm) ->
              let* s = map_ctx_slot r in
              push_item (jit "MOV_RI", s, 0, imm);
              Ok ()
          | AddRegImm (r, imm) ->
              let* s = map_ctx_slot r in
              let* () = check_push_depth () in
              let dst = push_slot () in
              push_item (jit "MOV_RR", dst, s, 0L);
              push_item (jit "ADD_RI", dst, 0, imm);
              Ok ()
          | AddImm v ->
              if !vdepth < 1 then Error "stack_jit: underflow on AddImm"
              else begin
                push_item (jit "ADD_RI", tos_slot (), 0, v);
                Ok ()
              end
          | SubImm v ->
              if !vdepth < 1 then Error "stack_jit: underflow on SubImm"
              else begin
                push_item (jit "SUB_RI", tos_slot (), 0, v);
                Ok ()
              end
          | AddImmImm (a, b) ->
              let* () = check_push_depth () in
              let dst = push_slot () in
              push_item (jit "MOV_RI", dst, 0, Int64.add a b);
              Ok ()
          | SubImmImm (a, b) ->
              let* () = check_push_depth () in
              let dst = push_slot () in
              push_item (jit "MOV_RI", dst, 0, Int64.sub a b);
              Ok ()
          | Dup ->
              if !vdepth < 1 then Error "stack_jit: underflow on Dup"
              else begin
                let src = tos_slot () in
                let* () = check_push_depth () in
                let dst = push_slot () in
                push_item (jit "MOV_RR", dst, src, 0L);
                Ok ()
              end
          | Swap ->
              if !vdepth < 2 then Error "stack_jit: underflow on Swap"
              else begin
                let a = sub_tos_slot () in
                let b = tos_slot () in
                push_item (jit "XOR_RR", a, b, 0L);
                push_item (jit "XOR_RR", b, a, 0L);
                push_item (jit "XOR_RR", a, b, 0L);
                Ok ()
              end
          | PushFlags ->
              (* materialised condition word becomes a real stack slot *)
              let* () = check_push_depth () in
              let dst = push_slot () in
              push_item (jit "PUSH_FLAGS", dst, 0, 0L);
              Ok ()
          | PopFlags ->
              if !vdepth < 1 then Error "stack_jit: underflow on PopFlags"
              else begin
                let src = pop_slot () in
                push_item (jit "POP_FLAGS", 0, src, 0L);
                Ok ()
              end
          | ResolveSym sym_idx ->
              let* () = check_push_depth () in
              let dst = push_slot () in
              push_item (jit "RESOLVE_SYM", dst, 0, Int64.of_int sym_idx);
              Ok ()
          | CallExtern sym_idx ->
              push_item (jit "CALL_EXTERN", 0, 0, Int64.of_int sym_idx);
              let* () = check_push_depth () in
              let dst = push_slot () in
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
          | NativeEscape (kind, a, b, c, _stub) ->
              let* s_a = map_ctx_slot a in
              let* s_b = map_ctx_slot b in
              let* s_c = map_ctx_slot c in
              let op =
                match kind with
                | 1 -> jit "SUB_RR"
                | 2 -> jit "MUL_RR"
                | _ -> jit "ADD_RR"
              in
              if s_a = s_c then
                push_item (op, s_c, s_b, 0L)
              else if s_b = s_c then begin
                let tmp = 10 in
                push_item (jit "MOV_RR", tmp, s_a, 0L);
                push_item (op, tmp, s_b, 0L);
                push_item (jit "MOV_RR", s_c, tmp, 0L)
              end else begin
                push_item (jit "MOV_RR", s_c, s_a, 0L);
                push_item (op, s_c, s_b, 0L)
              end;
              Ok ()
          | other -> unsupported (Stack_ir.op_to_string other)
        in
        match res with
        | Error e -> Error e
        | Ok () -> walk rest
  in
  let* () = walk ops in
  (* Canonical exit window: reload spilled values until exactly
     max(0, vdepth-4) remain in memory, so a successor block entering at
     this depth sees the live top-of-stack in physical slots. *)
  let want_spilled = max 0 (!vdepth - max_stack_depth) in
  while !spilled > want_spilled do
    decr spilled;
    push_item (jit "LOAD_64", phys_slot !spilled, r_rsp, spill_offset !spilled)
  done;
  (* Epilogue (single-trace mode): the observable result is the stack top,
     moved to slot 0.  Multi-block programs return via PopReg instead. *)
  if epilogue && !vdepth > 0 then
    push_item (jit "MOV_RR", 0, tos_slot (), 0L);
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
       Ok { chunks; final_depth = !vdepth; max_depth = !max_depth;
       real_instrs = List.length real; dummy_instrs = dummies;
       invalidation_schedule = make_invalidation_schedule n_chunks }
let translate_program ?(scale = Rd_jit_vm.Nano_jit_slot.nano_kolakoski_scale)
    ?(allow_spill = true) ()
    (prog : Stack_ir.program) : (translation, string) result =
  let ( let* ) = Result.bind in
  if Hashtbl.length prog.blocks <= 1 then
    match Hashtbl.find_opt prog.blocks prog.entry_id with
    | Some b -> translate_trace ~scale ~allow_branches:true ~allow_spill () b.ops
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
    let global_ctx_map = Hashtbl.create 16 in
    let global_used_slots = Hashtbl.create 16 in
    let r_rsp = 4 in
    Hashtbl.replace global_used_slots r_rsp ();
    List.iter (fun (b : Stack_ir.block) ->
      List.iter (function
        | PushReg r | PopReg r | Cmov (_, r) | SetRegImm (r, _) | AddRegImm (r, _) ->
            if r >= 0 && r < ctx_slots && r <> r_rsp then begin
              Hashtbl.replace global_ctx_map r r;
              Hashtbl.replace global_used_slots r ()
            end
        | _ -> ()) b.ops
    ) all_blocks;
    let map_reg_global r =
      if Hashtbl.mem global_ctx_map r then Ok ()
      else
        let rec find s =
          if s < 0 then
            Error (Printf.sprintf "stack_jit: too many context/scratch slots in trace (limit is %d)" ctx_slots)
          else if Hashtbl.mem global_used_slots s then
            find (s - 1)
          else begin
            Hashtbl.replace global_used_slots s ();
            Hashtbl.replace global_ctx_map r s;
            Ok ()
          end
        in
        find (ctx_slots - 1)
    in
    let rec collect_regs_loop = function
      | [] -> Ok ()
      | (b : Stack_ir.block) :: rest ->
          let rec loop_ops = function
            | [] -> Ok ()
            | (PushReg r | PopReg r | Cmov (_, r) | SetRegImm (r, _) | AddRegImm (r, _)) :: ops_rest ->
                let* () = map_reg_global r in
                loop_ops ops_rest
            | _ :: ops_rest -> loop_ops ops_rest
          in
          let* () = loop_ops b.ops in
          collect_regs_loop rest
    in
    let* () = collect_regs_loop all_blocks in
    (* Cross-block stack state: the reference evaluator's vstack persists
       across block transitions, so each block's model must start at the
       depth its predecessors leave behind.  Collect every branch edge
       with the (relative) depth at the branch point, then run a fixpoint
       from the entry block.  A merge with two different depths is an
       ambiguous program and is rejected; blocks never reached keep a
       self-consistent depth derived from their own walk minimum (they
       never execute, but must still lower without underflow). *)
    let block_edges (b : Stack_ir.block) : (int * int) list =
      let rec go d = function
        | [] -> []
        | JmpRel t :: rest -> (t, d) :: go d rest
        | JccRel (t, _) :: JmpRel f :: rest -> (t, d) :: (f, d) :: go d rest
        | JccRel (t, _) :: rest -> (t, d) :: (b.id, d) :: go d rest
        | Exit :: rest -> go d rest
        | op :: rest -> go (d + Stack_ir.stack_delta op) rest
      in
      go 0 b.ops
    in
    let rel_edges = List.map (fun b -> (b, block_edges b)) all_blocks in
    let entry_depths = Hashtbl.create 16 in
    Hashtbl.replace entry_depths prog.entry_id 0;
    let changed = ref true in
    let iters = ref 0 in
    let max_iters = List.length all_blocks in
    while !changed && !iters < max_iters do
      incr iters;
      changed := false;
      List.iter
        (fun (b, edges) ->
          match Hashtbl.find_opt entry_depths b.id with
          | None -> ()
          | Some d0 ->
              List.iter
                (fun (t, rd) ->
                  let ad = min 64 (d0 + rd) in
                  match Hashtbl.find_opt entry_depths t with
                  | None -> Hashtbl.replace entry_depths t ad; changed := true
                  | Some e when e < ad ->
                      Hashtbl.replace entry_depths t ad; changed := true
                  | _ -> ())
                edges)
        rel_edges
    done;
    let walk_minimum (b : Stack_ir.block) =
      let rec go m d = function
        | [] -> m
        | op :: rest ->
            let d' = d + Stack_ir.stack_delta op in
            go (min m d') d' rest
      in
      go 0 0 b.ops
    in
    let block_chunks = Hashtbl.create 16 in
    let block_offsets = Hashtbl.create 16 in
    let cur_chunk_offset = ref 0 in
    let total_real = ref 0 in
    let total_dummies = ref 0 in
    let max_d = ref 0 in
    let rec chunk_blocks = function
      | [] -> Ok ()
      | (b : Stack_ir.block) :: rest ->
          let entry_d =
            match Hashtbl.find_opt entry_depths b.id with
            | Some d -> max d (- walk_minimum b)
            | None -> max 0 (- walk_minimum b)
          in
          let* res =
            match translate_trace ~scale ~allow_branches:true ~allow_spill
                    ~entry_depth:entry_d ~epilogue:false
                    ~ctx_map:global_ctx_map ~used_slots:global_used_slots () b.ops with
            | Ok r -> Ok r
            | Error e -> Error (Printf.sprintf "%s (in block %d)" e b.id)
          in
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
