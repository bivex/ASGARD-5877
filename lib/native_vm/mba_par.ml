(** Global shared Domainslib Task pool for parallel MBA obfuscation.

    One pool is created lazily on first use and reused for the lifetime of
    the process, avoiding the spawn/teardown overhead that would dominate
    for small inputs.  Pool size = recommended_domain_count - 1 (leaving
    one domain for the main thread). *)

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
