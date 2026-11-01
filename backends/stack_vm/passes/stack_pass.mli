(** Formal Pass Contracts and Verifiable Boundaries (P2)
    ─────────────────────────────────────────────────────
    Wraps compiler and transformation passes with formal pre- and post-condition
    contracts to guarantee invariant preservation across transformation stages.
*)


type ('a, 'b) pass = {
  name : string;
  run : 'a -> 'b;
  pre_check : ('a -> (unit, string) result) option;
  post_check : ('b -> (unit, string) result) option;
}

val make_pass :
  name:string ->
  ?pre:('a -> (unit, string) result) ->
  ?post:('b -> (unit, string) result) ->
  ('a -> 'b) ->
  ('a, 'b) pass

val run_pass : ('a, 'b) pass -> 'a -> ('b, string) result

val run_pipeline : ('a, 'a) pass list -> 'a -> ('a, string) result
