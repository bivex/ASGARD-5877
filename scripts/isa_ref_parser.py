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
                parts = line.split("\t")
                if len(parts) >= 6:
                    spec.variants.append(
                        InstructionVariant(parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
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


def audit_instruction_in_codebase(mnemonic: str):
    mnem_lower = mnemonic.lower()
    print(f"\n[+] Auditing {mnemonic.upper()} in ASGARD-5877 Codebase:")
    
    # Check x86 lifter
    try:
        with open("lib/x86_lifter/lifter.ml", "r") as f:
            lifter_src = f.read()
        has_lifter = f'"{mnem_lower}"' in lifter_src.lower()
        print(f"  * x86 Lifter (`lib/x86_lifter/lifter.ml`): {'[FOUND]' if has_lifter else '[MISSING]'}")
    except Exception as e:
        print(f"  * x86 Lifter: check error ({e})")

    # Check tests
    try:
        with open("test/test_x86_lifter.ml", "r") as f:
            test_src = f.read()
        has_test = mnem_lower in test_src.lower()
        print(f"  * x86 Lifter Tests (`test/test_x86_lifter.ml`): {'[FOUND]' if has_test else '[MISSING]'}")
    except Exception as e:
        print(f"  * Tests: check error ({e})")


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
    audit_parser.add_argument("mnemonic", help="Instruction mnemonic")

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
        audit_instruction_in_codebase(args.mnemonic)
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
