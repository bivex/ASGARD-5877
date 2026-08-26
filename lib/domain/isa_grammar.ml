let unwrap = function
  | Ok v -> v
  | Error err -> invalid_arg (Errors.to_string err)


let f_vv_vx_vi = [
  Types.Instruction_format.OP_VV;
  Types.Instruction_format.OP_VX;
  Types.Instruction_format.OP_VI;
]

let f_vv_vx = [
  Types.Instruction_format.OP_VV;
  Types.Instruction_format.OP_VX;
]

let f_mvv = [ Types.Instruction_format.OP_MVV ]
let f_wide = [ Types.Instruction_format.OP_WIDENING ]

let arith_families = [
  unwrap (Instruction_family.make ~mnemonic_base:"vadd" ~klass:Instruction_class.Arith ~weight:10.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.ADD ());
  unwrap (Instruction_family.make ~mnemonic_base:"vsub" ~klass:Instruction_class.Arith ~weight:6.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.SUB ());
  unwrap (Instruction_family.make ~mnemonic_base:"vmul" ~klass:Instruction_class.Arith ~weight:5.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.MUL ());
  unwrap (Instruction_family.make ~mnemonic_base:"vand" ~klass:Instruction_class.Arith ~weight:4.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.AND ());
  unwrap (Instruction_family.make ~mnemonic_base:"vor" ~klass:Instruction_class.Arith ~weight:4.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.OR ());
  unwrap (Instruction_family.make ~mnemonic_base:"vxor" ~klass:Instruction_class.Arith ~weight:3.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.XOR ());
  unwrap (Instruction_family.make ~mnemonic_base:"vsll" ~klass:Instruction_class.Arith ~weight:4.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.SLL ());
  unwrap (Instruction_family.make ~mnemonic_base:"vsrl" ~klass:Instruction_class.Arith ~weight:4.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.SRL ());
  unwrap (Instruction_family.make ~mnemonic_base:"vsra" ~klass:Instruction_class.Arith ~weight:3.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.SRA ());
  unwrap (Instruction_family.make ~mnemonic_base:"vmin" ~klass:Instruction_class.Arith ~weight:2.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.MIN ());
  unwrap (Instruction_family.make ~mnemonic_base:"vmax" ~klass:Instruction_class.Arith ~weight:2.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.MAX ());
  unwrap (Instruction_family.make ~mnemonic_base:"vdiv" ~klass:Instruction_class.Arith ~weight:1.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.DIV ());
  unwrap (Instruction_family.make ~mnemonic_base:"vrem" ~klass:Instruction_class.Arith ~weight:1.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.REM ());
  unwrap (Instruction_family.make ~mnemonic_base:"vneg" ~klass:Instruction_class.Arith ~weight:1.5 ~formats:f_mvv ~unary_op:Types.Unary_op.NEG ());
  unwrap (Instruction_family.make ~mnemonic_base:"vnot" ~klass:Instruction_class.Arith ~weight:1.5 ~formats:f_mvv ~unary_op:Types.Unary_op.NOT ());
  unwrap (Instruction_family.make ~mnemonic_base:"vabs" ~klass:Instruction_class.Arith ~weight:1.0 ~formats:f_mvv ~unary_op:Types.Unary_op.ABS ());
  unwrap (Instruction_family.make ~mnemonic_base:"vclz" ~klass:Instruction_class.Arith ~weight:0.5 ~formats:f_mvv ~unary_op:Types.Unary_op.CLZ ());
  unwrap (Instruction_family.make ~mnemonic_base:"vctz" ~klass:Instruction_class.Arith ~weight:0.5 ~formats:f_mvv ~unary_op:Types.Unary_op.CTZ ());
  unwrap (Instruction_family.make ~mnemonic_base:"vcpop" ~klass:Instruction_class.Arith ~weight:0.5 ~formats:f_mvv ~unary_op:Types.Unary_op.CPOP ());
]

let saturating_families = [
  unwrap (Instruction_family.make ~mnemonic_base:"vsadd" ~klass:Instruction_class.Saturating ~weight:2.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.SADD ());
  unwrap (Instruction_family.make ~mnemonic_base:"vssub" ~klass:Instruction_class.Saturating ~weight:2.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.SSUB ());
]

let widening_families = [
  unwrap (Instruction_family.make ~mnemonic_base:"vwadd" ~klass:Instruction_class.Widening ~weight:3.0 ~formats:f_wide ~binary_op:Types.Binary_op.ADD ~is_widening:true ());
  unwrap (Instruction_family.make ~mnemonic_base:"vwsub" ~klass:Instruction_class.Widening ~weight:3.0 ~formats:f_wide ~binary_op:Types.Binary_op.SUB ~is_widening:true ());
  unwrap (Instruction_family.make ~mnemonic_base:"vwmul" ~klass:Instruction_class.Widening ~weight:2.0 ~formats:f_wide ~binary_op:Types.Binary_op.MUL ~is_widening:true ());
]

let compare_families = [
  unwrap (Instruction_family.make ~mnemonic_base:"vmseq" ~klass:Instruction_class.Compare ~weight:3.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.CMPEQ ());
  unwrap (Instruction_family.make ~mnemonic_base:"vmsne" ~klass:Instruction_class.Compare ~weight:3.0 ~formats:f_vv_vx_vi ~binary_op:Types.Binary_op.CMPNE ());
  unwrap (Instruction_family.make ~mnemonic_base:"vmslt" ~klass:Instruction_class.Compare ~weight:2.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.CMPLT ());
  unwrap (Instruction_family.make ~mnemonic_base:"vmsge" ~klass:Instruction_class.Compare ~weight:2.0 ~formats:f_vv_vx ~binary_op:Types.Binary_op.CMPGE ());
]

let family_catalog = [
  (Instruction_class.Arith, arith_families);
  (Instruction_class.Saturating, saturating_families);
  (Instruction_class.Widening, widening_families);
  (Instruction_class.Compare, compare_families);
]

let families_for cls =
  match List.assoc_opt cls family_catalog with
  | Some fams -> fams
  | None -> []

let lookup_family base_name =
  let rec search = function
    | [] -> None
    | (_, fams) :: rest -> (
        match List.find_opt (fun (fam : Instruction_family.t) -> fam.mnemonic_base = base_name) fams with
        | Some f -> Some f
        | None -> search rest)
  in
  search family_catalog

let available_profiles () = [ "rvv-like"; "uniform" ]

let get_profile = function
  | "rvv-like" -> Ok Generation_profile.rvv_like
  | "uniform" -> Ok Generation_profile.uniform
  | other ->
      Error
        (Errors.Invalid_profile
           (Printf.sprintf "Unknown generation profile '%s' (available: %s)" other
              (String.concat ", " (available_profiles ()))))

let sample_family ~rng ~profile ~candidates =
  let weights =
    List.map
      (fun (fam : Instruction_family.t) ->
        Generation_profile.weight_for profile fam.klass *. fam.weight)
      candidates
  in
  let total = List.fold_left ( +. ) 0.0 weights in
  let threshold = Random.State.float rng total in
  let rec pick acc = function
    | [], _ -> List.hd candidates
    | [ c ], _ -> c
    | c :: cs, w :: ws ->
        let acc' = acc +. w in
        if threshold < acc' then c else pick acc' (cs, ws)
    | c :: _, [] -> c
  in
  pick 0.0 (candidates, weights)


let assign_encodings families =
  let ordered =
    List.sort
      (fun (a : Instruction_family.t) (b : Instruction_family.t) ->
        Stdlib.compare b.weight a.weight)
      families
  in
  let allocated_f6 = Hashtbl.create 64 in
  let allocate_for_family fam =
    let rec find_f6 candidate =
      if candidate >= 64 then
        Error (Errors.Encoding_space_exhausted fam.Instruction_family.mnemonic_base)
      else if Hashtbl.mem allocated_f6 candidate then
        find_f6 (candidate + 1)
      else begin
        Hashtbl.add allocated_f6 candidate ();
        Ok candidate
      end
    in
    find_f6 0
  in
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | fam :: rest -> (
        match allocate_for_family fam with
        | Ok f6 -> loop ((fam, f6) :: acc) rest
        | Error err -> Error err)
  in
  loop [] ordered

let generate_isa
    ~rng
    ?(name = "RVV_Custom_ISA")
    ?(config = Vector_config.default)
    ?(profile = Generation_profile.rvv_like)
    ~num_instructions
    () =
  if num_instructions < 1 then
    Error (Errors.General_error (Printf.sprintf "num_instructions must be >= 1, got %d" num_instructions))
  else
    let remaining =
      ref (
        List.concat_map
          (fun cls -> families_for cls)
          (Generation_profile.enabled_classes profile)
      )
    in
    if !remaining = [] then
      Error (Errors.Invalid_profile (Printf.sprintf "Profile '%s' enables classes with no families" profile.name))
    else
      let chosen = ref [] in
      let planned = ref 0 in
      while !planned < num_instructions && !remaining <> [] do
        let fam = sample_family ~rng ~profile ~candidates:!remaining in
        chosen := fam :: !chosen;
        remaining := List.filter (fun (f : Instruction_family.t) -> f.mnemonic_base <> fam.mnemonic_base) !remaining;
        planned := !planned + List.length fam.formats
      done;

      if !planned < num_instructions then
        Error
          (Errors.Family_catalog_exhausted
             (Printf.sprintf "%d/%d variants planned" !planned num_instructions))
      else
        match assign_encodings !chosen with
        | Error err -> Error err
        | Ok family_encodings ->
            let spec = Vector_isa_spec.make ~name ~config () in
            let budget = ref num_instructions in
            let rec add_variants current_spec = function
              | [] -> Ok current_spec
              | (fam, funct6) :: rest_fams ->
                  if !budget <= 0 then Ok current_spec
                  else
                    let formats_to_use =
                      if List.length fam.Instruction_family.formats > !budget then
                        (* Take budget elements deterministically from formats *)
                        let rec take n = function
                          | [] -> []
                          | _ when n <= 0 -> []
                          | x :: xs -> x :: take (n - 1) xs
                        in
                        take !budget fam.Instruction_family.formats
                      else fam.Instruction_family.formats
                    in
                    let rec process_formats spec_acc = function
                      | [] -> add_variants spec_acc rest_fams
                      | fmt :: rest_fmts ->
                          if !budget <= 0 then add_variants spec_acc rest_fams
                          else
                            let funct3 = Types.Instruction_format.to_funct3 fmt in
                            let mnemonic =
                              Printf.sprintf "%s_%s" fam.Instruction_family.mnemonic_base
                                (Types.Instruction_format.to_suffix fmt)
                            in
                            let description =
                              Printf.sprintf "Synthesized %s family '%s' variant (%s)"
                                (Instruction_class.to_string fam.klass)
                                fam.mnemonic_base
                                (Types.Instruction_format.to_string fmt)
                            in
                            let inst =
                              Vector_instruction.make
                                ~mnemonic
                                ~format:fmt
                                ~funct6
                                ~funct3
                                ~opcode:0x57
                                ?binary_op:fam.binary_op
                                ?unary_op:fam.unary_op
                                ~element_kind:fam.element_kind
                                ~is_widening:fam.is_widening
                                ~description
                                ~sew:config.default_sew
                                ()
                            in
                            match Vector_isa_spec.add_instruction spec_acc inst with
                            | Error err -> Error err
                            | Ok next_spec ->
                                decr budget;
                                process_formats next_spec rest_fmts
                    in
                    process_formats current_spec formats_to_use
            in
            add_variants spec family_encodings
