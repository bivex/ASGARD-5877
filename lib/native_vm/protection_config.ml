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

let with_stack_vm ?superoperators ?state_feedback ?layout_randomization ?runtime_hardening ?compact_imm ?feedback_rate ?cff_couple_key enabled b =
  let curr = !b.stack_vm in
  let stack_vm = {
    enabled;
    superoperators = Option.value ~default:curr.superoperators superoperators;
    state_feedback = Option.value ~default:curr.state_feedback state_feedback;
    layout_randomization = Option.value ~default:curr.layout_randomization layout_randomization;
    runtime_hardening = Option.value ~default:curr.runtime_hardening runtime_hardening;
    compact_imm = Option.value ~default:curr.compact_imm compact_imm;
    feedback_rate = Option.value ~default:curr.feedback_rate feedback_rate;
    cff_couple_key = Option.value ~default:curr.cff_couple_key cff_couple_key;
    opcode_polymorphism = curr.opcode_polymorphism;
    permute_registers = curr.permute_registers;
    host_stack_size_kb = curr.host_stack_size_kb;
  } in
  b := { !b with stack_vm };
  b

let with_eh_shadowing ?shadow_alloc_size ?interceptor_symbol enabled b =
  let curr = !b.eh_shadowing in
  let eh_shadowing = {
    enabled;
    shadow_alloc_size = Option.value ~default:curr.shadow_alloc_size shadow_alloc_size;
    interceptor_symbol = Option.value ~default:curr.interceptor_symbol interceptor_symbol;
  } in
  b := { !b with eh_shadowing };
  b

let with_anti_vpc ?scramble_vpc ?split_vpc ?entropy_whitening enabled b =
  let curr = !b.anti_vpc in
  let anti_vpc = {
    enabled;
    scramble_vpc = Option.value ~default:curr.scramble_vpc scramble_vpc;
    split_vpc = Option.value ~default:curr.split_vpc split_vpc;
    entropy_whitening = Option.value ~default:curr.entropy_whitening entropy_whitening;
  } in
  b := { !b with anti_vpc };
  b

let with_memory_chaffing ?pool_size ?chaff_ratio enabled b =
  let curr = !b.memory_chaffing in
  let memory_chaffing = {
    enabled;
    pool_size = Option.value ~default:curr.pool_size pool_size;
    chaff_ratio = Option.value ~default:curr.chaff_ratio chaff_ratio;
  } in
  b := { !b with memory_chaffing };
  b

let with_comp_stall ?n_iterations ?pow_difficulty ?variant ?seed enabled b =
  let curr = !b.comp_stall in
  let comp_stall = {
    enabled;
    n_iterations = Option.value ~default:curr.n_iterations n_iterations;
    pow_difficulty = Option.value ~default:curr.pow_difficulty pow_difficulty;
    variant = Option.value ~default:curr.variant variant;
    tau_ux_sec = curr.tau_ux_sec;
    emu_quota_instrs = curr.emu_quota_instrs;
    seed = Option.value ~default:curr.seed seed;
  } in
  b := { !b with comp_stall };
  b

let with_seed seed b =
  b := { !b with seed };
  b

let build b = !b
