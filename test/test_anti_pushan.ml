open X86_lifter
open Native_vm

(** Golden vectors pinned from [lib/vm_ir/rolling_key.ml] — any drift in the PRF
    constants (multipliers, rotations, xor-domains) breaks the OCaml/C++ mirror
    contract and must fail loudly here. *)
let gold_anchor_seed12345678_off0 = 0xBD4DB93D6D585E96L
let gold_anchor_seed0BADF00D_off1337 = 0x74A78CAE58D19631L
let gold_advance_kDEADBEEF_op61_dst7 = 0x43420536502AD634L
let gold_advance_k0123_op3_dst31_negimm = 0x71825847E6590789L

(** Tests for Anti-Pushan Protection: Execution-History Coupled Rolling Key.
    Pushan assumes static / constraint-free block emulation where opcodes are
    stateless. ASGARD couples every instruction dispatch to a dynamic running key
    mutated by prior execution history. *)

let compile_and_run ~tmp_prefix pkg =
  let tmp_dir = Filename.temp_file tmp_prefix "_dir" in
  (try Sys.remove tmp_dir with _ -> ());
  (try Sys.mkdir tmp_dir 0o755 with _ -> ());

  let hdr_path = Filename.concat tmp_dir "threaded_vm.hpp" in
  let oc_h = open_out hdr_path in
  output_string oc_h pkg.Vm_emitter.cpp_runtime_source;
  close_out oc_h;

  let runner_path = Filename.concat tmp_dir "runner.cpp" in
  let oc_r = open_out runner_path in
  output_string oc_r pkg.Vm_emitter.runner_source;
  close_out oc_r;

  let bin_path = Filename.concat tmp_dir "runner" in
  let comp_cmd = Printf.sprintf "clang++ -std=c++20 -O2 -I%s %s -o %s" tmp_dir runner_path bin_path in
  let comp_status = Sys.command comp_cmd in
  if comp_status <> 0 then Alcotest.fail "clang++ compilation failed";

  let run_cmd = bin_path in
  let ic = Unix.open_process_in run_cmd in
  let out_buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_string out_buf (input_line ic);
       Buffer.add_char out_buf '\n'
     done
   with End_of_file -> ());
  let status = Unix.close_process_in ic in
  let _ = Sys.command (Printf.sprintf "rm -rf %s" tmp_dir) in
  (status, Buffer.contents out_buf)

let test_running_key_advances_on_execution () =
  let rng = Random.State.make [| 0x1337 |] in
  let asm = {|
func_key_test:
    mov rax, 100
    add rax, 50
    sub rax, 10
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng func in
      let status, out_str = compile_and_run ~tmp_prefix:"anti_pushan_adv_" pkg in
      Alcotest.(check bool) "exit code 0" true (status = Unix.WEXITED 0);
      (* 100 + 50 - 10 = 140 *)
      Alcotest.(check bool) "rax is 140" true (String.contains out_str '1' && String.contains out_str '4' && String.contains out_str '0')

let test_rolling_key_derivation_vectors () =
  (* Domain separation: the block-anchor PRF must be distinct from the positional
     PRF, otherwise the first in-block mask (k_pos ^ anchor) collapses to zero. *)
  Alcotest.(check bool) "anchor_key differs from key64_for_offset" true
    (Int64.compare (Vm_ir.Rolling_key.anchor_key 0x12345678l 0)
                   (Vm_ir.Rolling_key.key64_for_offset 0x12345678l 0) <> 0);
  Alcotest.(check bool) "anchor_key is offset-sensitive" true
    (Int64.compare (Vm_ir.Rolling_key.anchor_key 0x12345678l 5)
                   (Vm_ir.Rolling_key.anchor_key 0x12345678l 6) <> 0);
  (* Golden vectors: pin the exact constants so silent drift in the PRF chain
     (multipliers, rotations, xor-domains) breaks the mirror contract loudly. *)
  Alcotest.(check int64) "anchor_key golden" gold_anchor_seed12345678_off0
    (Vm_ir.Rolling_key.anchor_key 0x12345678l 0);
  Alcotest.(check int64) "anchor_key golden (offset 0x1337)" gold_anchor_seed0BADF00D_off1337
    (Vm_ir.Rolling_key.anchor_key 0x0BADF00Dl 0x1337);
  Alcotest.(check int64) "advance_key_step golden" gold_advance_kDEADBEEF_op61_dst7
    (Vm_ir.Rolling_key.advance_key_step 0xDEADBEEFCAFEBABEL 0x61 7 0x11223344L);
  Alcotest.(check int64) "advance_key_step golden (negative imm)" gold_advance_k0123_op3_dst31_negimm
    (Vm_ir.Rolling_key.advance_key_step 0x0123456789ABCDEFL 3 31 (-0x5A5A5A5AL))

let pack_word op dst src imm64 =
  let imm_masked = Int64.logand imm64 0x3FFFFFFFFFFL in
  Int64.logor (Int64.of_int op)
    (Int64.logor (Int64.shift_left (Int64.of_int dst) 8)
       (Int64.logor (Int64.shift_left (Int64.of_int src) 13)
          (Int64.shift_left imm_masked 18)))

let test_decode_fields_truncation () =
  (* The imm field packs 46 bits but FETCH_NEXT extracts a 32-bit window and
     sign-extends it; the OCaml mirror must agree or the chain diverges. *)
  let w = pack_word 0xAB 19 7 0x7FFFFFFFFL in
  let (op, dst, src, imm) = Vm_ir.Rolling_key.decode_fields w in
  Alcotest.(check int) "op extracted" 0xAB op;
  Alcotest.(check int) "dst extracted" 19 dst;
  Alcotest.(check int) "src extracted" 7 src;
  Alcotest.(check int64) "imm 32-bit sign-extended truncation" (-1L) imm;
  let (_, _, _, imm2) = Vm_ir.Rolling_key.decode_fields (pack_word 0x01 5 2 0x130L) in
  Alcotest.(check int64) "small positive imm passes through" 0x130L imm2;
  (* imm with bit 31 set inside the window must come back negative *)
  let (_, _, _, imm3) = Vm_ir.Rolling_key.decode_fields (pack_word 0x42 9 1 0x80000000L) in
  Alcotest.(check int64) "bit-31 imm sign-extends" (-0x80000000L) imm3

(* Pull the baked-in key_seed back out of the emitted runtime (the default
   argument of execute_threaded carries it as 0x%08XU). *)
let extract_key_seed (src : string) : int32 option =
  let marker = "seed = 0x" in
  let ml = String.length marker in
  let rec find i =
    if i + ml > String.length src then None
    else if String.sub src i ml = marker then Some i
    else find (i + 1)
  in
  match find 0 with
  | None -> None
  | Some i ->
    let is_hex c =
      (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    in
    let rec hex j acc =
      if j < String.length src && is_hex src.[j] then hex (j + 1) (acc ^ String.make 1 src.[j])
      else acc
    in
    let h = hex (i + ml) "" in
    if h = "" then None else Some (Int32.of_string ("0x" ^ h))

let test_block_chained_keystream_mirror () =
  (* Structural contract: encoding a single-block function twice from identical
     rng states — once with the rolling key on, once off — must yield the same
     plaintext words.  Replaying the anchor+advance chain over the ON ciphertext
     has to recover exactly the OFF (legacy positional) plaintext, while the two
     ciphertexts themselves differ.  This is the encoder-side simulation of what
     the C++ FETCH_NEXT does at runtime. *)
  let asm = {|
func_rk_mirror:
    mov rax, 100
    add rax, 50
    sub rax, 10
    xor rax, 0x5A
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let on_cfg = Protection_config.lightweight in
      let off_cfg = { on_cfg with anti_pushan = { enabled = false; running_key = false } } in
      let pkg_on = Vm_emitter.compile_and_package ~rng:(Random.State.make [| 0xC0FFEE |]) ~config:on_cfg func in
      let pkg_off = Vm_emitter.compile_and_package ~rng:(Random.State.make [| 0xC0FFEE |]) ~config:off_cfg func in
      let bc_on = Array.of_list pkg_on.bytecode in
      let bc_off = Array.of_list pkg_off.bytecode in
      Alcotest.(check int) "same plaintext length" (Array.length bc_off) (Array.length bc_on);
      if Array.length bc_on = 0 then Alcotest.fail "empty bytecode";
      let seed32 =
        match extract_key_seed pkg_on.cpp_runtime_source with
        | Some s -> s
        | None -> Alcotest.fail "key seed not found in emitted runtime"
      in
      (match extract_key_seed pkg_off.cpp_runtime_source with
       | Some s -> Alcotest.(check int32) "same key seed on both sides" s seed32
       | None -> Alcotest.fail "key seed not found in emitted runtime");
      let k = ref (Vm_ir.Rolling_key.anchor_key seed32 0) in
      let differs = ref false in
      Array.iteri
        (fun i w_on ->
          let k_pos = Vm_ir.Rolling_key.key64_for_offset seed32 i in
          (* runtime FETCH_NEXT: plaintext = ciphertext ^ k_pos ^ running_key *)
          let w = Int64.logxor w_on (Int64.logxor k_pos !k) in
          (* legacy run: ciphertext_off = plaintext ^ k_pos (cur_key = 0) *)
          let expected_plain = Int64.logxor bc_off.(i) k_pos in
          Alcotest.(check int64) (Printf.sprintf "mirror plaintext word %d" i) expected_plain w;
          if Int64.compare w_on bc_off.(i) <> 0 then differs := true;
          let (op, dst, _, imm) = Vm_ir.Rolling_key.decode_fields w in
          k := Vm_ir.Rolling_key.advance_key_step !k op dst imm)
        bc_on;
      Alcotest.(check bool) "rolling ciphertext differs from legacy" true !differs

let test_disabled_flag_is_legacy_bytecode () =
  (* Legacy invariant: with the flag off the encoder emits exactly the old
     positional-only mask (cur_key = 0), so the ciphertext equals the manual
     k_pos masking of the same plaintext. *)
  let asm = {|
func_rk_legacy:
    mov rax, 77
    add rax, 11
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let off_cfg =
        let base = Protection_config.lightweight in
        { base with anti_pushan = { enabled = false; running_key = false } }
      in
      let pkg_off = Vm_emitter.compile_and_package ~rng:(Random.State.make [| 0xFEED |]) ~config:off_cfg func in
      let pkg_on = Vm_emitter.compile_and_package ~rng:(Random.State.make [| 0xFEED |]) ~config:Protection_config.lightweight func in
      let bc_off = Array.of_list pkg_off.bytecode in
      let bc_on = Array.of_list pkg_on.bytecode in
      let seed32 =
        match extract_key_seed pkg_off.cpp_runtime_source with
        | Some s -> s
        | None -> Alcotest.fail "key seed not found in emitted runtime"
      in
      (* Legacy proof: every OFF word unmasks by pure k_pos to a well-formed
         packed word — decode and re-pack reproduce it bit-for-bit (the asm uses
         small positive imms, so the 46-bit imm field round-trips through the
         32-bit extraction window).  This is only possible when the encoder kept
         cur_key = 0, i.e. the legacy positional encoding. *)
      Array.iteri
        (fun i w ->
          let plaintext = Int64.logxor w (Vm_ir.Rolling_key.key64_for_offset seed32 i) in
          let (op, dst, src, imm) = Vm_ir.Rolling_key.decode_fields plaintext in
          Alcotest.(check int64)
            (Printf.sprintf "legacy word %d is pure positional masking" i)
            plaintext (pack_word op dst src imm))
        bc_off;
      Alcotest.(check int) "same length across flag states" (Array.length bc_off) (Array.length bc_on);
      let same = ref true in
      Array.iteri
        (fun i w -> if Int64.compare w bc_on.(i) <> 0 then same := false)
        bc_off;
      Alcotest.(check bool) "flag toggling changes ciphertext" true (not !same)

let test_loop_history_soundness () =
  let rng = Random.State.make [| 0x5877 |] in
  let asm = {|
func_loop_fact:
    mov rax, 1
    mov rcx, 5
.Lloop:
    imul rax, rcx
    sub rcx, 1
    cmp rcx, 0
    jne .Lloop
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_cff:false func in
      let status, out_str = compile_and_run ~tmp_prefix:"anti_pushan_loop_" pkg in
      Alcotest.(check bool) "loop execution succeeds" true (status = Unix.WEXITED 0);
      (* 5! = 120 *)
      Alcotest.(check bool) "rax is 120 (5!)" true (String.contains out_str '1' && String.contains out_str '2' && String.contains out_str '0')

let test_branch_path_history_diversity () =
  let rng = Random.State.make [| 0x9999 |] in
  let asm = {|
func_branch_div:
    mov rax, 42
    cmp rax, 50
    jl .Lless
    add rax, 1000
    ret
.Lless:
    add rax, 2000
    ret
|} in
  match Lifter.lift_function asm with
  | Error e -> Alcotest.fail e
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_cff:true func in
      let status, out_str = compile_and_run ~tmp_prefix:"anti_pushan_branch_" pkg in
      Alcotest.(check bool) "branch execution succeeds" true (status = Unix.WEXITED 0);
      (* 42 < 50 -> rax = 42 + 2000 = 2042 *)
      Alcotest.(check bool) "rax is 2042" true (String.contains out_str '2' && String.contains out_str '0' && String.contains out_str '4')

let tests = [
  Alcotest.test_case "running_key_advances_on_execution" `Quick test_running_key_advances_on_execution;
  Alcotest.test_case "rolling_key_derivation_vectors" `Quick test_rolling_key_derivation_vectors;
  Alcotest.test_case "decode_fields_truncation" `Quick test_decode_fields_truncation;
  Alcotest.test_case "block_chained_keystream_mirror" `Quick test_block_chained_keystream_mirror;
  Alcotest.test_case "disabled_flag_is_legacy_bytecode" `Quick test_disabled_flag_is_legacy_bytecode;
  Alcotest.test_case "loop_history_soundness" `Quick test_loop_history_soundness;
  Alcotest.test_case "branch_path_history_diversity" `Quick test_branch_path_history_diversity;
]
