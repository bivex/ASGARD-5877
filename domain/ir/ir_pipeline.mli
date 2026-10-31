(** End-to-End Verifiable Compiler Transformation Pipeline.
    Connects:
      Parse/Lifter -> Typed IR -> IR Verification
                   -> Semantic Diversification
                   -> CFG Diversification
                   -> Register Allocation
                   -> IR Verification
                   -> Differential Equivalence Assertion. *)

type pipeline_result = {
  original_func : Ir.func;
  diversified_func : Ir.func;
  seed : Seed.t;
  alloc_strategy : Register_allocator.strategy;
  equivalence_verified : bool;
}

val compile :
  ?seed:Seed.t ->
  ?strategy:Register_allocator.strategy ->
  ?verify_equivalence:bool ->
  Ir.func ->
  (pipeline_result, string) result
