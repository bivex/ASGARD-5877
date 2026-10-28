(* lib/rd_jit_vm/nano_jit_slot.ml
   ASGARD-5877: Sealed Nano-JIT Slot Arena & Inter-Chunk Hardening

   OEIS catalogue (docs/OEIS_MATHEMATICAL_SEQUENCES.md):
   - A269160  Rule 30 cellular automaton       -> wipe gamma of every slot
   - A003022  Golomb ruler {0,1,4,9,11}        -> placement of the active slots
   - A000201/A001950 Beatty-Wythoff partition  -> real vs honeypot arena units
   - A001511  Ruler function v2(2t)            -> fractal tiered invalidation
   - A000695  Moser-de Bruijn                  -> carry-free operand blinding
   - A000166  Derangements                     -> gprs shuffle between chunks
   - A002487  Stern's diatomic series          -> odd affine transfer factors
   - A010060  Thue-Morse                       -> dummy opcode positions

   The OCaml half seals chunks at packaging time; the EDSL half builds the
   typed C++20 controller that materializes, executes, shuffles and wipes
   them at run time.  Every constant is shared through Magic_numbers. *)

open Int64
module Magic_numbers = Random_visa_constants.Magic_numbers

let nano_slot_bytes = 128
let nano_slot_words = 16
let nano_max_chunk_instrs = 8
let golomb5_marks = [|
  Magic_numbers.golomb5_m0;
  Magic_numbers.golomb5_m1;
  Magic_numbers.golomb5_m2;
  Magic_numbers.golomb5_m3;
  Magic_numbers.golomb5_m4 |]
let nano_active_slots = Array.length golomb5_marks
let nano_arena_units = 12 (* units 0..11 cover the G5 span and its honeypots *)
let nano_kolakoski_scale = 2

(* ------------------------------------------------------------------ *)
(* OEIS generators (OCaml side, mirrored by the emitted C++ runtime)   *)
(* ------------------------------------------------------------------ *)

let rotl64 (x : int64) (n : int) : int64 =
  logor (shift_left x n) (shift_right_logical x (64 - n))

let rotr64 (x : int64) (n : int) : int64 =
  logor (shift_right_logical x n) (shift_left x (64 - n))

(* OEIS A269160 - Wolfram Rule 30 step on a 64-bit ring:
     step(x) = rotl(x, 1) ^ (x | rotr(x, 1)).
   The OR/XOR coupling is non-linear over GF(2): symbolic inversion of the
   key explodes the SAT clause count (no Gaussian elimination). *)
let rule30_step (x : int64) : int64 =
  logxor (rotl64 x 1) (logor x (rotr64 x 1))

(* SplitMix64 word of the transport keystream (sealing only; wiping uses
   Rule 30 above). *)
let keystream_word (key : int64) (nonce : int64) (word_idx : int) : int64 =
  let z = add key (logxor nonce (mul (of_int word_idx) Magic_numbers.golden_ratio_64)) in
  let z = mul (logxor z (shift_right_logical z 30)) Magic_numbers.splitmix64_gamma in
  let z = mul (logxor z (shift_right_logical z 27)) Magic_numbers.splitmix64_mix in
  logxor z (shift_right_logical z 31)

(* Rule 30 wipe gamma for word [w]: gamma_w = R30^(w+1)(key ^ nonce ^ salt).
   Every slot wipe draws fresh, non-linear words. *)
let wipe_gamma_word (key : int64) (nonce : int64) (w : int) : int64 =
  let seed = logxor (logxor key nonce) Magic_numbers.rule30_salt in
  let rec advance st = function
    | 0 -> st
    | k -> advance (rule30_step st) (k - 1)
  in
  advance seed (1 + (w mod nano_slot_words))

(* OEIS A000695 - Moser-de Bruijn carry-free split.  Every N decomposes
   uniquely as N = X + 2Y with X, Y in A000695 (X on even bit positions,
   2Y on odd), so X + 2Y = X xor 2Y: no carries ever cross the planes.
   [moser_pack] compacts the two planes into one 64-bit word (even bits ->
   low half, odd bits -> high half); [moser_unpack] is the exact inverse,
   so the compiler may recombine the planes with ADD or XOR alike. *)
let morton_compact (t : int64) : int64 =
  let t = logand t Magic_numbers.even_bit_mask in
  let step t s m = logand (logor t (shift_right_logical t s)) m in
  let t = step t 1 0x3333333333333333L in
  let t = step t 2 0x0F0F0F0F0F0F0F0FL in
  let t = step t 4 0x00FF00FF00FF00FFL in
  let t = step t 8 0x0000FFFF0000FFFFL in
  step t 16 0x00000000FFFFFFFFL

let morton_spread (t : int64) : int64 =
  let t = logand t 0xFFFFFFFFL in  (* only the compacted 32-bit plane *)
  let step t s m = logand (logor t (shift_left t s)) m in
  let t = step t 16 0x0000FFFF0000FFFFL in
  let t = step t 8 0x00FF00FF00FF00FFL in
  let t = step t 4 0x0F0F0F0F0F0F0F0FL in
  let t = step t 2 0x3333333333333333L in
  step t 1 Magic_numbers.even_bit_mask

let moser_pack (v : int64) : int64 =
  logor (morton_compact v) (shift_left (morton_compact (shift_right_logical v 1)) 32)

let moser_unpack (w : int64) : int64 =
  logor (morton_spread w) (shift_left (morton_spread (shift_right_logical w 32)) 1)

(* OEIS A000002 - Kolakoski self-describing word 1,2,2,1,1,2,1,2,2,1,...
   whose run lengths equal the word itself.  Chunk fission sizes come from
   its run lengths scaled by [nano_kolakoski_scale]: chunk boundaries are
   self-descriptive but aperiodic. *)
let kolakoski (n : int) : int array =
  if n <= 0 then [||]
  else if n = 1 then [| 1 |]
  else
    let buf = Array.make (Stdlib.max n 16) 0 in
    buf.(0) <- 1;
    buf.(1) <- 2;
    buf.(2) <- 2;
    let r = ref 2 in
    let i = ref 3 in
    while !i < n do
      let v = if !r mod 2 = 0 then 1 else 2 in
      let len = buf.(!r) in
      for _ = 1 to len do
        if !i < n then begin
          buf.(!i) <- v;
          incr i
        end
      done;
      incr r
    done;
    Array.sub buf 0 n

(* OEIS A002487 - Stern's diatomic series: a(0)=0, a(1)=1, a(2n)=a(n),
   a(2n+1)=a(n)+a(n+1); consecutive terms are coprime.  alpha_n = 2a(n)+1
   is odd, hence a unit of Z_2^64. *)
let stern_alphas : int64 array =
  let count = 64 in
  let a = Array.make (2 * count + 2) 0L in
  a.(1) <- 1L;
  for k = 1 to count do
    a.(2 * k) <- a.(k);
    a.(2 * k + 1) <- add a.(k) a.(k + 1)
  done;
  Array.init count (fun i -> add (mul 2L a.(i + 1)) 1L)

(* OEIS A000201 / A001950 - branchless Beatty classification of arena unit
   [u] (Rayleigh theorem: floor(n*phi) and floor(n*phi^2) partition N+).
   Unit u is a real (executable) unit iff floor((u+1)/phi) > floor(u/phi),
   computed as a high multiply by golden_ratio_64 = floor(2^64/phi); no
   lookup table is consulted. *)
let beatty_mulhi (u : int64) (c : int64) : int64 =
  (* floor(u*c / 2^64) for u < 2^16, exact in 64-bit arithmetic. *)
  let c1 = shift_right_logical c 32 in
  let c0 = logand c 0xFFFFFFFFL in
  shift_right_logical
    (add (mul u c1) (shift_right_logical (mul u c0) 32))
    32

let beatty_is_real (u : int) : bool =
  let u = of_int u in
  beatty_mulhi (add u 1L) Magic_numbers.golden_ratio_64
  > beatty_mulhi u Magic_numbers.golden_ratio_64

(* OEIS A000166 - derangement tables for the inter-chunk gprs shuffle,
   packed one nibble per slot (nibble i = pi(i)); index 4 is the identity
   used at external-call ABI boundaries. *)
let derangement_tables : int64 array =
  [|
    Magic_numbers.derangement16_rot1;
    Magic_numbers.derangement16_rev;
    Magic_numbers.derangement16_swap;
    Magic_numbers.derangement16_rot7;
  |]

let identity16_packed : int64 =
  Array.fold_left (fun acc i -> logor acc (shift_left (of_int i) (4 * i))) 0L
    (Array.init 16 Fun.id)

let perm_tables : int64 array =
  Array.append derangement_tables [| identity16_packed |]

let perm_identity_index = 4

let perm_apply (packed : int64) (i : int) : int =
  to_int (logand (shift_right_logical packed (4 * i)) 0xFL)

(* OEIS A010060 - Thue-Morse: t_n = popcount(n) mod 2. *)
let thue_morse (n : int) : bool =
  let rec bits x acc =
    if x = 0 then acc
    else bits (x land (x - 1)) (acc lxor 1)  (* clear the lowest set bit *)
  in
  bits n 0 = 1

(* ------------------------------------------------------------------ *)
(* Sealing (packaging side)                                            *)
(* ------------------------------------------------------------------ *)

type nano_block_ticket = {
  block_id        : int;
  encrypted_bytes : bytes;
  stream_nonce    : int64;
  wipe_gamma      : int64;
}

let xor_bytes_with_stream (src : bytes) ~(key : int64) ~(nonce : int64) : bytes =
  let len = Bytes.length src in
  let dst = Bytes.create len in
  for i = 0 to len - 1 do
    let ks = keystream_word key nonce (i / 8) in
    let byte_mask = to_int (logand (shift_right_logical ks ((i mod 8) * 8)) 0xFFL) in
    let b = Char.code (Bytes.get src i) lxor byte_mask in
    Bytes.set dst i (Char.chr b)
  done;
  dst

let wipe_gamma_bytes (key : int64) (nonce : int64) (len : int) : bytes =
  let dst = Bytes.create len in
  for i = 0 to len - 1 do
    let g = wipe_gamma_word key nonce (i / 8) in
    let byte = to_int (logand (shift_right_logical g ((i mod 8) * 8)) 0xFFL) in
    Bytes.set dst i (Char.chr byte)
  done;
  dst

let seal_nano_block ~(block_id : int) ~(raw_code : bytes) ~(master_key : int64) ~(nonce : int64)
    : nano_block_ticket =
  let len = Bytes.length raw_code in
  if len > nano_slot_bytes then
    invalid_arg "Nano_jit_slot.seal_nano_block: block exceeds 128-byte single-slot limit";
  let encrypted_bytes = xor_bytes_with_stream raw_code ~key:master_key ~nonce in
  let wipe_gamma = wipe_gamma_word master_key nonce 0 in
  { block_id; encrypted_bytes; stream_nonce = nonce; wipe_gamma }

let simulate_nano_slot_lifecycle (ticket : nano_block_ticket) ~(master_key : int64)
    : bytes * bytes =
  (* 1. Materialization into the 128-byte slot *)
  let active_slot =
    xor_bytes_with_stream ticket.encrypted_bytes ~key:master_key ~nonce:ticket.stream_nonce
  in
  let materialized_snapshot = Bytes.copy active_slot in
  (* 2. Block epilogue: Rule 30 (OEIS A269160) gamma overwrite of the slot *)
  let wiped_slot =
    wipe_gamma_bytes ticket.wipe_gamma (neg ticket.stream_nonce) (Bytes.length active_slot)
  in
  Bytes.blit wiped_slot 0 active_slot 0 (Bytes.length active_slot);
  (materialized_snapshot, active_slot)

(* ------------------------------------------------------------------ *)
(* Typed C++20 EDSL controllers                                        *)
(* ------------------------------------------------------------------ *)

open Cpp_codegen.Cpp_ast
open Cpp_codegen.Cpp_dsl

(* ---- legacy single-slot controller (standalone header) ------------ *)

let build_nano_jit_slot_ast () : top_decl list =
  let splitmix_fn = FuncDecl {
      attrs    = [AlwaysInline; NoExcept];
      ret_type = UInt64;
      name     = "splitmix_stream";
      params   = [(UInt64, "key"); (UInt64, "nonce"); (SizeT, "idx")];
      body     = [
        let_u64 "z" (var "key" +~ (var "nonce" ^~ (var "idx" *~ u64 Magic_numbers.golden_ratio_64)));
        var "z" := (var "z" ^~ (var "z" >>~ u64 30L)) *~ u64 Magic_numbers.splitmix64_gamma;
        var "z" := (var "z" ^~ (var "z" >>~ u64 27L)) *~ u64 Magic_numbers.splitmix64_mix;
        ret (var "z" ^~ (var "z" >>~ u64 31L));
      ];
    } in
  let rule30_fn = FuncDecl {
      attrs    = [AlwaysInline; NoExcept];
      ret_type = UInt64;
      name     = "rule30_step";
      params   = [(UInt64, "x")];
      body     = [
        let_u64 "l" ((var "x" <<~ u64 1L) |~ (var "x" >>~ u64 63L));
        let_u64 "r" ((var "x" >>~ u64 1L) |~ (var "x" <<~ u64 63L));
        ret ((var "l") ^~ ((var "x") |~ (var "r")));
      ];
    } in
  let materialize_fn = FuncDecl {
      attrs    = [AlwaysInline; NoExcept];
      ret_type = Void;
      name     = "materialize_nano_block";
      params   = [
        (Ref (StructType "EphemeralSlot"), "slot");
        (ConstPtr UInt64, "encrypted_words");
        (SizeT, "word_count");
        (UInt64, "master_key");
        (UInt64, "nonce");
      ];
      body     = [
        decl_var ~is_volatile:true (Ptr UInt64) "dst" ~init:(var "slot" $. "code_words");
        ForRange {
          var_name = "i";
          start_e  = u64 0L;
          limit_e  = ternary (var "word_count" <~ u64 16L) (var "word_count") (u64 16L);
          body     = [
            (idx (var "dst") (var "i")) :=
              ((idx (var "encrypted_words") (var "i")) ^~
               (call "splitmix_stream" [var "master_key"; var "nonce"; var "i"]));
          ];
        };
        FenceSeqCst;
      ];
    } in
  let wipe_fn = FuncDecl {
      attrs    = [AlwaysInline; NoExcept];
      ret_type = Void;
      name     = "wipe_nano_block";
      params   = [
        (Ref (StructType "EphemeralSlot"), "slot");
        (UInt64, "wipe_key");
        (UInt64, "nonce");
      ];
      body     = [
        decl_var ~is_volatile:true (Ptr UInt64) "dst" ~init:(var "slot" $. "code_words");
        let_u64 "st" (var "wipe_key" ^~ var "nonce" ^~ u64 Magic_numbers.rule30_salt);
        ForRange {
          var_name = "i";
          start_e  = u64 0L;
          limit_e  = u64 16L;
          body     = [
            var "st" := call "rule30_step" [var "st"];
            (idx (var "dst") (var "i")) := var "st";
          ];
        };
        FenceSeqCst;
      ];
    } in
  [
    IncludeSys "cstdint";
    IncludeSys "cstddef";
    IncludeSys "atomic";
    Namespace ("asgard::nano_jit", [
      ConstexprGlobal (SizeT, "NANO_SLOT_SIZE", u64 (of_int nano_slot_bytes));
      StructDecl {
        align_as = Some 64;
        name     = "EphemeralSlot";
        fields   = [(Array (UInt64, nano_slot_words), "code_words")];
      };
      rule30_fn;
      splitmix_fn;
      materialize_fn;
      wipe_fn;
    ]);
  ]

let emit_self_wiping_nano_jit_hpp () : string =
  Cpp_codegen.Cpp_printer.render_header_unit (build_nano_jit_slot_ast ())

(* ---- sealed arena controller (assembled into the JIT runtime) ----- *)

(* OEIS A269160 - Rule 30 step. *)
let arena_rule30_fn = func_decl ~attrs:[AlwaysInline; NoExcept] UInt64 "rule30_step"
    [(UInt64, "x")]
    [
      let_u64 "l" ((var "x" <<~ u64 1L) |~ (var "x" >>~ u64 63L));
      let_u64 "r" ((var "x" >>~ u64 1L) |~ (var "x" <<~ u64 63L));
      ret ((var "l") ^~ ((var "x") |~ (var "r")));
    ]

let arena_splitmix_fn = func_decl ~attrs:[AlwaysInline; NoExcept] UInt64 "splitmix_stream"
    [(UInt64, "key"); (UInt64, "nonce"); (SizeT, "idx")]
    [
      let_u64 "z" (var "key" +~ (var "nonce" ^~ (var "idx" *~ u64 Magic_numbers.golden_ratio_64)));
      var "z" := (var "z" ^~ (var "z" >>~ u64 30L)) *~ u64 Magic_numbers.splitmix64_gamma;
      var "z" := (var "z" ^~ (var "z" >>~ u64 27L)) *~ u64 Magic_numbers.splitmix64_mix;
      ret (var "z" ^~ (var "z" >>~ u64 31L));
    ]

(* OEIS A000695 - spread the compacted bit planes back onto the even
   positions and rebuild N = X + 2Y (carry-free, so ADD and XOR agree). *)
let arena_moser_unblind_fn = func_decl ~attrs:[AlwaysInline; NoExcept] UInt64 "moser_unblind"
    [(UInt64, "w")]
    [
      let_u64 "e" (var "w" &~ u64 0xFFFFFFFFL);
      let_u64 "o" ((var "w" >>~ u64 32L) &~ u64 0xFFFFFFFFL);
      let_u64 "x" (var "e");
      var "x" := (var "x" |~ (var "x" <<~ u64 16L)) &~ u64 0x0000FFFF0000FFFFL;
      var "x" := (var "x" |~ (var "x" <<~ u64 8L)) &~ u64 0x00FF00FF00FF00FFL;
      var "x" := (var "x" |~ (var "x" <<~ u64 4L)) &~ u64 0x0F0F0F0F0F0F0F0FL;
      var "x" := (var "x" |~ (var "x" <<~ u64 2L)) &~ u64 0x3333333333333333L;
      var "x" := (var "x" |~ (var "x" <<~ u64 1L)) &~ u64 Magic_numbers.even_bit_mask;
      let_u64 "y" (var "o");
      var "y" := (var "y" |~ (var "y" <<~ u64 16L)) &~ u64 0x0000FFFF0000FFFFL;
      var "y" := (var "y" |~ (var "y" <<~ u64 8L)) &~ u64 0x00FF00FF00FF00FFL;
      var "y" := (var "y" |~ (var "y" <<~ u64 4L)) &~ u64 0x0F0F0F0F0F0F0F0FL;
      var "y" := (var "y" |~ (var "y" <<~ u64 2L)) &~ u64 0x3333333333333333L;
      var "y" := (var "y" |~ (var "y" <<~ u64 1L)) &~ u64 Magic_numbers.even_bit_mask;
      ret ((var "x") |~ (var "y" <<~ u64 1L));
    ]

(* OEIS A000201 - branchless Beatty membership: unit u is an executable
   (lower Wythoff) unit iff floor((u+1)/phi) > floor(u/phi). *)
let arena_beatty_fn = func_decl ~attrs:[AlwaysInline; NoExcept] Bool "beatty_unit_is_real"
    [(UInt32, "u")]
    [
      let_u64 "g" (u64 Magic_numbers.golden_ratio_64);
      let_u64 "up1" (c_cast UInt64 (var "u") +~ u64 1L);
      decl_var (StructType "__uint128_t") "m1"
        ~init:(c_cast (StructType "__uint128_t") (var "up1")
               *~ c_cast (StructType "__uint128_t") (var "g"));
      decl_var (StructType "__uint128_t") "m0"
        ~init:(c_cast (StructType "__uint128_t") (c_cast UInt64 (var "u"))
               *~ c_cast (StructType "__uint128_t") (var "g"));
      ret ((c_cast UInt64 (var "m1" >>~ u64 64L)) >~ (c_cast UInt64 (var "m0" >>~ u64 64L)));
    ]

let arena_is_active_fn = func_decl ~attrs:[AlwaysInline; NoExcept] Bool "is_active_unit"
    [(UInt32, "u")]
    [
      for_range "j" (i32 0) (var "NANO_ACTIVE_SLOTS") [
        if_then (c_cast UInt32 (idx (var "g_golomb5") (var "j")) ==~ var "u") [
          ret (bool_lit true);
        ];
      ];
      ret (bool_lit false);
    ]

let arena_slot_base_fn = func_decl ~attrs:[AlwaysInline; NoExcept] (Ptr UInt64)
    "arena_slot_base"
    [(Ref (StructType "NanoArena"), "arena"); (UInt32, "slot")]
    [
      ret (addr_of
             (idx (var "arena.words")
                ((c_cast UInt64 (idx (var "g_golomb5") (var "slot")))
                 *~ u64 (of_int nano_slot_words))));
    ]

(* OEIS A269160/A002487 - slot wipe with a fresh Rule 30 gamma keyed by the
   slot index (through its Stern factor) and the global step counter. *)
let arena_wipe_slot_fn = func_decl ~attrs:[AlwaysInline; NoExcept] Void "wipe_slot"
    [(Ref (StructType "NanoArena"), "arena"); (UInt32, "slot"); (UInt32, "step")]
    [
      decl_var ~is_volatile:true (Ptr UInt64) "p" ~init:(call "arena_slot_base" [var "arena"; var "slot"]);
      let_u64 "st"
        (u64 Magic_numbers.rule30_init_key
         ^~ idx (var "g_stern_alpha") (var "slot")
         ^~ c_cast UInt64 (var "step")
         ^~ u64 Magic_numbers.rule30_salt);
      for_range "w" (i32 0) (i32 nano_slot_words) [
        var "st" := call "rule30_step" [var "st"];
        (idx (var "p") (var "w")) := var "st";
      ];
      FenceSeqCst;
    ]

(* OEIS A000201/A001950 - arena initialization: every unit that is not an
   active Golomb slot is classified by the branchless Beatty predicate.
   Lower-Wythoff (a-class) units receive Rule 30 padding; upper-Wythoff
   (b-class) units receive the executable trap fill. *)
let arena_init_fn = func_decl ~attrs:[AlwaysInline; NoExcept] Void "arena_init"
    [(Ref (StructType "NanoArena"), "arena")]
    [
      var "arena.step" := u32 0l;
      for_range "u" (i32 0) (i32 nano_arena_units) [
        if_then (log_not (call "is_active_unit" [var "u"])) [
          let_u64 "fill"
            (ternary
               (log_not (call "beatty_unit_is_real" [var "u"]))
               (var "NANO_TRAP_WORD")
               (call "rule30_step"
                  [u64 Magic_numbers.rule30_init_key
                   ^~ c_cast UInt64 (var "u")
                   ^~ u64 Magic_numbers.rule30_salt]));
          for_range "w" (i32 0) (i32 nano_slot_words) [
            (idx (var "arena.words")
               ((c_cast UInt64 (var "u") *~ u64 (of_int nano_slot_words))
                +~ c_cast UInt64 (var "w")))
              := var "fill";
          ];
        ];
      ];
      FenceSeqCst;
    ]

(* Materialization: SplitMix64 transport decryption into the Golomb-placed
   slot (OEIS A003022 offsets), gated by the branchless Beatty legitimacy
   check, then deserialization into the staging window with Moser-de Bruijn
   (OEIS A000695) immediate unblinding. *)
let arena_materialize_fn = func_decl ~attrs:[AlwaysInline; NoExcept] Void
    "materialize_chunk"
    [ (Ref (StructType "NanoArena"), "arena");
      (UInt32, "k");
      (ConstRef (StructType "NanoTicket"), "ticket");
      (ConstPtr UInt64, "encrypted_words");
      (UInt64, "master") ]
    [
      let_u32 "slot" (var "k" %~ u32 (Int32.of_int nano_active_slots));
      let_u32 "unit" (idx (var "g_golomb5") (var "slot"));
      (* Defensive gate: only real (a-class) units or the arena base may
         host code; b-class honeypots abort the run. *)
      if_then ((log_not (call "beatty_unit_is_real" [var "unit"]))
               &&~ (var "unit" <>~ u32 0l)) [
        expr_stmt (call "abort" []);
      ];
      decl_var ~is_volatile:true (Ptr UInt64) "dst"
        ~init:(call "arena_slot_base" [var "arena"; var "slot"]);
      for_range "w" (i32 0) (var "ticket.word_count") [
        (idx (var "dst") (var "w")) :=
          ((idx (var "encrypted_words") (var "w"))
           ^~ (call "splitmix_stream" [var "master"; var "ticket.nonce"; var "w"]));
      ];
      for_range "i" (i32 0) (var "ticket.instr_count") [
        let_u64 "w0" (idx (var "dst") (var "i" *~ u32 2l));
        let_u64 "w1" (idx (var "dst") ((var "i" *~ u32 2l) +~ u32 1l));
        ((idx (var "arena.staging") (var "i")) $. "op")
          := c_cast UInt8 (var "w0" &~ u64 0xFFL);
        ((idx (var "arena.staging") (var "i")) $. "dst")
          := c_cast UInt8 ((var "w0" >>~ u64 8L) &~ u64 0xFFL);
        ((idx (var "arena.staging") (var "i")) $. "src")
          := c_cast UInt8 ((var "w0" >>~ u64 16L) &~ u64 0xFFL);
        ((idx (var "arena.staging") (var "i")) $. "imm")
          := call "moser_unblind" [var "w1"];
      ];
      FenceSeqCst;
    ]

(* OEIS A001511 - fractal tiered invalidation.  After execution step t the
   active slot is always wiped, and every slot of fractal level
   1 + ctz(t) = A001511(t) or below is re-wiped with fresh Rule 30 gamma. *)
let arena_after_chunk_fn = func_decl ~attrs:[AlwaysInline; NoExcept] Void
    "arena_after_chunk"
    [(Ref (StructType "NanoArena"), "arena"); (UInt32, "k")]
    [
      var "arena.step" := (var "arena.step" +~ u32 1l);
      let_u32 "t" (var "arena.step");
      let_u32 "active" (var "k" %~ u32 (Int32.of_int nano_active_slots));
      expr_stmt (call "wipe_slot" [var "arena"; var "active"; var "t"]);
      let_u32 "thresh" (c_cast UInt32 (call "__builtin_ctz" [var "t"]) +~ u32 1l);
      for_range "s" (i32 0) (i32 nano_active_slots) [
        if_then (((var "s" <>~ var "active")
                  &&~ (((var "s" %~ u32 4l) +~ u32 1l) <=~ var "thresh"))) [
          expr_stmt (call "wipe_slot" [var "arena"; var "s"; var "t"]);
        ];
      ];
      for_range "i" (i32 0) (i32 nano_max_chunk_instrs) [
        ((idx (var "arena.staging") (var "i")) $. "op") := u8 0;
        ((idx (var "arena.staging") (var "i")) $. "dst") := u8 0;
        ((idx (var "arena.staging") (var "i")) $. "src") := u8 0;
        ((idx (var "arena.staging") (var "i")) $. "imm") := u64 0L;
      ];
      FenceSeqCst;
    ]

(* OEIS A000166 + A002487 - inter-chunk register shuffle.  Virtual register
   i lives in gprs slot pi(i) of the current chunk's convention; between
   chunks the file is re-permuted (fix-free permutation: no slot keeps its
   meaning in two adjacent chunks) while the values cross the transfer
   window affine-encrypted with the odd Stern factor alpha.  alpha^-1 is
   computed by five Newton-Raphson iterations (no division table). *)
let arena_remap_gprs_fn = func_decl ~attrs:[AlwaysInline; NoExcept] Void "remap_gprs"
    [ (Ref (StructType "asgard_rd_jit::RD_JIT_Context"), "ctx");
      (UInt64, "from_packed");
      (UInt64, "to_packed");
      (UInt64, "alpha") ]
    [
      decl_var ~is_volatile:true (Array (UInt64, 16)) "tmp";
      let_u64 "inv" (var "alpha");
      var "inv" := (var "inv" *~ (u64 2L -~ (var "alpha" *~ var "inv")));
      var "inv" := (var "inv" *~ (u64 2L -~ (var "alpha" *~ var "inv")));
      var "inv" := (var "inv" *~ (u64 2L -~ (var "alpha" *~ var "inv")));
      var "inv" := (var "inv" *~ (u64 2L -~ (var "alpha" *~ var "inv")));
      var "inv" := (var "inv" *~ (u64 2L -~ (var "alpha" *~ var "inv")));
      for_range "i" (i32 0) (i32 16) [
        let_u32 "from_slot"
          (c_cast UInt32 ((var "from_packed" >>~ (var "i" *~ u64 4L)) &~ u64 0xFL));
        let_u32 "to_slot"
          (c_cast UInt32 ((var "to_packed" >>~ (var "i" *~ u64 4L)) &~ u64 0xFL));
        (idx (var "tmp") (var "to_slot"))
          := ((idx ((var "ctx") $. "gprs") (var "from_slot")) *~ var "alpha");
      ];
      for_range "i" (i32 0) (i32 16) [
        (idx ((var "ctx") $. "gprs") (var "i")) := ((idx (var "tmp") (var "i")) *~ var "inv");
      ];
      for_range "i" (i32 0) (i32 16) [
        expr_stmt (call "ctx.vregs[i].set" [idx ((var "ctx") $. "gprs") (var "i")]);
      ];
    ]

let arena_execute_chunk_fn = func_decl ~attrs:[AlwaysInline; NoExcept] Void
    "execute_sealed_chunk"
    [ (Ref (StructType "asgard_rd_jit::DualMappedJITBuffer"), "jit");
      (Ref (StructType "asgard_rd_jit::RD_JIT_Context"), "ctx");
      (Ref (StructType "NanoArena"), "arena");
      (UInt32, "k");
      (ConstRef (StructType "NanoTicket"), "ticket");
      (ConstPtr UInt64, "encrypted_words");
      (UInt64, "master") ]
    [
      expr_stmt (call "materialize_chunk"
                   [var "arena"; var "k"; var "ticket"; var "encrypted_words"; var "master"]);
      decl_var (StructType "asgard_rd_jit::JITBlock") "view" ~init:(init_list [
        var "k";
        var "ticket.instr_count";
        var "arena.staging";
      ]);
      expr_stmt (call "asgard_rd_jit::synthesize_and_execute_block"
                   [var "jit"; var "ctx"; var "view"]);
      expr_stmt (call "arena_after_chunk" [var "arena"; var "k"]);
    ]

(* Sealed execution driver: arena setup, identity->pi(0) shuffle, the
   materialize / execute / fractal-wipe cascade per chunk, and the final
   shuffle back to the canonical convention. *)
let arena_execute_function_fn = func_decl ~attrs:[InlineFn] Void "execute_sealed_function"
    [ (Ref (StructType "asgard_rd_jit::DualMappedJITBuffer"), "jit");
      (Ref (StructType "asgard_rd_jit::RD_JIT_Context"), "ctx");
      (ConstPtr (StructType "NanoTicket"), "tickets");
      (ConstPtr (Ptr UInt64), "blobs");
      (SizeT, "num_chunks");
      (UInt64, "master") ]
    [
      decl_var (Ref (StructType "NanoArena")) "arena"
        ~init:(deref (c_cast (Ptr (StructType "NanoArena")) (call "jit.arena_region" [])));
      decl_var (Ptr UInt64) "meta" ~init:(c_cast (Ptr UInt64) (call "jit.metadata_region" []));
      expr_stmt (call "memcpy"
                   [ var "meta"; var "g_perm_packed"; sizeof_expr (var "g_perm_packed") ]);
      expr_stmt (call "memcpy"
                   [ addr_of (idx (var "meta") (i32 5)); var "g_stern_alpha";
                     sizeof_expr (var "g_stern_alpha") ]);
      expr_stmt (call "arena_init" [var "arena"]);
      if_then (var "num_chunks" >~ i32 0) [
        expr_stmt (call "remap_gprs"
                     [ var "ctx";
                       idx (var "meta") (i32 perm_identity_index);
                       idx (var "meta") ((idx (var "tickets") (i32 0)) $. "perm_idx");
                       idx (var "meta") (u64 5L) ]);
        for_range "k" (i32 0) (var "num_chunks") [
          if_then (var "k" >~ i32 0) [
            expr_stmt (call "remap_gprs"
                         [ var "ctx";
                           idx (var "meta")
                             ((idx (var "tickets") (var "k" -~ i32 1)) $. "perm_idx");
                           idx (var "meta")
                             ((idx (var "tickets") (var "k")) $. "perm_idx");
                           idx (var "meta") ((var "k" &~ u64 63L) +~ u64 5L) ]);
          ];
          expr_stmt (call "execute_sealed_chunk"
                       [ var "jit"; var "ctx"; var "arena"; var "k";
                         idx (var "tickets") (var "k");
                         idx (var "blobs") (var "k");
                         var "master" ]);
        ];
        expr_stmt (call "remap_gprs"
                     [ var "ctx";
                       idx (var "meta")
                         ((idx (var "tickets") (var "num_chunks" -~ i32 1)) $. "perm_idx");
                       idx (var "meta") (i32 perm_identity_index);
                       idx (var "meta") ((var "num_chunks" &~ u64 63L) +~ u64 5L) ]);
      ];
    ]

(* Tables and types of the arena controller. *)
let arena_types_and_tables () : top_decl list =
  let golomb_entries = Array.to_list
      (Array.map (fun m -> u32 (Int32.of_int (to_int m))) golomb5_marks) in
  let stern_entries = Array.to_list (Array.map u64 stern_alphas) in
  let perm_entries = Array.to_list (Array.map u64 perm_tables) in
  [
    ConstexprGlobal (SizeT, "NANO_SLOT_WORDS", u64 (of_int nano_slot_words));
    ConstexprGlobal (SizeT, "NANO_ACTIVE_SLOTS", u64 (of_int nano_active_slots));
    ConstexprGlobal (SizeT, "NANO_ARENA_UNITS", u64 (of_int nano_arena_units));
    ConstexprGlobal (SizeT, "NANO_MAX_CHUNK_INSTRS", u64 (of_int nano_max_chunk_instrs));
    comment_top "/* OEIS A003022: optimal 5-mark Golomb ruler {0, 1, 4, 9, 11} - active slot units */";
    global_var ~is_static:true ~is_const:true (Array (UInt32, 0)) "g_golomb5"
      ~init:(init_list golomb_entries);
    comment_top "/* OEIS A002487: Stern alpha_n = 2a(n)+1, odd units of Z_2^64 */";
    global_var ~is_static:true ~is_const:true (Array (UInt64, 0)) "g_stern_alpha"
      ~init:(init_list stern_entries);
    comment_top "/* OEIS A000166: fix-free gprs permutations (nibble i = pi(i)), then identity */";
    global_var ~is_static:true ~is_const:true (Array (UInt64, 0)) "g_perm_packed"
      ~init:(init_list perm_entries);
    preproc_if "defined(__aarch64__)"
      [ ConstexprGlobal (UInt64, "NANO_TRAP_WORD", u64 Magic_numbers.honeypot_trap_word_arm64) ]
      ~else_decls:[
        ConstexprGlobal (UInt64, "NANO_TRAP_WORD", u64 Magic_numbers.honeypot_trap_word_x86) ];
    StructDecl {
        align_as = None;
        name = "NanoTicket";
        fields = [
          (UInt64, "nonce");
          (UInt32, "word_count");
          (UInt32, "instr_count");
          (UInt32, "perm_idx");
        ];
      };
    StructDecl {
        align_as = None;
        name = "NanoArena";
        fields = [
          (Array (UInt64, nano_arena_units * nano_slot_words), "words");
          (UInt32, "step");
          (Array (StructType "asgard_rd_jit::JITInstr", nano_max_chunk_instrs), "staging");
        ];
      };
  ]

let build_nano_arena_ast () : top_decl list =
  [
    IncludeSys "cstdint";
    IncludeSys "cstddef";
    IncludeSys "cstdlib";
    IncludeSys "atomic";
    Namespace ("asgard::nano_jit",
      (arena_types_and_tables ()
       @ [ arena_rule30_fn;
           arena_splitmix_fn;
           arena_moser_unblind_fn;
           arena_beatty_fn;
           arena_is_active_fn;
           arena_slot_base_fn;
           arena_wipe_slot_fn;
           arena_init_fn;
           arena_materialize_fn;
           arena_after_chunk_fn;
           arena_remap_gprs_fn;
           arena_execute_chunk_fn;
           arena_execute_function_fn ]));
  ]
