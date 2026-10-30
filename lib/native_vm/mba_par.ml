(** Global shared Domainslib Task pool for parallel MBA obfuscation.

    One pool is created lazily on first use and reused for the lifetime of
    the process, avoiding the spawn/teardown overhead that would dominate
    for small inputs.  Pool size = recommended_domain_count - 1 (leaving
    one domain for the main thread). *)

let global_pool () = Random_visa_ports.Domain_pool.global_pool ()
