(** RFC 2104 HMAC-SHA256 Message Authentication Code. *)

val digest : key:bytes -> data:bytes -> bytes
(** Computes 32-byte HMAC-SHA256 authentication tag for [data] with [key]. *)

val verify : key:bytes -> data:bytes -> expected_mac:bytes -> bool
(** Authenticates [data] against [expected_mac] in constant time.
    Returns true if and only if the tag is valid. *)
