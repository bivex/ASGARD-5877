open Random_visa_domain

let run ~rng ?(name = "RVV_Custom_ISA") ?(config = Vector_config.default) ?profile ~num_instructions () =
  let prof =
    match profile with
    | Some p -> p
    | None -> Generation_profile.rvv_like
  in
  Isa_grammar.generate_isa ~rng ~name ~config ~profile:prof ~num_instructions ()
