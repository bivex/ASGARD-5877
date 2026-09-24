open Register
open Flags

type alu_op =
  | Add
  | Adc
  | Sub
  | Sbb
  | And
  | Or
  | Xor
  | Shl
  | Shr
  | Sar
  | Rol
  | Ror
  | Mul
  | Imul
  | Div
  | Idiv

type unary_op =
  | Not
  | Neg
  | Inc
  | Dec

type mem_ref = {
  base : Register.t option;
  index : (Register.t * int) option;
  disp : int64;
  width : width;
  is_signed : bool;
}

type operand =
  | Reg of Register.t
  | Imm of int64
  | Mem of mem_ref

type target =
  | Label of string
  | BlockId of int
  | TargetImm of int64

type fp_binop = Fadd | Fsub | Fmul | Fdiv
type fp_conv = Fcvtzs | Scvtf
type vec_op = Vadd | Vsub | Vmul | Vand | Vor | Vxor
type vec_elem = VInt | VF32 | VF64
type atomic_op = AtLoad | AtStore | AtCas | AtAdd | AtSwp

type instr =
  | Nop
  | Mov of { dst : operand; src : operand }
  | Lea of { dst : Register.t; addr : mem_ref }
  | Push of operand
  | Pop of operand
  | Xchg of operand * operand
  | Alu of { op : alu_op; dst : Register.t; src1 : operand; src2 : operand; set_flags : bool }
  | Unary of { op : unary_op; dst : Register.t; src : operand; set_flags : bool }
  | Cmp of { src1 : operand; src2 : operand }
  | Test of { src1 : operand; src2 : operand }
  | Jmp of target
  | Jcc of { cond : condition; target_true : target; target_false : target }
  | Call of target
  | Ret
  | Setcc of { cond : condition; dst : operand }
  | Cmov of { cond : condition; dst : Register.t; src : operand }
  | Vm_enter
  | Vm_exit
  | Trap of string
  | Bridge_to_flow of int64
  | Bridge_to_math of int64
  | Load_symbol of { dst : Register.t; sym : string; addend : int64 }
  | Fp_binop of { op : fp_binop; dst : int; src1 : int; src2 : int }
  | Fp_cmp of { src1 : int; src2 : int }
  | Fp_conv of { op : fp_conv; dst : Register.t; src : Register.t }
  | Vec_mov of { dst : int; src : int; bits : int }
  | Vec_binop of { op : vec_op; elem : vec_elem; dst : int; src1 : int; src2 : int; bits : int; lane_bits : int }
  | Vec_load of { dst : int; addr : mem_ref; bits : int }
  | Vec_store of { src : int; addr : mem_ref; bits : int }
  | Atomic_mem of { op : atomic_op; dst : Register.t; addr : Register.t; src : Register.t; imm : int64 }

type basic_block = {
  id : int;
  label : string;
  instrs : instr list;
}

type cfg = {
  entry_id : int;
  blocks : (int, basic_block) Hashtbl.t;
}

type func = {
  name : string;
  cfg : cfg;
}

let alu_op_to_string = function
  | Add -> "add" | Adc -> "adc" | Sub -> "sub" | Sbb -> "sbb"
  | And -> "and" | Or -> "or"   | Xor -> "xor"
  | Shl -> "shl" | Shr -> "shr" | Sar -> "sar"
  | Rol -> "rol" | Ror -> "ror"
  | Mul -> "mul" | Imul -> "imul" | Div -> "div" | Idiv -> "idiv"

let unary_op_to_string = function
  | Not -> "not" | Neg -> "neg" | Inc -> "inc" | Dec -> "dec"

let vec_elem_to_string = function
  | VInt -> "int"
  | VF32 -> "f32"
  | VF64 -> "f64"

let mem_ref_to_string m =
  let size_prefix = match m.width with
    | B8 -> if m.is_signed then "sbyte ptr " else "byte ptr "
    | B16 -> if m.is_signed then "sword ptr " else "word ptr "
    | B32 -> if m.is_signed then "sdword ptr " else "dword ptr "
    | B64 -> "qword ptr "
  in
  let parts = ref [] in
  (match m.base with
  | Some b -> parts := Register.to_string b :: !parts
  | None -> ());
  (match m.index with
  | Some (idx, scale) ->
      let idx_str =
        if scale = 1 then Register.to_string idx
        else Printf.sprintf "%s*%d" (Register.to_string idx) scale
      in
      parts := idx_str :: !parts
  | None -> ());
  if m.disp <> 0L || !parts = [] then begin
    let disp_str =
      if !parts = [] then Printf.sprintf "0x%LX" m.disp
      else if m.disp > 0L then Printf.sprintf "+ 0x%LX" m.disp
      else Printf.sprintf "- 0x%LX" (Int64.neg m.disp)
    in
    parts := disp_str :: !parts
  end;
  let body = String.concat " + " (List.rev !parts) in
  Printf.sprintf "%s[%s]" size_prefix body

let operand_to_string = function
  | Reg r -> Register.to_string r
  | Imm i -> Printf.sprintf "0x%LX" i
  | Mem m -> mem_ref_to_string m

let target_to_string = function
  | Label l -> l
  | BlockId id -> Printf.sprintf "BB_%d" id
  | TargetImm i -> Printf.sprintf "0x%LX" i

let instr_to_string = function
  | Nop -> "nop"
  | Mov { dst; src } -> Printf.sprintf "mov %s, %s" (operand_to_string dst) (operand_to_string src)
  | Lea { dst; addr } -> Printf.sprintf "lea %s, %s" (Register.to_string dst) (mem_ref_to_string addr)
  | Push op -> Printf.sprintf "push %s" (operand_to_string op)
  | Pop op -> Printf.sprintf "pop %s" (operand_to_string op)
  | Xchg (a, b) -> Printf.sprintf "xchg %s, %s" (operand_to_string a) (operand_to_string b)
  | Alu { op; dst; src1; src2; set_flags } ->
      let s_flags = if set_flags then "" else " [no_flags]" in
      Printf.sprintf "%s %s, %s, %s%s" (alu_op_to_string op) (Register.to_string dst)
        (operand_to_string src1) (operand_to_string src2) s_flags
  | Unary { op; dst; src; set_flags } ->
      let s_flags = if set_flags then "" else " [no_flags]" in
      Printf.sprintf "%s %s, %s%s" (unary_op_to_string op) (Register.to_string dst)
        (operand_to_string src) s_flags
  | Cmp { src1; src2 } -> Printf.sprintf "cmp %s, %s" (operand_to_string src1) (operand_to_string src2)
  | Test { src1; src2 } -> Printf.sprintf "test %s, %s" (operand_to_string src1) (operand_to_string src2)
  | Jmp t -> Printf.sprintf "jmp %s" (target_to_string t)
  | Jcc { cond; target_true; target_false } ->
      Printf.sprintf "j%s %s, else %s" (condition_to_string cond) (target_to_string target_true) (target_to_string target_false)
  | Call t -> Printf.sprintf "call %s" (target_to_string t)
  | Ret -> "ret"
  | Setcc { cond; dst } -> Printf.sprintf "set%s %s" (condition_to_string cond) (operand_to_string dst)
  | Cmov { cond; dst; src } ->
      Printf.sprintf "cmov%s %s, %s" (condition_to_string cond) (Register.to_string dst) (operand_to_string src)
  | Vm_enter -> "vm_enter"
  | Vm_exit -> "vm_exit"
  | Trap msg -> Printf.sprintf "trap \"%s\"" msg
  | Bridge_to_flow d -> Printf.sprintf "bridge_to_flow 0x%LX" d
  | Bridge_to_math d -> Printf.sprintf "bridge_to_math 0x%LX" d
  | Load_symbol { dst; sym; addend } ->
      Printf.sprintf "load_sym %s, %s + 0x%LX" (Register.to_string dst) sym addend
  | Fp_binop { op; dst; src1; src2 } ->
      let op_s = match op with Fadd -> "fadd" | Fsub -> "fsub" | Fmul -> "fmul" | Fdiv -> "fdiv" in
      Printf.sprintf "%s d%d, d%d, d%d" op_s dst src1 src2
  | Fp_cmp { src1; src2 } ->
      Printf.sprintf "fcmp d%d, d%d" src1 src2
  | Fp_conv { op; dst; src } ->
      let op_s = match op with Fcvtzs -> "fcvtzs" | Scvtf -> "scvtf" in
      Printf.sprintf "%s %s, %s" op_s (Register.to_string dst) (Register.to_string src)
  | Vec_mov { dst; src; bits } -> Printf.sprintf "vec_mov.%d v%d, v%d" bits dst src
  | Vec_binop { op; elem; dst; src1; src2; bits; lane_bits } ->
      let op_s = match op with Vadd -> "vec_add" | Vsub -> "vec_sub" | Vmul -> "vec_mul" | Vand -> "vec_and" | Vor -> "vec_or" | Vxor -> "vec_xor" in
      Printf.sprintf "%s.%d.%d.%s v%d, v%d, v%d" op_s bits lane_bits (vec_elem_to_string elem) dst src1 src2
  | Vec_load { dst; addr; bits } -> Printf.sprintf "vec_load.%d v%d, %s" bits dst (mem_ref_to_string addr)
  | Vec_store { src; addr; bits } -> Printf.sprintf "vec_store.%d v%d, %s" bits src (mem_ref_to_string addr)
  | Atomic_mem { op; dst; addr; src; imm } ->
      let op_s = match op with AtLoad -> "at_load" | AtStore -> "at_store" | AtCas -> "at_cas" | AtAdd -> "at_add" | AtSwp -> "at_swp" in
      Printf.sprintf "%s %s, [%s + 0x%LX], %s" op_s (Register.to_string dst) (Register.to_string addr) imm (Register.to_string src)

let block_to_string b =
  let b_lines = List.map (fun i -> "    " ^ instr_to_string i) b.instrs in
  Printf.sprintf "%s (id=%d):\n%s" b.label b.id (String.concat "\n" b_lines)

let func_to_string f =
  let b_ids = Hashtbl.fold (fun id _ acc -> id :: acc) f.cfg.blocks [] in
  let sorted_ids = List.sort Int.compare b_ids in
  let b_strs =
    List.map
      (fun id ->
        match Hashtbl.find_opt f.cfg.blocks id with
        | Some b -> block_to_string b
        | None -> "")
      sorted_ids
  in
  Printf.sprintf "func @%s (entry=%d):\n%s" f.name f.cfg.entry_id (String.concat "\n\n" b_strs)

let make_block ~id ~label ~instrs = { id; label; instrs }

let make_func ~name ~entry_id ~blocks =
  let tbl = Hashtbl.create (List.length blocks) in
  List.iter (fun (b : basic_block) -> Hashtbl.replace tbl b.id b) blocks;
  { name; cfg = { entry_id; blocks = tbl } }

let get_block (cfg : cfg) id = Hashtbl.find_opt cfg.blocks id

let successors (b : basic_block) =
  match List.rev b.instrs with
  | [] -> []
  | last :: _ -> (
      match last with
      | Jmp t -> [ t ]
      | Jcc { target_true; target_false; _ } -> [ target_true; target_false ]
      | Call t -> [ t ]
      | Ret | Vm_exit | Trap _ -> []
      | _ -> [])
