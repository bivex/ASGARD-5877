open Vm_ir

let test_roundtrip () =
  let rng = Random.State.make [| 42; 1337 |] in
  for _ = 1 to 1000 do
    let codec = Ring_codec.gen ~rng () in
    let x = Random.State.int64 rng Int64.max_int in
    let encoded = Ring_codec.encode codec x in
    let decoded = Ring_codec.decode codec encoded in
    Alcotest.(check int64) "roundtrip" x decoded
  done

let test_homomorphic () =
  let rng = Random.State.make [| 999; 888 |] in
  for _ = 1 to 1000 do
    let codec = Ring_codec.gen ~rng () in
    let x = Random.State.int64 rng Int64.max_int in
    let y = Random.State.int64 rng Int64.max_int in
    let enc_x = Ring_codec.encode codec x in
    let enc_y = Ring_codec.encode codec y in
    
    (* Homomorphic add: enc_x + enc_y + fixup == encode(x + y) *)
    let sum_enc = Int64.add (Int64.add enc_x enc_y) (Ring_codec.hom_add_fixup codec) in
    Alcotest.(check int64) "homomorphic add" (Int64.add x y) (Ring_codec.decode codec sum_enc);

    (* Homomorphic sub: enc_x - enc_y + fixup == encode(x - y) *)
    let diff_enc = Int64.add (Int64.sub enc_x enc_y) (Ring_codec.hom_sub_fixup codec) in
    Alcotest.(check int64) "homomorphic sub" (Int64.sub x y) (Ring_codec.decode codec diff_enc)
  done

let test_pipeline_equivalence () =
  let entry = Ir.make_block ~id:0 ~label:"entry" ~instrs:[
    Ir.Mov { dst = Ir.Reg Register.rax; src = Ir.Imm 100L };
    Ir.Mov { dst = Ir.Reg Register.rcx; src = Ir.Imm 25L };
    Ir.Alu { op = Ir.Add; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Reg Register.rcx; set_flags = false };
    Ir.Alu { op = Ir.Sub; dst = Register.rax; src1 = Ir.Reg Register.rax; src2 = Ir.Imm 15L; set_flags = false };
    Ir.Ret;
  ] in
  let func = Ir.make_func ~name:"test_codec_func" ~entry_id:0 ~blocks:[entry] in
  let seed = Seed.create ~master_seed:0x123456789ABCDEF0L () in
  let cfg = Codec_pass.default_config (Seed.codec_seed seed) in
  let transformed = Codec_pass.transform_func ~cfg func in
  match Equivalence.assert_equivalent ~trials:25 func transformed with
  | Ok () -> ()
  | Error disc -> Alcotest.fail (Printf.sprintf "Equivalence mismatch: %s" disc.details)

let tests = [
  Alcotest.test_case "roundtrip" `Quick test_roundtrip;
  Alcotest.test_case "homomorphic" `Quick test_homomorphic;
  Alcotest.test_case "pipeline_equivalence" `Quick test_pipeline_equivalence;
]
