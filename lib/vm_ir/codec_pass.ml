(** Codec Pass — wraps immediate-load registers in per-seed affine ring codecs.
    Within each block, uses one fresh codec per block (seeded by block_id xor seed).
    Arithmetic on encoded values is rewritten homomorphically (Add/Sub only).
    Any non-homomorphic use (Cmp, Test, set_flags=true, Mem base, Div, Xor, And,
    variable shifts, Xchg, Push, Call, special registers) triggers an eager decode before use. *)

open Ir

type config = {
  codec_rate : int;   (** 0..100 probability of encoding each Mov r, Imm *)
  seed       : int64;
}

let default_config seed = { codec_rate = 70; seed }

type reg_state =
  | Plain
  | Encoded of Ring_codec.t

let is_eligible_reg = function
  | Register.Gpr (Register.RSP, _) -> false
  | Register.Gpr (_, Register.B64) -> true
  | _ -> false

let is_homomorphic_alu = function
  | Add | Sub -> true
  | _ -> false

let process_block ~cfg (b : basic_block) : basic_block =
  let rng_seed = Int64.logxor cfg.seed (Int64.of_int (b.id lxor 0x5EED_C0DE)) in
  let block_rng = Seed.make_rng rng_seed in
  let block_codec = Ring_codec.gen ~rng:block_rng () in
  let env : (Register.t, reg_state) Hashtbl.t = Hashtbl.create 16 in
  let get_state r = match Hashtbl.find_opt env r with Some s -> s | None -> Plain in
  let set_state r s = Hashtbl.replace env r s in

  let decode_all acc =
    let pairs = Hashtbl.fold (fun r state acc -> (r, state) :: acc) env [] in
    let sorted_pairs = List.sort (fun (r1, _) (r2, _) -> Stdlib.compare r1 r2) pairs in
    let dec = List.concat_map (fun (r, state) ->
      match state with
      | Encoded codec -> Ring_codec.emit_decode ~t:codec ~dst:r
      | Plain -> []
    ) sorted_pairs in
    Hashtbl.reset env;
    acc @ dec
  in

  let force_decode r acc =
    match get_state r with
    | Plain -> acc
    | Encoded codec ->
        set_state r Plain;
        acc @ Ring_codec.emit_decode ~t:codec ~dst:r
  in

  let force_decode_operand op acc =
    match op with
    | Reg r -> force_decode r acc
    | Imm _ | Mem _ -> acc
  in

  let force_decode_mem_base m acc =
    let acc = match m.base with Some r -> force_decode r acc | None -> acc in
    match m.index with Some (r, _) -> force_decode r acc | None -> acc
  in

  let process_instr acc instr =
    match instr with
    | Mov { dst = Reg r; src = Imm c } when is_eligible_reg r ->
        let probe = Random.State.int block_rng 100 in
        if probe < cfg.codec_rate then begin
          let enc_c = Ring_codec.encode block_codec c in
          set_state r (Encoded block_codec);
          acc @ [ Mov { dst = Reg r; src = Imm enc_c } ]
        end else begin
          set_state r Plain;
          acc @ [ instr ]
        end

    | Mov { dst = Reg r; src = Reg src_r } when is_eligible_reg r ->
        let s = get_state src_r in
        set_state r s;
        acc @ [ instr ]

    | Mov { dst = Reg r; src = Reg src_r } ->
        let acc = force_decode src_r acc in
        set_state r Plain;
        acc @ [ instr ]

    | Mov { dst = Reg r; _ } ->
        set_state r Plain;
        acc @ [ instr ]

    | Alu { op; dst; src1 = Reg r1; src2 = Reg r2; set_flags = false } when
        is_homomorphic_alu op && is_eligible_reg dst && is_eligible_reg r1 && is_eligible_reg r2 ->
        let s1 = get_state r1 in
        let s2 = get_state r2 in
        (match s1, s2 with
        | Encoded c1, Encoded c2 when c1.Ring_codec.a = c2.Ring_codec.a
                                   && c1.Ring_codec.b = c2.Ring_codec.b ->
            let fixup = match op with
              | Add -> Ring_codec.hom_add_fixup c1
              | Sub -> Ring_codec.hom_sub_fixup c1
              | _ -> 0L
            in
            set_state dst (Encoded c1);
            acc @ [
              Alu { op; dst; src1 = Reg r1; src2 = Reg r2; set_flags = false };
              Alu { op = Add; dst; src1 = Reg dst; src2 = Imm fixup; set_flags = false };
            ]
        | _ ->
            let acc = force_decode r1 acc in
            let acc = force_decode r2 acc in
            set_state dst Plain;
            acc @ [ Alu { op; dst; src1 = Reg r1; src2 = Reg r2; set_flags = false } ])

    | Alu { op; dst; src1 = Reg r1; src2 = Imm imm; set_flags = false } when
        is_homomorphic_alu op && is_eligible_reg dst && is_eligible_reg r1 ->
        let s1 = get_state r1 in
        (match s1 with
        | Encoded c1 ->
            (* Homomorphic add/sub of constant: phi(x +/- c) = phi(x) +/- a*c *)
            let scaled_imm = Int64.mul c1.Ring_codec.a imm in
            set_state dst (Encoded c1);
            acc @ [ Alu { op; dst; src1 = Reg r1; src2 = Imm scaled_imm; set_flags = false } ]
        | Plain ->
            set_state dst Plain;
            acc @ [ Alu { op; dst; src1 = Reg r1; src2 = Imm imm; set_flags = false } ])

    | Alu { op; dst; src1; src2; set_flags } ->
        let acc = if set_flags then decode_all acc
                  else (let acc = force_decode_operand src1 acc in force_decode_operand src2 acc) in
        set_state dst Plain;
        acc @ [ Alu { op; dst; src1; src2; set_flags } ]

    | Unary { op; dst; src; set_flags } ->
        let acc = if set_flags then decode_all acc else force_decode_operand src acc in
        set_state dst Plain;
        acc @ [ Unary { op; dst; src; set_flags } ]

    | Cmp _ | Ccmp _ | Ccmn _ | Test _ | Fp_ccmp _ ->
        let acc = decode_all acc in
        acc @ [ instr ]

    | Mov { dst = Mem m; src } ->
        let acc = force_decode_mem_base m acc in
        let acc = force_decode_operand src acc in
        acc @ [ instr ]

    | Push op ->
        let acc = force_decode_operand op acc in
        acc @ [ instr ]

    | Pop (Reg r) ->
        set_state r Plain;
        acc @ [ instr ]

    | Xchg (a, b) ->
        let acc = force_decode_operand a acc in
        let acc = force_decode_operand b acc in
        acc @ [ instr ]

    | Call _ ->
        let acc = decode_all acc in
        acc @ [ instr ]

    | Ret | Vm_exit | Jmp _ | Jcc _ | Trap _ ->
        let acc = decode_all acc in
        acc @ [ instr ]

    | Lea { dst; addr } ->
        let acc = force_decode_mem_base addr acc in
        set_state dst Plain;
        acc @ [ instr ]

    (* Fp_conv: src is a GPR read by the FP unit; dst receives the GPR result.
       Decode src before use; dst is thereafter plain. *)
    | Fp_conv { dst; src; _ } ->
        let acc = force_decode src acc in
        set_state dst Plain;
        acc @ [ instr ]
    | Pinsr { src2; _ } ->
        let acc = force_decode_operand src2 acc in
        acc @ [ instr ]

    | Pextr { dst; _ } ->
        let acc = match dst with Reg r -> set_state r Plain; acc | _ -> acc in
        acc @ [ instr ]


    (* Atomic_mem: addr and src are GPR inputs; dst receives the old memory
       value (GPR output).  Decode all three live inputs before use. *)
    | Atomic_mem { dst; addr; src; _ } ->
        let acc = force_decode addr acc in
        let acc = force_decode src  acc in
        set_state dst Plain;
        acc @ [ instr ]

    (* Cmov: reads flags and src, writes dst. *)
    | Cmov { dst; src; _ } ->
        let acc = force_decode_operand src acc in
        set_state dst Plain;
        acc @ [ instr ]

    (* Setcc: writes dst (no GPR inputs beyond flags). *)
    | Setcc { dst = Reg r; _ } ->
        set_state r Plain;
        acc @ [ instr ]

    | other -> acc @ [ other ]
  in

  let new_instrs = List.fold_left process_instr [] b.instrs in
  let final_instrs = decode_all new_instrs in
  { b with instrs = final_instrs }

let transform_func ~cfg (f : func) : func =
  let block_ids =
    Hashtbl.fold (fun id _ acc -> id :: acc) f.cfg.blocks []
    |> List.sort Int.compare
  in
  let new_blocks = Hashtbl.create (Hashtbl.length f.cfg.blocks) in
  List.iter (fun id ->
    match Hashtbl.find_opt f.cfg.blocks id with
    | Some b ->
        let tb = process_block ~cfg b in
        Hashtbl.replace new_blocks id tb
    | None -> ()
  ) block_ids;
  { f with cfg = { f.cfg with blocks = new_blocks } }
