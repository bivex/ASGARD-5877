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
}

type operand =
  | Reg of Register.t
  | Imm of int64
  | Mem of mem_ref

type target =
  | Label of string
  | BlockId of int
  | TargetImm of int64

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

let mem_ref_to_string m =
  let size_prefix = match m.width with
    | B8 -> "byte ptr "
    | B16 -> "word ptr "
    | B32 -> "dword ptr "
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
