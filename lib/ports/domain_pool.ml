(** Global shared Domainslib task pool.

    Created lazily on first use; reused for the process lifetime.
    Size = recommended_domain_count - 1 (main domain runs the coordinator).

    Safe to call from any thread; protected by a mutex. *)

(** Minimum number of work items before we pay the parallel_for overhead.
    Below this threshold we fall back to a sequential Array.iter / Array.init. *)
let min_parallel_n = 64

let pool_ref : Domainslib.Task.pool option ref = ref None
let pool_mutex = Mutex.create ()

let global_pool () =
  Mutex.lock pool_mutex;
  let p =
    match !pool_ref with
    | Some p -> p
    | None ->
        let n = max 1 (Domain.recommended_domain_count () - 1) in
        let p = Domainslib.Task.setup_pool ~num_domains:n () in
        pool_ref := Some p;
        p
  in
  Mutex.unlock pool_mutex;
  p

(** Pre-warm the pool so the first packaging call finds running workers.
    Call once at program startup (e.g. from [Protect_pipeline.run]). *)
let warm () = ignore (global_pool ())

(** [parallel_for pool ~n body] dispatches [body] over [0..n-1] in parallel
    when [n >= min_parallel_n], otherwise runs sequentially on the main domain. *)
let parallel_for pool ~n body =
  if n < min_parallel_n then
    for i = 0 to n - 1 do body i done
  else
    Domainslib.Task.run pool (fun () ->
      Domainslib.Task.parallel_for pool ~start:0 ~finish:(n - 1) ~body)

(** [parallel_array_map pool arr f] maps [f] over [arr] in parallel (or
    sequentially for small arrays) and returns results in index order. *)
let parallel_array_map pool arr f =
  let n = Array.length arr in
  if n = 0 then [||]
  else begin
    let results = Array.make n (f arr.(0)) in
    parallel_for pool ~n:(n - 1) (fun i -> results.(i + 1) <- f arr.(i + 1));
    results
  end
