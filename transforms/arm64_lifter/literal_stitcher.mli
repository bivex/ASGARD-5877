(** ASGARD-5877: ARM64 Literal Stitcher & Disassembler Disrupter
    Based on research from arXiv:2407.08924 & arXiv:2507.07246:
    "Disassembling Obfuscated Executables with LLM" and "Disa" *)

(** Generates a stitched ARM64 machine sequence embedding an opaque literal payload
    disguised as code, using dynamic ADR and branch jumps to disrupt linear disassembly. *)
val stitch_arm64_literal_payload : rng:Random.State.t -> payload:int64 -> string

(** Interleaves literal-stitched dead words and anti-disassembly jump sequences
    into an ARM64 assembly listing. *)
val obfuscate_arm64_asm_sequence : rng:Random.State.t -> string -> string
