open Ir

type verify_error =
  | MissingEntryBlock of int
  | InvalidJumpTarget of int * string
  | MissingTerminator of int
  | EmptyBlock of int
  | InvalidRegisterWidth of Register.t * string

let error_to_string = function
  | MissingEntryBlock id -> Printf.sprintf "Verification Error: Entry block %d does not exist" id
  | InvalidJumpTarget (id, tgt) -> Printf.sprintf "Verification Error: Block %d has unresolved target '%s'" id tgt
  | MissingTerminator id -> Printf.sprintf "Verification Error: Block %d lacks a valid control-flow terminator" id
  | EmptyBlock id -> Printf.sprintf "Verification Error: Block %d is empty" id
  | InvalidRegisterWidth (r, msg) -> Printf.sprintf "Verification Error: Register %s invalid width: %s" (Register.to_string r) msg

let is_terminator = function
  | Jmp _ | Jcc _ | Call _ | Ret | Vm_exit | Trap _ -> true
  | _ -> false

let verify_block (cfg : cfg) (b : basic_block) : (unit, verify_error) result =
  if b.instrs = [] then Error (EmptyBlock b.id)
  else
    let last_instr = List.hd (List.rev b.instrs) in
    if not (is_terminator last_instr) then Error (MissingTerminator b.id)
    else
      let check_target = function
        | BlockId id ->
            if Hashtbl.mem cfg.blocks id then Ok ()
            else Error (InvalidJumpTarget (b.id, Printf.sprintf "BlockId(%d)" id))
        | Label lbl ->
            let exists = Hashtbl.fold (fun _ (blk : basic_block) acc -> acc || blk.label = lbl) cfg.blocks false in
            if exists then Ok ()
            else Error (InvalidJumpTarget (b.id, Printf.sprintf "Label(%s)" lbl))
        | TargetImm _ -> Ok ()
      in
      let targets = successors b in
      let rec loop_targets = function
        | [] -> Ok ()
        | t :: rest ->
            (match check_target t with
            | Ok () -> loop_targets rest
            | Error e -> Error e)
      in
      loop_targets targets

let verify_cfg (cfg : cfg) : (unit, verify_error) result =
  if not (Hashtbl.mem cfg.blocks cfg.entry_id) then
    Error (MissingEntryBlock cfg.entry_id)
  else
    let res = ref (Ok ()) in
    Hashtbl.iter (fun _ (b : basic_block) ->
      if Result.is_ok !res then begin
        match verify_block cfg b with
        | Ok () -> ()
        | Error e -> res := Error e
      end
    ) cfg.blocks;
    !res

let verify_func (f : func) : (unit, verify_error) result =
  verify_cfg f.cfg
