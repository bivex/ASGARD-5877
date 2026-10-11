open Prims
let poly5 (x : Prims.int) : Prims.int=
  (((x * (x - Prims.int_one)) * (x - (Prims.of_int 2))) *
     (x - (Prims.of_int 3)))
    * (x - (Prims.of_int 4))
let poly5_sym (x : Prims.int) : Prims.int=
  ((((x - (Prims.of_int 2)) * (x - Prims.int_one)) * x) * (x + Prims.int_one))
    * (x + (Prims.of_int 2))
let two_61 : Prims.pos= Prims.parse_int "0x2000000000000000"
let two_64 : Prims.pos= Prims.parse_int "0x10000000000000000"
