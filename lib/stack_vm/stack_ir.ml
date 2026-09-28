open Vm_ir
open Flags

type stack_op =
  | PushImm of int64
  | PushReg of int
  | PopReg of int
  | ReadMem of int
  | WriteMem of int
  | Add
  | Sub
  | Mul
  | Nor
  | Nand
  | Shl
  | Shr
  | Sar
  | Div
  | Idiv
  | Dup
  | Swap
  | PushFlags
  | PopFlags
  | JmpRel of int
  | JccRel of int * condition
  | KeyAdjust of int64
  | Exit
  | CallExtern of int
  | ResolveSym of int
  | Setcc of condition
  | Cmov of condition * int
  | Cmp
  | Test
  | AddImm of int64
  | SubImm of int64
  | AddImmImm of int64 * int64
  | SubImmImm of int64 * int64
  | SetRegImm of int * int64
  | AddRegImm of int * int64

type block = {
  id : int;
  label : string;
  ops : stack_op list;
}

type program = {
  entry_id : int;
  blocks : (int, block) Hashtbl.t;
  context_slots : int;
}

let push_weight = function
  | PushImm _ -> 1
  | PushReg _ -> 1
  | PopReg _ -> 0
  | ReadMem _ -> 1
  | WriteMem _ -> 0
  | Add | Sub | Mul | Nor | Nand | Shl | Shr | Sar | Div | Idiv -> 1
  | Dup -> 2
  | Swap -> 2
  | PushFlags -> 1
  | PopFlags -> 0
  | JmpRel _ | JccRel _ | KeyAdjust _ | Exit -> 0
  | CallExtern _ -> 0
  | ResolveSym _ -> 1
  | Setcc _ -> 1
  | Cmov _ -> 0
  | Cmp -> 0
  | Test -> 0
  | AddImm _ | SubImm _ -> 1
  | AddImmImm _ | SubImmImm _ | AddRegImm _ -> 1
  | SetRegImm _ -> 0

let pop_weight = function
  | PushImm _ -> 0
  | PushReg _ -> 0
  | PopReg _ -> 1
  | ReadMem _ -> 1
  | WriteMem _ -> 2
  | Add | Sub | Mul | Nor | Nand | Shl | Shr | Sar | Div | Idiv -> 2
  | Dup -> 1
  | Swap -> 2
  | PushFlags -> 0
  | PopFlags -> 1
  | JmpRel _ | JccRel _ | KeyAdjust _ | Exit -> 0
  | CallExtern _ -> 0
  | ResolveSym _ -> 0
  | Setcc _ -> 0
  | Cmov _ -> 1
  | Cmp -> 2
  | Test -> 2
  | AddImm _ | SubImm _ -> 1
  | AddImmImm _ | SubImmImm _ | AddRegImm _ -> 0
  | SetRegImm _ -> 0

let stack_delta op =
  push_weight op - pop_weight op

let op_to_string = function
  | PushImm v -> Printf.sprintf "PUSH_IMM 0x%Lx" v
  | PushReg idx -> Printf.sprintf "PUSH_REG [ctx+%d]" idx
  | PopReg idx -> Printf.sprintf "POP_REG [ctx+%d]" idx
  | ReadMem w -> Printf.sprintf "READ_MEM (size=%d)" w
  | WriteMem w -> Printf.sprintf "WRITE_MEM (size=%d)" w
  | Add -> "ADD"
  | Sub -> "SUB"
  | Mul -> "MUL"
  | Nor -> "NOR"
  | Nand -> "NAND"
  | Shl -> "SHL"
  | Shr -> "SHR"
  | Sar -> "SAR"
  | Div -> "DIV"
  | Idiv -> "IDIV"
  | Dup -> "DUP"
  | Swap -> "SWAP"
  | PushFlags -> "PUSH_FLAGS"
  | PopFlags -> "POP_FLAGS"
  | JmpRel b -> Printf.sprintf "JMP_REL block_%d" b
  | JccRel (b, c) -> Printf.sprintf "JCC_REL block_%d (cond=%s)" b (Flags.condition_to_string c)
  | KeyAdjust delta -> Printf.sprintf "KEY_ADJUST 0x%Lx" delta
  | Exit -> "EXIT"
  | CallExtern idx -> Printf.sprintf "CALL_EXTERN sym_%d" idx
  | ResolveSym idx -> Printf.sprintf "RESOLVE_SYM sym_%d" idx
  | Setcc c -> Printf.sprintf "SETCC %s" (Flags.condition_to_string c)
  | Cmov (c, idx) -> Printf.sprintf "CMOV %s [ctx+%d]" (Flags.condition_to_string c) idx
  | Cmp -> "CMP"
  | Test -> "TEST"
  | AddImm c -> Printf.sprintf "ADD_IMM 0x%Lx" c
  | SubImm c -> Printf.sprintf "SUB_IMM 0x%Lx" c
  | AddImmImm (a, b) -> Printf.sprintf "ADD_II 0x%Lx, 0x%Lx" a b
  | SubImmImm (a, b) -> Printf.sprintf "SUB_II 0x%Lx, 0x%Lx" a b
  | SetRegImm (idx, v) -> Printf.sprintf "SET_REG_IMM [ctx+%d], 0x%Lx" idx v
  | AddRegImm (idx, c) -> Printf.sprintf "ADD_REG_IMM [ctx+%d], 0x%Lx" idx c

let block_to_string b =
  let ops_str = List.map (fun op -> "    " ^ op_to_string op) b.ops |> String.concat "\n" in
  Printf.sprintf "%s (id=%d):\n%s" b.label b.id ops_str

let program_to_string prog =
  let header = Printf.sprintf "StackProgram (entry=%d, context_slots=%d):\n" prog.entry_id prog.context_slots in
  let blocks_list = Hashtbl.fold (fun _ b acc -> b :: acc) prog.blocks []
                    |> List.sort (fun a b -> compare a.id b.id) in
  let b_strs = List.map block_to_string blocks_list in
  header ^ String.concat "\n" b_strs

let make_block id label ops =
  { id; label; ops }

let make_program entry_id block_list context_slots =
  let tbl = Hashtbl.create (List.length block_list) in
  List.iter (fun b -> Hashtbl.replace tbl b.id b) block_list;
  { entry_id; blocks = tbl; context_slots }
