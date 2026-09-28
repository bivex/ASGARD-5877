include Protection_types
include Protection_presets

let from_json_string = Protection_json.from_json_string
let from_file = Protection_json.from_file
let to_json_string = Protection_json.to_json_string
let save_to_file = Protection_json.save_to_file

type builder = t ref

let create_builder ?(base = default) () = ref base

let with_cff enabled b =
  b := { !b with cff = { !b.cff with enabled } };
  b

let with_mba ?depth enabled b =
  let mba =
    match depth with
    | Some d -> { !b.mba with enabled; depth = d }
    | None -> { !b.mba with enabled }
  in
  b := { !b with mba };
  b

let with_stack_vm ?superoperators ?state_feedback ?layout_randomization ?runtime_hardening ?compact_imm enabled b =
  let curr = !b.stack_vm in
  let stack_vm = {
    enabled;
    superoperators = Option.value ~default:curr.superoperators superoperators;
    state_feedback = Option.value ~default:curr.state_feedback state_feedback;
    layout_randomization = Option.value ~default:curr.layout_randomization layout_randomization;
    runtime_hardening = Option.value ~default:curr.runtime_hardening runtime_hardening;
    compact_imm = Option.value ~default:curr.compact_imm compact_imm;
  } in
  b := { !b with stack_vm };
  b

let with_seed seed b =
  b := { !b with seed };
  b

let build b = !b
