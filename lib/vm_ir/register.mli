(** Register definitions for x86_64 CPU and VM execution contexts. *)

type width =
  | B8
  | B16
  | B32
  | B64

val width_to_bytes : width -> int
val width_to_bits : width -> int

type gpr =
  | RAX
  | RCX
  | RDX
  | RBX
  | RSP
  | RBP
  | RSI
  | RDI
  | R8
  | R9
  | R10
  | R11
  | R12
  | R13
  | R14
  | R15

type vreg =
  | VIP       (** Virtual Instruction Pointer *)
  | VSP       (** Virtual Stack Pointer *)
  | VKEY      (** Current Rolling Key / Context State *)
  | VTMP0     (** Scratch register 0 *)
  | VTMP1     (** Scratch register 1 *)
  | VTMP2     (** Scratch register 2 *)
  | VTMP3     (** Scratch register 3 *)
  | VZERO     (** Architectural Zero Register (wzr / xzr) *)
  | VX18
  | VX19
  | VX20
  | VX21
  | VX22
  | VX23
  | VX24
  | VX25
  | VX26

type t =
  | Gpr of gpr * width
  | Vreg of vreg * width
  | Fpr of int * width

val rax : t
val rbx : t
val rcx : t
val rdx : t
val rsp : t
val rbp : t
val rsi : t
val rdi : t
val r8 : t
val r9 : t
val r10 : t
val r11 : t
val r12 : t
val r13 : t
val r14 : t
val r15 : t

val vip : t
val vsp : t
val vkey : t
val vtmp0 : t
val vtmp1 : t
val vtmp2 : t
val vtmp3 : t
val vx18 : t
val vx19 : t
val vx20 : t
val vx21 : t
val vx22 : t
val vx23 : t
val vx24 : t
val vx25 : t
val vx26 : t

val to_string : t -> string
val of_string : string -> (t, string) result
val gpr_index : gpr -> int
val gpr_of_index : int -> (gpr, string) result
val get_width : t -> width
val with_width : t -> width -> t
