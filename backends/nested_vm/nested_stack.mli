(** Multi-VM Nested Stack (VM-in-VM):
    Combinatorial and number-theoretic primitives for nested virtual machine execution.
    Implements OEIS sequences:
    - A000108: Catalan numbers & Dyck word well-nestedness ranking
    - A004001: Hofstadter-Conway $10,000 sequence for self-referential tier dispatch
    - A005228 / A030124: Hofstadter Figure-Figure complementary partition
    - A061775: Matula-Goebel bijective encoding for VM nesting topology
    - A287654 / A249569: Meta-Fibonacci chaotic handoff jitter
*)

(** {1 OEIS A000108: Catalan Numbers & Dyck Words} *)

val catalan : int -> int64
(** [catalan n] returns the n-th Catalan number C_n = (2n)! / ((n+1)! * n!). *)

val is_dyck : bool list -> bool
(** [is_dyck word] tests whether [word] is a valid Dyck word where [true] represents
    an open bracket (EnterVM) and [false] represents a close bracket (ExitVM).
    Requires all prefixes to have count(true) >= count(false), and total counts equal. *)

val dyck_rank : bool list -> int64
(** [dyck_rank word] computes the 0-based lexicographical rank of [word] among
    all Dyck words of the same semilength. Raises [Invalid_argument] if not a Dyck word. *)

(** {1 OEIS A004001: Hofstadter-Conway Tier Dispatch} *)

val precompute_a004001 : int -> int array
(** [precompute_a004001 n] precomputes the first [n] terms of OEIS A004001:
    a(1) = 1, a(2) = 1, a(n) = a(a(n-1)) + a(n - a(n-1)). *)

val a004001_table : int array
(** Precomputed table of the first 256 terms of OEIS A004001. *)

val dispatch_tier : depth:int -> step:int -> int
(** [dispatch_tier ~depth ~step] selects the VM tier for execution step [step]
    using the A004001 self-referential sequence modulo [depth].
    Guarantees tier in range [[0, depth - 1]]. *)

(** {1 OEIS A005228 / A030124: Hofstadter Figure-Figure Partition} *)

val figure_figure_lists : int -> int list * int list
(** [figure_figure_lists n] generates the first [n] terms of A005228 (R, tier slots)
    and A030124 (S, honeypot slots). *)

val is_tier_slot : int -> bool
(** [is_tier_slot slot_idx] returns [true] if [slot_idx] belongs to the tier-owned
    partition (A005228), and [false] if it is a honeypot slot (A030124). *)

(** {1 OEIS A061775: Matula-Goebel Topology Digest} *)

type topology =
  | Leaf of int
  | Branch of int * topology list

val matula_number : topology -> int
(** [matula_number t] computes the Matula-Goebel integer uniquely encoding
    the rooted tree [t]. Leaf = 1; Branch with subtrees T_1..T_k = prod p(matula(T_i)). *)

val topology_digest : ?salt:int64 -> topology -> int64
(** [topology_digest ?salt t] computes a 64-bit cryptographic-grade hash of the
    nesting topology [t] using [Magic_numbers.nested_topology_salt] and SplitMix64 mixing. *)

val chain_topology : depth:int -> topology
(** [chain_topology ~depth] returns a linear nesting chain of depth [depth]. *)

(** {1 OEIS A287654 / A249569: Meta-Fibonacci Handoff Jitter} *)

val handoff_jitter : seed:int64 -> step:int -> int
(** [handoff_jitter ~seed ~step] produces a chaotic jitter in range [0, 15] for
    decorrelating the timing of inter-tier VM handoffs. *)

(** {1 Configuration} *)

type nested_config = {
  enabled : bool;
  max_depth : int;
  salt : int64;
}

val default_nested_config : nested_config
