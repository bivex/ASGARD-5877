open X86_lifter
open Native_vm

let asm = {|
func_verify:
    mov rax, rdi
    xor rax, rsi
    cmp rax, 0xE123
    jne fail

    mov rax, rsi
    imul rax, 0x9E37
    add rax, rdx
    and rax, 0xFFFF
    cmp rax, 0xE892
    jne fail

    mov rax, rcx
    shl rax, 5
    mov r8, rcx
    shr r8, 11
    or rax, r8
    and rax, 0xFFFF
    xor rax, rdx
    cmp rax, 0x80CB
    jne fail

    mov rax, rdi
    add rax, rsi
    add rax, rdx
    add rax, rcx
    and rax, 0xFFFF
    cmp rax, 0x9153
    jne fail

    mov rax, rdi
    shl rax, 48
    mov r8, rsi
    shl r8, 32
    or rax, r8
    mov r8, rdx
    shl r8, 16
    or rax, r8
    or rax, rcx
    ret

fail:
    mov rax, 0
    ret
|}

let () =
  let rng = Random.State.make [| 0x1337BEEF |] in
  match Lifter.lift_function asm with
  | Error err -> failwith err
  | Ok func ->
      let pkg = Vm_emitter.compile_and_package ~rng ~enable_cff:true ~enable_mba:true ~mba_depth:4 func in
      let out_dir = "/Volumes/External/Code/ASGARD-5877/binaries/crackme_arm64" in
      let oc_h = open_out (Filename.concat out_dir "threaded_vm.hpp") in
      output_string oc_h pkg.cpp_runtime_source;
      close_out oc_h;
      let oc_r = open_out (Filename.concat out_dir "runner.cpp") in
      output_string oc_r pkg.runner_source;
      close_out oc_r;
      let oc_b = open_out_bin (Filename.concat out_dir "protected.vanguard") in
      List.iter
        (fun w ->
          for i = 0 to 7 do
            let b = Int64.to_int (Int64.logand (Int64.shift_right_logical w (i * 8)) 0xFFL) in
            output_byte oc_b b
          done)
        pkg.bytecode;
      close_out oc_b;
      print_endline (Metrics.report_to_string pkg.metrics);
      Printf.printf "Successfully emitted VM header & bytecode (%d bytes)\n" (List.length pkg.bytecode * 8)
