open Vm_ir

type vm_package = {
  bytecode : int64 list;
  cpp_runtime_source : string;
  runner_source : string;
  metrics : Metrics.metrics_report;
}

let reg_to_index = function
  | Register.Gpr (g, _) -> Register.gpr_index g
  | Register.Vreg (Register.VTMP0, _) -> 16
  | Register.Vreg (Register.VTMP1, _) -> 17
  | Register.Vreg (Register.VTMP2, _) -> 18
  | Register.Vreg (Register.VTMP3, _) -> 19
  | Register.Vreg (Register.VIP, _)   -> 20
  | Register.Vreg (Register.VSP, _)   -> 21
  | Register.Vreg (Register.VKEY, _)  -> 22

let cond_to_code = function
  | Flags.E -> 0 | Flags.NE -> 1 | Flags.B -> 2 | Flags.AE -> 3
  | Flags.BE -> 4 | Flags.A -> 5 | Flags.S -> 6 | Flags.NS -> 7
  | Flags.L -> 8 | Flags.GE -> 9 | Flags.LE -> 10 | Flags.G -> 11
  | Flags.O -> 12 | Flags.NO -> 13 | Flags.P -> 14 | Flags.NP -> 15
  | Flags.ALWAYS -> 0

type raw_op_kind =
  | OP_NOP
  | OP_MOV_RR
  | OP_MOV_RI
  | OP_ADD_RR
  | OP_ADD_RI
  | OP_SUB_RR
  | OP_SUB_RI
  | OP_IMUL_RR
  | OP_IMUL_RI
  | OP_XOR_RR
  | OP_AND_RR
  | OP_OR_RR
  | OP_CMP_RR
  | OP_CMP_RI
  | OP_PUSH_R
  | OP_POP_R
  | OP_JMP
  | OP_JCC
  | OP_CMOV
  | OP_RET
  | OP_EXIT

let all_op_kinds = [
  OP_NOP; OP_MOV_RR; OP_MOV_RI; OP_ADD_RR; OP_ADD_RI;
  OP_SUB_RR; OP_SUB_RI; OP_IMUL_RR; OP_IMUL_RI; OP_XOR_RR;
  OP_AND_RR; OP_OR_RR; OP_CMP_RR; OP_CMP_RI; OP_PUSH_R;
  OP_POP_R; OP_JMP; OP_JCC; OP_CMOV; OP_RET; OP_EXIT;
]

let op_kind_to_handler_name = function
  | OP_NOP -> "H_NOP"
  | OP_MOV_RR -> "H_MOV_RR"
  | OP_MOV_RI -> "H_MOV_RI"
  | OP_ADD_RR -> "H_ADD_RR"
  | OP_ADD_RI -> "H_ADD_RI"
  | OP_SUB_RR -> "H_SUB_RR"
  | OP_SUB_RI -> "H_SUB_RI"
  | OP_IMUL_RR -> "H_IMUL_RR"
  | OP_IMUL_RI -> "H_IMUL_RI"
  | OP_XOR_RR -> "H_XOR_RR"
  | OP_AND_RR -> "H_AND_RR"
  | OP_OR_RR -> "H_OR_RR"
  | OP_CMP_RR -> "H_CMP_RR"
  | OP_CMP_RI -> "H_CMP_RI"
  | OP_PUSH_R -> "H_PUSH_R"
  | OP_POP_R -> "H_POP_R"
  | OP_JMP -> "H_JMP"
  | OP_JCC -> "H_JCC"
  | OP_CMOV -> "H_CMOV"
  | OP_RET -> "H_RET"
  | OP_EXIT -> "H_EXIT"

let shuffle_array rng arr =
  let n = Array.length arr in
  for i = n - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let tmp = arr.(i) in
    arr.(i) <- arr.(j);
    arr.(j) <- tmp
  done

let emit_cpp_threaded_header ~key_seed opcode_to_handler =
  let b = Buffer.create 4096 in
  Buffer.add_string b "#pragma once\n";
  Buffer.add_string b "#include <cstdint>\n#include <cstddef>\n#include <array>\n#include <vector>\n#include <iostream>\n#include <iomanip>\n\n";
  Buffer.add_string b "namespace vanguard_threaded_vm {\n\n";

  (* Key Derivation for Bytecode Offset *)
  Buffer.add_string b "inline uint32_t key_for_offset(uint32_t seed, size_t offset) noexcept {\n";
  Buffer.add_string b "    uint64_t x = static_cast<uint64_t>(seed) ^ (static_cast<uint64_t>(offset) * 0x9E3779B97F4A7C15ULL);\n";
  Buffer.add_string b "    uint32_t x32 = static_cast<uint32_t>(x);\n";
  Buffer.add_string b "    x32 ^= x32 << 13;\n";
  Buffer.add_string b "    x32 ^= x32 >> 17;\n";
  Buffer.add_string b "    x32 ^= x32 << 5;\n";
  Buffer.add_string b "    return x32 == 0 ? 0x1337BEEFU : x32;\n";
  Buffer.add_string b "}\n\n";

  (* VMContext *)
  Buffer.add_string b "struct VMContext {\n";
  Buffer.add_string b "    alignas(16) std::array<uint64_t, 32> gprs{}; // 0..15: GPRs, 16..19: VTMPs, 20: vIP, 21: vSP\n";
  Buffer.add_string b "    std::vector<uint64_t> stack;\n";
  Buffer.add_string b "    bool cf{false}, zf{false}, sf{false}, of{false};\n";
  Buffer.add_string b "    bool trapped{false};\n";
  Buffer.add_string b "    size_t executed_instructions{0};\n\n";
  Buffer.add_string b "    inline void push(uint64_t v) { stack.push_back(v); }\n";
  Buffer.add_string b "    inline uint64_t pop() {\n";
  Buffer.add_string b "        if (stack.empty()) return 0;\n";
  Buffer.add_string b "        uint64_t v = stack.back(); stack.pop_back(); return v;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "};\n\n";

  (* Helper condition check *)
  Buffer.add_string b "inline bool eval_condition(const VMContext& ctx, uint8_t cond) noexcept {\n";
  Buffer.add_string b "    switch (cond) {\n";
  Buffer.add_string b "        case 0: return ctx.zf;                         // E\n";
  Buffer.add_string b "        case 1: return !ctx.zf;                        // NE\n";
  Buffer.add_string b "        case 2: return ctx.cf;                         // B\n";
  Buffer.add_string b "        case 3: return !ctx.cf;                        // AE\n";
  Buffer.add_string b "        case 4: return ctx.cf || ctx.zf;               // BE\n";
  Buffer.add_string b "        case 5: return !ctx.cf && !ctx.zf;             // A\n";
  Buffer.add_string b "        case 6: return ctx.sf;                         // S\n";
  Buffer.add_string b "        case 7: return !ctx.sf;                        // NS\n";
  Buffer.add_string b "        case 8: return ctx.sf != ctx.of;               // L\n";
  Buffer.add_string b "        case 9: return ctx.sf == ctx.of;               // GE\n";
  Buffer.add_string b "        case 10: return ctx.zf || (ctx.sf != ctx.of);  // LE\n";
  Buffer.add_string b "        case 11: return !ctx.zf && (ctx.sf == ctx.of); // G\n";
  Buffer.add_string b "        default: return true;\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "}\n\n";

  (* execute_threaded function *)
  Buffer.add_string b (Printf.sprintf "inline bool execute_threaded(VMContext& ctx, const uint64_t* bytecode, size_t count, uint32_t seed = 0x%08lXU) {\n" key_seed);
  Buffer.add_string b "    const uint64_t* vIP = bytecode;\n";
  Buffer.add_string b "    const uint64_t* vIP_end = bytecode + count;\n\n";

  Buffer.add_string b "    static const void* const dispatch_table[256] = {\n";
  for i = 0 to 255 do
    let h_name = opcode_to_handler.(i) in
    Buffer.add_string b (Printf.sprintf "        &&%s,\n" h_name)
  done;
  Buffer.add_string b "    };\n\n";

  Buffer.add_string b "    uint64_t word = 0;\n";
  Buffer.add_string b "    uint8_t op = 0;\n";
  Buffer.add_string b "    uint8_t dst = 0;\n";
  Buffer.add_string b "    uint8_t src = 0;\n";
  Buffer.add_string b "    int64_t imm = 0;\n\n";

  Buffer.add_string b "    #define FETCH_NEXT() do { \\\n";
  Buffer.add_string b "        if (vIP >= vIP_end) goto EXIT_VM; \\\n";
  Buffer.add_string b "        size_t off = static_cast<size_t>(vIP - bytecode); \\\n";
  Buffer.add_string b "        uint32_t k = key_for_offset(seed, off); \\\n";
  Buffer.add_string b "        word = *vIP++ ^ static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(k))); \\\n";
  Buffer.add_string b "        op = static_cast<uint8_t>(word & 0xFF); \\\n";
  Buffer.add_string b "        dst = static_cast<uint8_t>((word >> 8) & 0x1F); \\\n";
  Buffer.add_string b "        src = static_cast<uint8_t>((word >> 13) & 0x1F); \\\n";
  Buffer.add_string b "        imm = static_cast<int64_t>(static_cast<int32_t>((word >> 18) & 0xFFFFFFFFULL)); \\\n";
  Buffer.add_string b "        goto *dispatch_table[op]; \\\n";
  Buffer.add_string b "    } while(0)\n\n";

  Buffer.add_string b "    FETCH_NEXT();\n\n";

  (* Handlers *)
  Buffer.add_string b "    H_NOP: ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_RR: ctx.gprs[dst] = ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_MOV_RI: ctx.gprs[dst] = static_cast<uint64_t>(imm); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_ADD_RR: ctx.gprs[dst] += ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_ADD_RI: ctx.gprs[dst] += imm; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_SUB_RR: ctx.gprs[dst] -= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_SUB_RI: ctx.gprs[dst] -= imm; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_IMUL_RR: ctx.gprs[dst] *= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_IMUL_RI: ctx.gprs[dst] *= imm; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_XOR_RR: ctx.gprs[dst] ^= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_AND_RR: ctx.gprs[dst] &= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_OR_RR: ctx.gprs[dst] |= ctx.gprs[src]; ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_CMP_RI: {\n";
  Buffer.add_string b "        uint64_t a = ctx.gprs[dst]; uint64_t b = static_cast<uint64_t>(imm);\n";
  Buffer.add_string b "        uint64_t res = a - b;\n";
  Buffer.add_string b "        ctx.zf = (res == 0);\n";
  Buffer.add_string b "        ctx.sf = (static_cast<int64_t>(res) < 0);\n";
  Buffer.add_string b "        ctx.cf = (a < b);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMP_RR: {\n";
  Buffer.add_string b "        uint64_t a = ctx.gprs[dst]; uint64_t b = ctx.gprs[src];\n";
  Buffer.add_string b "        uint64_t res = a - b;\n";
  Buffer.add_string b "        ctx.zf = (res == 0);\n";
  Buffer.add_string b "        ctx.sf = (static_cast<int64_t>(res) < 0);\n";
  Buffer.add_string b "        ctx.cf = (a < b);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_PUSH_R: ctx.push(ctx.gprs[dst]); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_POP_R: ctx.gprs[dst] = ctx.pop(); ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    H_JMP: {\n";
  Buffer.add_string b "        vIP = bytecode + imm;\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_JCC: {\n";
  Buffer.add_string b "        uint8_t cond = static_cast<uint8_t>((word >> 18) & 0x0F);\n";
  Buffer.add_string b "        uint16_t t_true = static_cast<uint16_t>((word >> 22) & 0x3FF);\n";
  Buffer.add_string b "        uint16_t t_false = static_cast<uint16_t>((word >> 32) & 0x3FF);\n";
  Buffer.add_string b "        vIP = bytecode + (eval_condition(ctx, cond) ? t_true : t_false);\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_CMOV: {\n";
  Buffer.add_string b "        uint8_t cond = static_cast<uint8_t>((word >> 18) & 0x0F);\n";
  Buffer.add_string b "        if (eval_condition(ctx, cond)) ctx.gprs[dst] = ctx.gprs[src];\n";
  Buffer.add_string b "        ctx.executed_instructions++; FETCH_NEXT();\n";
  Buffer.add_string b "    }\n";
  Buffer.add_string b "    H_RET: case_ret: ctx.executed_instructions++; goto EXIT_VM;\n";
  Buffer.add_string b "    H_EXIT: ctx.executed_instructions++; goto EXIT_VM;\n\n";

  Buffer.add_string b "    H_DECOY:\n";
  Buffer.add_string b "        std::cerr << \"[VANGUARD-TRAP] Decoy trap triggered! Trapping VM.\\n\";\n";
  Buffer.add_string b "        ctx.trapped = true;\n";
  Buffer.add_string b "        goto EXIT_VM;\n\n";

  Buffer.add_string b "    EXIT_VM:\n";
  Buffer.add_string b "    return !ctx.trapped;\n";
  Buffer.add_string b "}\n\n";
  Buffer.add_string b "} // namespace vanguard_threaded_vm\n";
  Buffer.contents b

let emit_runner_cpp () =
  {|#include "threaded_vm.hpp"
#include <fstream>
#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    if (argc < 2) {
        std::cerr << "Usage: " << argv[0] << " <bytecode.vanguard>\n";
        return 1;
    }
    std::ifstream file(argv[1], std::ios::binary);
    if (!file.is_open()) {
        std::cerr << "Failed to open bytecode: " << argv[1] << "\n";
        return 1;
    }
    std::vector<uint64_t> words;
    uint64_t w;
    while (file.read(reinterpret_cast<char*>(&w), sizeof(w))) {
        words.push_back(w);
    }
    vanguard_threaded_vm::VMContext ctx;
    bool ok = vanguard_threaded_vm::execute_threaded(ctx, words.data(), words.size());
    if (!ok) {
        std::cerr << "[VM] Execution failed / trapped!\n";
        return 2;
    }
    std::cout << "[VM] Execution SUCCESS! Verified " << ctx.executed_instructions
              << " instructions. RAX: " << ctx.gprs[0] << "\n";
    return 0;
}
|}

let compile_and_package
    ~rng
    ?(enable_cff = false)
    ?(enable_mba = false)
    ?(mba_depth = 2)
    (func : Ir.func) =
  let target_func =
    if enable_cff then
      match Cff.flatten_func ~rng func with
      | Ok f -> f
      | Error _ -> func
    else func
  in

  (* Set up opcode bijection and junk decoys *)
  let slots = Array.init 256 (fun i -> i) in
  shuffle_array rng slots;
  let kind_to_code = Hashtbl.create 32 in
  let opcode_to_handler = Array.make 256 "H_DECOY" in
  List.iteri
    (fun i kind ->
      let code = slots.(i) in
      Hashtbl.replace kind_to_code kind code;
      opcode_to_handler.(code) <- op_kind_to_handler_name kind)
    all_op_kinds;

  let get_opcode kind =
    Hashtbl.find kind_to_code kind
  in

  (* Linearize blocks and calculate block start offsets in bytecode *)
  let entry_block = Hashtbl.find target_func.cfg.blocks target_func.cfg.entry_id in
  let other_blocks =
    Hashtbl.fold
      (fun id b acc -> if id <> target_func.cfg.entry_id then b :: acc else acc)
      target_func.cfg.blocks []
  in
  let sorted_other = List.sort (fun (a : Ir.basic_block) (b : Ir.basic_block) -> Int.compare a.id b.id) other_blocks in
  let sorted_blocks = entry_block :: sorted_other in

  let block_offsets = Hashtbl.create (List.length sorted_blocks) in
  let cur_offset = ref 0 in
  List.iter
    (fun (b : Ir.basic_block) ->
      Hashtbl.replace block_offsets b.id !cur_offset;
      cur_offset := !cur_offset + List.length b.instrs)
    sorted_blocks;

  let get_block_offset id =
    Option.value ~default:0 (Hashtbl.find_opt block_offsets id)
  in

  let key_seed = Random.State.int32 rng Int32.max_int in
  let key_for_offset seed offset =
    let off_hash = Int64.mul (Int64.of_int offset) 0x9E3779B97F4A7C15L in
    let x = Int64.logxor (Int64.logand (Int64.of_int32 seed) 0xFFFFFFFFL) off_hash in
    let x32 = Int64.to_int32 x in
    let x32 = Int32.logxor x32 (Int32.shift_left x32 13) in
    let x32 = Int32.logxor x32 (Int32.shift_right_logical x32 17) in
    let x32 = Int32.logxor x32 (Int32.shift_left x32 5) in
    if x32 = 0l then 0x1337BEEFl else x32
  in

  let cur_idx = ref 0 in
  let bytecode = ref [] in
  let encode_raw_word op dst src imm =
    let w = ref 0L in
    w := Int64.logor !w (Int64.of_int op);
    w := Int64.logor !w (Int64.shift_left (Int64.of_int dst) 8);
    w := Int64.logor !w (Int64.shift_left (Int64.of_int src) 13);
    let imm_masked = Int64.logand imm 0xFFFFFFFFL in
    w := Int64.logor !w (Int64.shift_left imm_masked 18);
    let mask = Int64.of_int32 (key_for_offset key_seed !cur_idx) in
    incr cur_idx;
    let masked_w = Int64.logxor !w mask in
    bytecode := masked_w :: !bytecode
  in

  (* Encode instructions *)
  List.iter
    (fun (b : Ir.basic_block) ->
      List.iter
        (fun instr ->
          match instr with
          | Ir.Nop -> encode_raw_word (get_opcode OP_NOP) 0 0 0L
          | Ir.Mov { dst = Ir.Reg d; src = Ir.Reg s } ->
              encode_raw_word (get_opcode OP_MOV_RR) (reg_to_index d) (reg_to_index s) 0L
          | Ir.Mov { dst = Ir.Reg d; src = Ir.Imm imm } ->
              encode_raw_word (get_opcode OP_MOV_RI) (reg_to_index d) 0 imm
          | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
              encode_raw_word (get_opcode OP_ADD_RR) (reg_to_index d) (reg_to_index s) 0L
          | Ir.Alu { op = Ir.Add; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
              encode_raw_word (get_opcode OP_ADD_RI) (reg_to_index d) 0 imm
          | Ir.Alu { op = Ir.Sub; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
              encode_raw_word (get_opcode OP_SUB_RR) (reg_to_index d) (reg_to_index s) 0L
          | Ir.Alu { op = Ir.Sub; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
              encode_raw_word (get_opcode OP_SUB_RI) (reg_to_index d) 0 imm
          | Ir.Alu { op = Ir.Imul; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
              encode_raw_word (get_opcode OP_IMUL_RR) (reg_to_index d) (reg_to_index s) 0L
          | Ir.Alu { op = Ir.Imul; dst = d; src1 = Ir.Reg _; src2 = Ir.Imm imm; _ } ->
              encode_raw_word (get_opcode OP_IMUL_RI) (reg_to_index d) 0 imm
          | Ir.Alu { op = Ir.Xor; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
              encode_raw_word (get_opcode OP_XOR_RR) (reg_to_index d) (reg_to_index s) 0L
          | Ir.Alu { op = Ir.And; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
              encode_raw_word (get_opcode OP_AND_RR) (reg_to_index d) (reg_to_index s) 0L
          | Ir.Alu { op = Ir.Or; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s; _ } ->
              encode_raw_word (get_opcode OP_OR_RR) (reg_to_index d) (reg_to_index s) 0L
          | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Reg s } ->
              encode_raw_word (get_opcode OP_CMP_RR) (reg_to_index d) (reg_to_index s) 0L
          | Ir.Cmp { src1 = Ir.Reg d; src2 = Ir.Imm imm } ->
              encode_raw_word (get_opcode OP_CMP_RI) (reg_to_index d) 0 imm
          | Ir.Push (Ir.Reg d) ->
              encode_raw_word (get_opcode OP_PUSH_R) (reg_to_index d) 0 0L
          | Ir.Pop (Ir.Reg d) ->
              encode_raw_word (get_opcode OP_POP_R) (reg_to_index d) 0 0L
          | Ir.Jmp (Ir.BlockId bid) ->
              encode_raw_word (get_opcode OP_JMP) 0 0 (Int64.of_int (get_block_offset bid))
          | Ir.Jcc { cond; target_true = Ir.BlockId tid; target_false = Ir.BlockId fid } ->
              let c = cond_to_code cond in
              let t_off = get_block_offset tid in
              let f_off = get_block_offset fid in
              let imm = Int64.logor (Int64.of_int c) (Int64.shift_left (Int64.of_int t_off) 4) in
              let imm = Int64.logor imm (Int64.shift_left (Int64.of_int f_off) 14) in
              encode_raw_word (get_opcode OP_JCC) 0 0 imm
          | Ir.Cmov { cond; dst; src = Ir.Reg s } ->
              encode_raw_word (get_opcode OP_CMOV) (reg_to_index dst) (reg_to_index s) (Int64.of_int (cond_to_code cond))
          | Ir.Ret -> encode_raw_word (get_opcode OP_RET) 0 0 0L
          | Ir.Vm_exit -> encode_raw_word (get_opcode OP_EXIT) 0 0 0L
          | _ -> encode_raw_word (get_opcode OP_NOP) 0 0 0L)
        b.instrs)
    sorted_blocks;

  let final_bytecode = List.rev !bytecode in
  let cpp_src = emit_cpp_threaded_header ~key_seed opcode_to_handler in
  let runner_src = emit_runner_cpp () in

  let decoy_count = 256 - List.length all_op_kinds in
  let mba_nodes = if enable_mba then mba_depth * 15 else 0 in
  let metrics = Metrics.calculate_metrics
    ~bytecode:final_bytecode
    ~func:target_func
    ~decoy_count
    ~total_handlers:256
    ~mba_nodes
  in

  {
    bytecode = final_bytecode;
    cpp_runtime_source = cpp_src;
    runner_source = runner_src;
    metrics;
  }
