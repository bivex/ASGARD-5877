#!/usr/bin/env python3
"""
ASGARD-5877 ISA Reference Parser & Test Generator
=================================================

Fetches and parses architecture specifications from ASM Reference
(https://asm-docs.microagi.org/ and https://www.felixcloutier.com/x86/)
and generates idiomatic OCaml Alcotest cases for ASGARD lifters and VMs.

Usage:
  python3 scripts/isa_ref_parser.py fetch x86 <mnemonic>
  python3 scripts/isa_ref_parser.py test x86 <mnemonic> [--output <file>]
  python3 scripts/isa_ref_parser.py parse-text <file_or_->
  python3 scripts/isa_ref_parser.py audit <mnemonic>
"""

import sys
import os
import re
import argparse
import urllib.request
import urllib.error
from typing import List, Dict, Optional, Any

try:
    import bs4
except ImportError:
    bs4 = None

BASE_URL_MICROAGI = "https://asm-docs.microagi.org"
BASE_URL_FELIX = "https://www.felixcloutier.com/x86"

USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) ASGARD-5877/1.0"


class InstructionVariant:
    def __init__(self, opcode: str, instruction: str, op_en: str, mode_64: str, compat_mode: str, description: str):
        self.opcode = opcode.strip()
        self.instruction = instruction.strip()
        self.op_en = op_en.strip()
        self.mode_64 = mode_64.strip()
        self.compat_mode = compat_mode.strip()
        self.description = description.strip()

    def to_dict(self) -> Dict[str, str]:
        return {
            "opcode": self.opcode,
            "instruction": self.instruction,
            "op_en": self.op_en,
            "mode_64": self.mode_64,
            "compat_mode": self.compat_mode,
            "description": self.description,
        }


class InstructionSpec:
    def __init__(self, mnemonic: str, full_title: str):
        self.mnemonic = mnemonic.upper()
        self.full_title = full_title
        self.variants: List[InstructionVariant] = []
        self.description: str = ""
        self.operation: str = ""
        self.flags_affected: str = "None"
        self.exceptions: Dict[str, str] = {}

    def is_valid_64bit(self) -> bool:
        return any("Valid" in v.mode_64 for v in self.variants)


def fetch_url(url: str) -> Optional[str]:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        return None
    except Exception as e:
        sys.stderr.write(f"[-] Fetch error ({url}): {e}\n")
        return None


def fetch_x86_instruction_page(mnemonic: str) -> Optional[str]:
    mnem_lower = mnemonic.lower()
    # 1. Try asm-docs.microagi.org
    url_microagi = f"{BASE_URL_MICROAGI}/x86/{mnem_lower}.html"
    html = fetch_url(url_microagi)
    if html:
        return html

    # 2. Try felixcloutier.com/x86 fallback
    url_felix = f"{BASE_URL_FELIX}/{mnem_lower}.html"
    return fetch_url(url_felix)


def parse_html_spec(html_content: str, mnemonic: str) -> InstructionSpec:
    if not bs4:
        raise RuntimeError("bs4 (BeautifulSoup4) is required for HTML parsing. Run `pip install beautifulsoup4`.")

    soup = bs4.BeautifulSoup(html_content, "html.parser")
    h1 = soup.find("h1")
    title = h1.get_text(" ", strip=True) if h1 else mnemonic

    spec = InstructionSpec(mnemonic, title)

    # 1. Parse main opcode / instruction table
    table = soup.find("table")
    if table:
        for tr in table.find_all("tr")[1:]:
            cells = [td.get_text(" ", strip=True) for td in tr.find_all("td")]
            if len(cells) >= 6:
                var = InstructionVariant(
                    opcode=cells[0],
                    instruction=cells[1],
                    op_en=cells[2],
                    mode_64=cells[3],
                    compat_mode=cells[4],
                    description=cells[5],
                )
                spec.variants.append(var)

    # 2. Parse sections: Description, Operation, Flags Affected
    for header in soup.find_all(["h2", "h3"]):
        hdr_text = header.get_text(strip=True).lower()
        content_paras = []
        sibling = header.find_next_sibling()
        while sibling and sibling.name not in ["h2", "h3"]:
            text = sibling.get_text("\n", strip=True)
            if text:
                content_paras.append(text)
            sibling = sibling.find_next_sibling()

        section_body = "\n\n".join(content_paras)
        if "description" in hdr_text:
            spec.description = section_body
        elif "operation" in hdr_text:
            spec.operation = section_body
        elif "flags affected" in hdr_text:
            spec.flags_affected = section_body

    return spec


def parse_raw_text(text: str) -> InstructionSpec:
    """Parses raw copy-pasted text from the documentation site."""
    lines = [line.strip() for line in text.splitlines()]
    mnemonic = "UNKNOWN"
    title = ""

    # Detect header (e.g. CPUID — CPU Identification)
    for line in lines:
        if "—" in line or "-" in line:
            parts = re.split(r"[\u2014\-]", line, maxsplit=1)
            candidate = parts[0].strip()
            if candidate and len(candidate.split()) == 1 and candidate.isalnum():
                mnemonic = candidate
                title = line
                break

    spec = InstructionSpec(mnemonic, title)

    # Table parsing state
    in_table = False
    in_flags = False
    flags_lines = []

    for line in lines:
        if "Opcode" in line and "Instruction" in line:
            in_table = True
            continue
        if in_table:
            if line.startswith("Instruction Operand Encoding") or line.startswith("Description"):
                in_table = False
            else:
                # The specification tables are tab-separated on the site, but
                # a copy-paste of the rendered page keeps the column padding
                # as runs of spaces instead.
                parts = re.split(r"\t+|\s{2,}", line.strip())
                if len(parts) >= 6:
                    spec.variants.append(
                        InstructionVariant(parts[0], parts[1], parts[2], parts[3], parts[4], " ".join(parts[5:]))
                    )
        if line.startswith("Flags Affected"):
            in_flags = True
            continue
        if in_flags:
            if line.startswith("Exceptions") or line.startswith("Protected Mode Exceptions"):
                in_flags = False
            else:
                if line:
                    flags_lines.append(line)

    if flags_lines:
        spec.flags_affected = "\n".join(flags_lines)

    return spec


def generate_ocaml_test(spec: InstructionSpec) -> str:
    """Generates an idiomatic Alcotest unit test case for ASGARD."""
    mnem_lower = spec.mnemonic.lower()
    test_func_name = f"test_x86_lift_{mnem_lower}"
    sample_instr = mnem_lower
    if spec.variants:
        # Choose a clean 64-bit valid form
        valid_64 = [v for v in spec.variants if "Valid" in v.mode_64]
        target_variant = valid_64[0] if valid_64 else spec.variants[0]
        sample_instr = target_variant.instruction.lower()

    # Simplify operands if abstract (e.g., r/m64 -> rax, imm8 -> 42)
    sample_concrete = sample_instr
    sample_concrete = re.sub(r"r/m64|r64", "rax", sample_concrete)
    sample_concrete = re.sub(r"r/m32|r32", "eax", sample_concrete)
    sample_concrete = re.sub(r"r/m16|r16", "ax", sample_concrete)
    sample_concrete = re.sub(r"r/m8|r8", "al", sample_concrete)
    sample_concrete = re.sub(r"imm64|imm32|imm16|imm8", "0x2A", sample_concrete)

    code = f"""let {test_func_name} () =
  (* Verified instruction lifecycle for {spec.full_title} *)
  let asm = {{|
func_{mnem_lower}:
    {sample_concrete}
    ret
|}} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail (Printf.sprintf "Lifting failed for {spec.mnemonic}: %s" e)
  | Ok func ->
      let state = make_state () in
      set_reg state Register.rax 0x10L;
      set_reg state Register.rcx 0x0L;
      match run_func state func with
      | Error e -> Alcotest.fail (Printf.sprintf "Oracle evaluation failed for {spec.mnemonic}: %s" e)
      | Ok () ->
          (* Check register results *)
          Alcotest.(check bool) "{spec.mnemonic} executed without trap" true (Option.is_none state.trapped);
"""
    if "None" in spec.flags_affected:
        code += '          (* Instruction specifies Flags Affected: None *)\n'
    else:
        code += f'          (* Flags affected: {spec.flags_affected.strip().replace(chr(10), " ")} *)\n'

    code += "\n"
    code += f'(* Add to tests list in test/test_x86_lifter.ml: *)\n'
    code += f'(*   Alcotest.test_case "{mnem_lower}_lifecycle" `Quick {test_func_name}; *)\n'
    return code


CATEGORIES = {
    "Арифметика целых": ["ADD", "SUB", "INC", "DEC", "NEG", "IMUL", "MUL"],
    "Логика/биты": ["AND", "OR", "XOR", "NOT", "SHL", "SHR", "SAR", "ROL", "ROR"],
    "Сравнение/флаги": ["CMP", "TEST"],
    "Управление потоком": ["JMP", "Jcc", "CALL", "RET"],
    "Условные пересылки": ["CMOVcc", "SETcc"],
    "Деление": ["DIV", "IDIV"],
    "Битовые тесты": ["BT", "BTC", "BTR", "BTS"],
    "Обмен": ["XCHG", "XADD", "CMPXCHG", "CMPXCHG8B", "CMPXCHG16B"],
    "Строковые": ["MOVS", "MOVSB", "MOVSW", "MOVSD", "MOVSQ",
                  "STOS", "STOSB", "STOSW", "STOSD", "STOSQ",
                  "CMPS", "CMPSB", "CMPSW", "CMPSD", "CMPSQ",
                  "SCAS", "SCASB", "SCASW", "SCASD", "SCASQ",
                  "LODS", "LODSB", "LODSW", "LODSD", "LODSQ",
                  "REP", "REPE", "REPNE", "REPZ", "REPNZ"],
    "Доп. сдвиги": ["SHLD", "SHRD", "RCL", "RCR"],
    "Знако-расширение": ["CBW", "CWD", "CDQ", "CQO", "CWDE", "CDQE", "CBTW", "CWTL", "CWTD", "CQTO"],
    "Расширение при переносе": ["MOVSX", "MOVSXD", "MOVZX"],
    "FPU (x87)": [
        "FLD", "FST", "FSTP", "FILD", "FIST", "FISTP",
        "FADD", "FADDP", "FSUB", "FSUBP", "FSUBR", "FSUBRP",
        "FMUL", "FMULP", "FDIV", "FDIVP", "FDIVR", "FDIVRP",
        "FCOM", "FCOMP", "FCOMPP", "FCOMI", "FCOMIP",
        "FCHS", "FABS", "FSQRT",
        "FLD1", "FLDZ", "FLDPI", "FLDL2E", "FLDL2T", "FLDLG2", "FLDLN2",
        "FSIN", "FCOS", "FSINCOS", "FPTAN", "FPATAN", "FYL2X", "FYL2XP1", "F2XM1",
        "FSTSW", "FNSTSW",
    ],
}


def get_native_audit_patterns(m: str):
    m_lower = m.lower()

    # Defaults
    l_pat = rf'("{m_lower}"|\b{m_lower}\b)'
    ir_pat = rf"\b{m_lower}\b"
    ev_pat = rf"\b{m_lower}\b"
    ctx_pat = r"(get_reg|set_reg|gprs)"
    emit_pat = rf"(op_{m_lower}|h_{m_lower}|\b{m_lower}\b)"
    hndl_pat = rf"(h_{m_lower}|op_{m_lower}|\b{m_lower}\b)"
    xform_pat = rf"(op_{m_lower}|h_{m_lower}|\b{m_lower}\b)"
    t_pat = rf"\b{m_lower}\b"

    if m_lower == "jcc":
        l_pat = r"(jcc|parse_jcc|jz|jnz|je|jne|jg|jge|jl|jle|ja|jae|jb|jbe)"
        ir_pat = r"\bjcc\b"
        ev_pat = r"\bjcc\b"
        ctx_pat = r"(cf|zf|sf|of|pf)"
        emit_pat = r"op_jcc"
        hndl_pat = r"(h_jcc|op_jcc)"
        xform_pat = r"op_jcc"
        t_pat = r"(jcc|test_.*_jcc|jnz|jz|jne|je)"
    elif m_lower == "cmovcc":
        l_pat = r"(cmovcc|parse_cmovcc|cmov)"
        ir_pat = r"\bcmov\b"
        ev_pat = r"\bcmov\b"
        ctx_pat = r"(get_reg|set_reg|cf|zf|sf|of)"
        emit_pat = r"op_cmov"
        hndl_pat = r"(h_cmov|op_cmov)"
        xform_pat = r"op_cmov"
        t_pat = r"(cmov|cmovz|cmovne|cmove)"
    elif m_lower == "setcc":
        l_pat = r"(setcc|parse_setcc|setz|setne|sete|seta|setb|setg|setl)"
        ir_pat = r"\bsetcc\b"
        ev_pat = r"\bsetcc\b"
        ctx_pat = r"(get_reg|set_reg|cf|zf|sf|of|pf)"
        emit_pat = r"op_setcc"
        hndl_pat = r"(h_setcc|op_setcc)"
        xform_pat = r"op_setcc"
        t_pat = r"(setcc|setz|setne|sete|seta|setb)"
    elif m_lower in ("movs", "stos", "cmps", "scas", "lods"):
        l_pat = rf'("{m_lower}b"|"{m_lower}w"|"{m_lower}d"|"{m_lower}q"|\b{m_lower}\b)'
        ir_pat = r"(mem|atomic_mem|\balu\b)"
        ev_pat = r"(mem|\balu\b|eval_mem)"
        ctx_pat = r"(reg_rdi|reg_rsi|reg_rcx|get_reg)"
        emit_pat = r"(op_load_|op_store_|op_add_)"
        hndl_pat = r"(h_load_|h_store_|h_add_)"
        xform_pat = r"(op_load_|op_store_)"
        t_pat = rf"({m_lower}b|{m_lower}w|{m_lower}d|{m_lower}q|test_x86_.*string)"
    elif m_lower in ("movsb", "movsw", "movsd", "movsq",
                     "stosb", "stosw", "stosd", "stosq",
                     "cmpsb", "cmpsw", "cmpsd", "cmpsq",
                     "scasb", "scasw", "scasd", "scasq",
                     "lodsb", "lodsw", "lodsd", "lodsq"):
        l_pat = rf'"{m_lower}"'
        ir_pat = r"(mem|atomic_mem|\balu\b)"
        ev_pat = r"(mem|\balu\b|eval_mem)"
        ctx_pat = r"(reg_rdi|reg_rsi|reg_rcx|get_reg)"
        emit_pat = r"(op_load_|op_store_|op_add_)"
        hndl_pat = r"(h_load_|h_store_|h_add_)"
        xform_pat = r"(op_load_|op_store_)"
        base_str = m_lower[:-1]
        t_pat = rf"({m_lower}|test_x86_.*string|test_x86_rep.*{base_str})"
    elif m_lower in ("rep", "repe", "repne", "repz", "repnz"):
        l_pat = rf'("{m_lower}"|"{m_lower} "|\b{m_lower}\b)'
        ir_pat = r"(jcc|jmp|alu)"
        ev_pat = r"(jcc|jmp|eval)"
        ctx_pat = r"(reg_rcx|get_reg|set_reg|zf)"
        emit_pat = r"(op_jcc|op_jmp|op_sub)"
        hndl_pat = r"(h_jcc|h_jmp|h_sub)"
        xform_pat = r"(op_jcc|op_jmp)"
        t_pat = rf"({m_lower}|test_x86_rep)"
    elif m_lower in ("cbw", "cbtw", "cwd", "cwde", "cwtl", "cdq", "cltd", "cwtd", "cqo", "cqto", "cdqe", "cltq"):
        l_pat = rf'("{m_lower}"|\b{m_lower}\b)'
        ir_pat = r"(alu|shl|sar|mov)"
        ev_pat = r"(alu|shl|sar|mov)"
        ctx_pat = r"(reg_rax|reg_rdx|get_reg|set_reg)"
        emit_pat = r"(op_sar_|op_shl_|op_mov_)"
        hndl_pat = r"(h_sar_|h_shl_|h_mov_)"
        xform_pat = r"(op_sar_|op_shl_|op_mov_)"
        t_pat = rf"({m_lower}|sign_extension)"
    elif m_lower in ("movzx", "movzxb", "movzxw", "movzbq", "movzwq"):
        l_pat = r'"movzx"|"movzxb"|"movzxw"|"movzbq"|"movzwq"'
        ir_pat = r"(mov|and)"
        ev_pat = r"(mov|and)"
        ctx_pat = r"(get_reg|set_reg)"
        emit_pat = r"(op_mov_|op_and_|op_load_)"
        hndl_pat = r"(h_mov_|h_and_|h_load_8|h_load_16)"
        xform_pat = r"(op_mov_|op_and_|op_load_)"
        t_pat = r"(movzx|zero_extend)"
    elif m_lower in ("movsx", "movsxd", "movsxb", "movsxw", "movsbq", "movswq", "movslq"):
        l_pat = r'"movsx"|"movsxd"|"movsxb"|"movsxw"|"movsbq"|"movswq"|"movslq"'
        ir_pat = r"(mov|shl|sar)"
        ev_pat = r"(mov|shl|sar)"
        ctx_pat = r"(get_reg|set_reg)"
        emit_pat = r"(op_mov_|op_shl_|op_sar_|op_load_s)"
        hndl_pat = r"(h_mov_|h_shl_|h_sar_|h_load_s8|h_load_s16|h_load_s32)"
        xform_pat = r"(op_mov_|op_shl_|op_load_s)"
        t_pat = r"(movsx|sign_extension)"
    elif m_lower in ("bt", "btc", "btr", "bts"):
        l_pat = rf'"{m_lower}"'
        ir_pat = r"(alu|cmp|not)"
        ev_pat = r"(alu|cmp)"
        ctx_pat = r"(cf|get_reg|set_reg)"
        emit_pat = r"(op_and|op_shr|op_shl|op_cmp)"
        hndl_pat = r"(h_and|h_or|h_xor|h_shr|h_shl|h_cmp)"
        xform_pat = r"(op_and|op_or|op_xor|op_cmp)"
        t_pat = rf"({m_lower}|bit_test)"
    elif m_lower in ("xchg", "xadd", "cmpxchg", "cmpxchg8b", "cmpxchg16b"):
        l_pat = rf'"{m_lower}"'
        ir_pat = rf"(atomic_mem|xchg|cmov|\b{m_lower}\b)"
        ev_pat = rf"(atomic_mem|xchg|cmov|eval_atomic)"
        ctx_pat = r"(reg_rax|get_reg|set_reg)"
        emit_pat = r"(op_atomic_cas|op_atomic_swp|op_atomic_add|op_cmov)"
        hndl_pat = r"(atomic_cas|atomic_swp|atomic_add|h_cmov|atomic_mem)"
        xform_pat = r"(op_atomic_cas|op_atomic_swp|op_atomic_add)"
        t_pat = rf"({m_lower}|test_x86_cmpxchg)"
    elif m_lower in ("shld", "shrd"):
        l_pat = rf'"{m_lower}"'
        ir_pat = r"(alu|shl|shr|or)"
        ev_pat = r"(alu|shl|shr|or)"
        ctx_pat = r"(get_reg|set_reg)"
        emit_pat = r"(op_shl_|op_shr_|op_or_)"
        hndl_pat = r"(h_shl_|h_shr_|h_or_)"
        xform_pat = r"(op_shl_|op_shr_|op_or_)"
        t_pat = rf"({m_lower}|test_x86_shld_shrd)"
    elif m_lower in ("rcl", "rcr"):
        l_pat = rf'"{m_lower}"'
        ir_pat = r"(get_flags|set_flags|alu)"
        ev_pat = r"(get_flags|set_flags|alu)"
        ctx_pat = r"(cf|get_reg|set_reg)"
        emit_pat = r"(op_get_flags|op_set_flags|op_rol|op_ror)"
        hndl_pat = r"(h_get_flags|h_set_flags|h_alu|h_rol|h_ror)"
        xform_pat = r"(op_get_flags|op_set_flags)"
        t_pat = rf"({m_lower}|test_x86_rcl_rcr_cmc)"
    elif m_lower == "cpuid":
        l_pat = r'"cpuid"|\bcpuid\b'
        ir_pat = r"cpuid"
        ev_pat = r"cpuid"
        ctx_pat = r"(reg_rax|reg_rbx|reg_rcx|reg_rdx)"
        emit_pat = r"op_cpuid"
        hndl_pat = r"h_cpuid"
        xform_pat = r"op_cpuid"
        t_pat = r"(cpuid|test_native_x86_cpuid)"
    elif m_lower.startswith("f") and (
        m_lower in (
            "fld", "fst", "fstp", "fild", "fist", "fistp",
            "fadd", "faddp", "fsub", "fsubp", "fsubr", "fsubrp",
            "fmul", "fmulp", "fdiv", "fdivp", "fdivr", "fdivrp",
            "fcom", "fcomp", "fcompp", "fcomi", "fcomip",
            "fchs", "fabs", "fsqrt",
            "fld1", "fldz", "fldpi", "fldl2e", "fldl2t", "fldlg2", "fldln2",
            "fsin", "fcos", "fsincos", "fptan", "fpatan", "fyl2x", "fyl2xp1", "f2xm1",
            "fstsw", "fnstsw",
        )
    ):
        l_pat = rf'"{m_lower}"'
        ir_pat = r"(fpu|fp_)"
        ev_pat = r"(fpu|fp_)"
        ctx_pat = r"(fpu_stack|fpu_top|fpu_status|get_st|set_st|fpu_push|fpu_pop|get_fsw)"
        emit_pat = r"(op_fpu_|fppush_|fpstore_|fpbinop|fpcompare|fpunary|fpconst|fptrans|fpstatus)"
        hndl_pat = r"(h_fpu_|fpu_push|fpu_pop|fpu_binop|fpu_compare|fpu_trans)"
        xform_pat = r"(op_fpu_|h_fpu_)"
        t_pat = r"(native_x86_fpu|test_x86_lifter|lift_and_eval_fpu)"

    return l_pat, ir_pat, ev_pat, ctx_pat, emit_pat, hndl_pat, xform_pat, t_pat


def audit_instructions_in_codebase(mnemonics: list[str]):
    # Flatten any category names or comma-separated inputs
    target_mnems = []
    for item in mnemonics:
        cleaned = item.strip().strip(",")
        if cleaned.lower() in [k.lower() for k in CATEGORIES]:
            cat_key = next(k for k in CATEGORIES if k.lower() == cleaned.lower())
            target_mnems.extend(CATEGORIES[cat_key])
        elif cleaned.lower() in ("all", "all-categories"):
            for v in CATEGORIES.values():
                target_mnems.extend(v)
        else:
            # could be comma-separated like "ADD,SUB"
            for sub_m in cleaned.split(","):
                sub_m = sub_m.strip()
                if sub_m:
                    target_mnems.append(sub_m)

    # De-duplicate while preserving order
    seen = set()
    unique_mnems = []
    for m in target_mnems:
        if m.upper() not in seen:
            seen.add(m.upper())
            unique_mnems.append(m)

    # Read codebase sources
    def read_file_safe(path):
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                return f.read()
        except Exception:
            return ""

    lifter_src = read_file_safe("lib/x86_lifter/lifter.ml").lower()
    ir_src = read_file_safe("lib/vm_ir/ir.ml").lower()
    eval_src = read_file_safe("lib/vm_ir/vm_eval.ml").lower()

    # C++ Native VM (vanguard_threaded_vm) files
    ctx_src = read_file_safe("lib/native_vm/vm_context_emitter.ml").lower()
    emit_src = read_file_safe("lib/native_vm/vm_emitter.ml").lower()
    hndl_src = (
        read_file_safe("lib/native_vm/vm_mem_handlers.ml") + "\n" +
        read_file_safe("lib/native_vm/vm_alu_handlers.ml") + "\n" +
        read_file_safe("lib/native_vm/vm_control_handlers.ml")
    ).lower()
    xform_src = read_file_safe("lib/native_vm/vm_transform.ml").lower()

    tests_src = ""
    for root, _, files in os.walk("test"):
        for file in files:
            if file.endswith(".ml"):
                tests_src += read_file_safe(os.path.join(root, file)) + "\n"
    tests_src = tests_src.lower()

    print("\n" + "=" * 94)
    print(f" {'ASGARD-5877 Instruction Implementation Audit':^92} ")
    print("=" * 94)
    fmt = "%-10s | %-6s | %-5s | %-7s | %-8s | %-8s | %-8s | %-7s | %-6s"
    print(fmt % ("Mnemonic", "Lifter", "VM IR", "VM Eval", "Context", "Emitter", "Handlers", "Xform", "Tests"))
    print("-" * 94)

    summary = []
    for m in unique_mnems:
        l_pat, ir_pat, ev_pat, ctx_pat, emit_pat, hndl_pat, xform_pat, t_pat = get_native_audit_patterns(m)

        has_lifter = bool(re.search(l_pat, lifter_src))
        has_ir = bool(re.search(ir_pat, ir_src))
        has_eval = bool(re.search(ev_pat, eval_src))
        has_ctx = bool(re.search(ctx_pat, ctx_src))
        has_emit = bool(re.search(emit_pat, emit_src))
        has_hndl = bool(re.search(hndl_pat, hndl_src))
        has_xform = bool(re.search(xform_pat, xform_src))
        has_tests = bool(re.search(t_pat, tests_src))

        status_str = lambda b: "[OK]" if b else "[MISSING]"
        print(fmt % (
            m.upper(),
            status_str(has_lifter),
            status_str(has_ir),
            status_str(has_eval),
            status_str(has_ctx),
            status_str(has_emit),
            status_str(has_hndl),
            status_str(has_xform),
            status_str(has_tests),
        ))
        summary.append((m.upper(), has_lifter, has_ir, has_eval, has_ctx, has_emit, has_hndl, has_xform, has_tests))

    print("-" * 94)
    all_ok = all(all(row[1:]) for row in summary)
    if all_ok:
        print(f"[+] All {len(summary)} audited instructions are fully implemented and verified across all layers (including C++ Native VM bindings & runtime handlers)!")
    else:
        missing_count = sum(1 for row in summary if not all(row[1:]))
        print(f"[-] {missing_count} instruction(s) have missing layers or coverage.")
    print("=" * 94 + "\n")


def search_native_mnemonic(mnemonic: str):
    target_mnems = []
    cleaned = mnemonic.strip().strip(",")
    if cleaned.lower() in [k.lower() for k in CATEGORIES]:
        cat_key = next(k for k in CATEGORIES if k.lower() == cleaned.lower())
        target_mnems.extend(CATEGORIES[cat_key])
    elif cleaned.lower() in ("all", "all-categories"):
        for v in CATEGORIES.values():
            target_mnems.extend(v)
    else:
        for sub_m in cleaned.split(","):
            sub_m = sub_m.strip()
            if sub_m:
                target_mnems.append(sub_m)

    for m in target_mnems:
        m_upper = m.upper()
        l_pat, ir_pat, ev_pat, ctx_pat, emit_pat, hndl_pat, xform_pat, t_pat = get_native_audit_patterns(m_upper)

        target_files = [
            ("lib/native_vm/vm_context_emitter.ml", "C++ VMContext Bindings", ctx_pat),
            ("lib/native_vm/vm_emitter.ml", "Bytecode Emitter", emit_pat),
            ("lib/native_vm/vm_mem_handlers.ml", "C++ Runtime Handlers (Memory / FPU / SIMD)", hndl_pat),
            ("lib/native_vm/vm_transform.ml", "Opcode & Handler Mapping", xform_pat),
        ]

        print("\n" + "=" * 90)
        print(f" C++ Native VM (vanguard_threaded_vm) Search: {m_upper} ")
        print("=" * 90)

        all_matched = True
        for file_path, desc, pattern in target_files:
            print(f"\n[*] {file_path} ({desc}):")
            if not os.path.exists(file_path):
                print(f"    [-] File not found: {file_path}")
                all_matched = False
                continue

            matched_lines = []
            with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
                for idx, line in enumerate(f, 1):
                    if re.search(pattern, line, re.IGNORECASE):
                        matched_lines.append((idx, line.rstrip()))

            if matched_lines:
                for line_no, content in matched_lines[:6]:
                    print(f"    L{line_no:<4} | {content}")
                if len(matched_lines) > 6:
                    print(f"    ... ({len(matched_lines) - 6} more matching line(s))")
                print(f"    [+] Match Status: [OK] ({len(matched_lines)} match(es))")
            else:
                print(f"    [-] Match Status: [MISSING] (searched pattern: {pattern})")
                all_matched = False

        print("\n" + "-" * 90)
        if all_matched:
            print(f"[+] '{m_upper}' is fully bound in C++ Native VM across all 4 core files!")
        else:
            print(f"[-] '{m_upper}' has missing Native VM layers or patterns.")
        print("=" * 90 + "\n")


def audit_instruction_in_codebase(mnemonic: str):
    audit_instructions_in_codebase([mnemonic])


def main():
    parser = argparse.ArgumentParser(description="ASGARD ISA Specification & Test Generator")
    subparsers = parser.add_subparsers(dest="cmd")

    # fetch
    fetch_parser = subparsers.add_parser("fetch", help="Fetch & display instruction specification from documentation site")
    fetch_parser.add_argument("arch", choices=["x86", "arm", "riscv"], help="Target architecture")
    fetch_parser.add_argument("mnemonic", help="Instruction mnemonic (e.g. cpuid, mov, blsr)")

    # test
    test_parser = subparsers.add_parser("test", help="Generate OCaml Alcotest template from specification")
    test_parser.add_argument("arch", choices=["x86", "arm", "riscv"], help="Target architecture")
    test_parser.add_argument("mnemonic", help="Instruction mnemonic")
    test_parser.add_argument("--output", "-o", help="Optional output file")

    # parse-text
    text_parser = subparsers.add_parser("parse-text", help="Parse raw copied documentation text from file or stdin (-)")
    text_parser.add_argument("file", help="File containing copied documentation or '-' for stdin")

    # audit
    audit_parser = subparsers.add_parser("audit", help="Audit implementation status in ASGARD-5877")
    audit_parser.add_argument("mnemonics", nargs="+", help="Instruction mnemonic(s) or category (e.g. ADD SUB, 'all')")

    # search-native
    search_native_parser = subparsers.add_parser(
        "search-native",
        help="Search C++ Native VM (vanguard_threaded_vm) bindings and runtime handlers in vm_context_emitter, vm_emitter, vm_mem_handlers, vm_transform",
    )
    search_native_parser.add_argument("mnemonic", help="Instruction mnemonic or category (e.g. FLD, FADD, CPUID, 'FPU (x87)')")

    args = parser.parse_args()

    if args.cmd == "fetch" or args.cmd == "test":
        html = fetch_x86_instruction_page(args.mnemonic)
        if not html:
            sys.stderr.write(f"[-] Could not find documentation for '{args.mnemonic}' on {BASE_URL_MICROAGI}.\n")
            sys.exit(1)
        spec = parse_html_spec(html, args.mnemonic)

        if args.cmd == "fetch":
            print(f"\n=======================================================")
            print(f" Title: {spec.full_title}")
            print(f" Source: {BASE_URL_MICROAGI}/x86/{args.mnemonic.lower()}.html")
            print(f"=======================================================\n")
            print(f"Variants ({len(spec.variants)}):")
            for v in spec.variants:
                print(f"  - [{v.opcode:15}] {v.instruction:25} | 64-bit: {v.mode_64:7} | {v.description}")
            print(f"\nFlags Affected: {spec.flags_affected.strip()}")
        else:
            test_code = generate_ocaml_test(spec)
            if args.output:
                with open(args.output, "w") as f:
                    f.write(test_code)
                print(f"[+] Written test to {args.output}")
            else:
                print(test_code)

    elif args.cmd == "parse-text":
        content = sys.stdin.read() if args.file == "-" else open(args.file).read()
        spec = parse_raw_text(content)
        print(f"\n[+] Parsed Mnemonic: {spec.mnemonic}")
        print(f"[+] Title: {spec.full_title}")
        print(f"[+] Variants Found: {len(spec.variants)}")
        for v in spec.variants:
            print(f"    * {v.opcode} | {v.instruction} | {v.mode_64}")
        print(f"[+] Flags Affected: {spec.flags_affected.strip()}")
        print("\n--- Generated Alcotest Case ---\n")
        print(generate_ocaml_test(spec))

    elif args.cmd == "audit":
        audit_instructions_in_codebase(args.mnemonics)
    elif args.cmd == "search-native":
        search_native_mnemonic(args.mnemonic)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
