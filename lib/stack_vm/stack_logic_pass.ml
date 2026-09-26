open Stack_ir

type logic_basis =
  | Basis_NOR
  | Basis_NAND
  | Basis_Random

let expand_not_nor = [
  Dup;
  Nor;
]

let expand_or_nor = [
  Nor;
  Dup;
  Nor;
]

let expand_and_nor = [
  Swap;
  Dup;
  Nor; (* ~y *)
  Swap;
  Dup;
  Nor; (* ~x *)
  Nor; (* ~x NOR ~y = x AND y *)
]

let expand_xor_nor scratch_x scratch_y = [
  PopReg scratch_x;
  PopReg scratch_y;
  PushReg scratch_y;
  Dup;
  Nor; (* ~y *)
  PushReg scratch_x;
  Dup;
  Nor; (* ~x *)
  Nor; (* x AND y *)
  PushReg scratch_y;
  PushReg scratch_x;
  Nor; (* x NOR y *)
  Nor; (* (x AND y) NOR (x NOR y) = x XOR y *)
]

let expand_not_nand = [
  Dup;
  Nand;
]

let expand_and_nand = [
  Nand;
  Dup;
  Nand;
]

let expand_or_nand = [
  Swap;
  Dup;
  Nand; (* ~y *)
  Swap;
  Dup;
  Nand; (* ~x *)
  Nand; (* ~x NAND ~y = x OR y *)
]

let expand_xor_nand scratch_x scratch_y scratch_n1 = [
  PopReg scratch_x;
  PopReg scratch_y;
  PushReg scratch_y;
  PushReg scratch_x;
  Nand;
  PopReg scratch_n1; (* n1 = x NAND y *)
  PushReg scratch_n1;
  PushReg scratch_x;
  Nand;              (* n2 = x NAND n1 *)
  PushReg scratch_n1;
  PushReg scratch_y;
  Nand;              (* n3 = y NAND n1 *)
  Nand;              (* n2 NAND n3 = x XOR y *)
]

let transform_block ?(basis = Basis_NOR) ?(seed = 0x42) _ctx block =
  let rng = Random.State.make [| seed + block.id |] in
  let current_basis = match basis with
    | Basis_NOR -> Basis_NOR
    | Basis_NAND -> Basis_NAND
    | Basis_Random -> if Random.State.bool rng then Basis_NOR else Basis_NAND
  in
  let new_ops = List.fold_left (fun acc op ->
    match op with
    | Nor when current_basis = Basis_NAND ->
        (* NOR via NAND: NOT (x OR y) *)
        expand_or_nand @ expand_not_nand @ acc
    | Nand when current_basis = Basis_NOR ->
        (* NAND via NOR: NOT (x AND y) *)
        expand_and_nor @ expand_not_nor @ acc
    | other -> other :: acc
  ) [] block.ops |> List.rev in
  { block with ops = new_ops }

let transform_program ?(basis = Basis_NOR) ?(seed = 0x42) ctx prog =
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  Hashtbl.iter (fun id b ->
    let transformed = transform_block ~basis ~seed ctx b in
    Hashtbl.replace new_blocks id transformed
  ) prog.blocks;
  { prog with blocks = new_blocks; context_slots = Context_allocator.total_slots ctx }
