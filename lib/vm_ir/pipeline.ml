type pipeline_result = {
  original_func : Ir.func;
  diversified_func : Ir.func;
  seed : Seed.t;
  alloc_strategy : Register_allocator.strategy;
  equivalence_verified : bool;
}

let compile ?(seed = Seed.create ()) ?(strategy = Register_allocator.Randomized) ?(verify_equivalence = true) (orig_f : Ir.func) =
  (* Stage 1: Initial Typed IR Verification *)
  match Ir_verify.verify_func orig_f with
  | Error err -> Error (Printf.sprintf "Stage 1 (Initial IR Verify) Failed: %s" (Ir_verify.error_to_string err))
  | Ok () ->
      (* Stage 2: Semantic Diversification (Modular Inverses & Non-Linear MBA) *)
      let sem_f = Semantic_transform.transform_func ~seed orig_f in
      
      (* Stage 3: Superoperator Fusion & Decoy Interleaving *)
      let super_f = Superoperator.transform_func ~seed sem_f in
      
      (* Stage 4: CFG Diversification (Block Splitting, Decoys & Topological Shuffling) *)
      let cfg_f = Cfg_transform.transform ~seed super_f in
      
      (* Stage 5: Register Allocation (LinearScan / Randomized / PressureAware) *)
      let alloc_f = Register_allocator.allocate ~strategy ~seed cfg_f in
      
      (* Stage 6: Final Typed IR Verification *)
      match Ir_verify.verify_func alloc_f with
      | Error err -> Error (Printf.sprintf "Stage 6 (Final IR Verify) Failed: %s" (Ir_verify.error_to_string err))
      | Ok () ->
          (* Stage 7: Differential Semantic Equivalence Check against Golden Reference VM *)
          if verify_equivalence then begin
            match Equivalence.assert_equivalent ~trials:25 orig_f alloc_f with
            | Error disc ->
                Error (Printf.sprintf "Stage 7 (Differential Equivalence Assertion) Failed on trial %d: %s"
                  disc.trial_index disc.details)
            | Ok () ->
                Ok {
                  original_func = orig_f;
                  diversified_func = alloc_f;
                  seed;
                  alloc_strategy = strategy;
                  equivalence_verified = true;
                }
          end else
            Ok {
              original_func = orig_f;
              diversified_func = alloc_f;
              seed;
              alloc_strategy = strategy;
              equivalence_verified = false;
            }
