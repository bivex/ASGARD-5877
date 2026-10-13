let rotr x n =
  let open Int32 in
  logor (shift_right_logical x n) (shift_left x (32 - n))

let sigma0 x =
  let open Int32 in
  logxor (logxor (rotr x 7) (rotr x 18)) (shift_right_logical x 3)

let sigma1 x =
  let open Int32 in
  logxor (logxor (rotr x 17) (rotr x 19)) (shift_right_logical x 10)

let big_sigma0 x =
  let open Int32 in
  logxor (logxor (rotr x 2) (rotr x 13)) (rotr x 22)

let big_sigma1 x =
  let open Int32 in
  logxor (logxor (rotr x 6) (rotr x 11)) (rotr x 25)

let ch x y z =
  let open Int32 in
  logxor (logand x y) (logand (lognot x) z)

let maj x y z =
  let open Int32 in
  logxor (logxor (logand x y) (logand x z)) (logand y z)

let k = [|
  0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l;
  0x3956c25bl; 0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l;
  0xd807aa98l; 0x12835b01l; 0x243185bel; 0x550c7dc3l;
  0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l; 0xc19bf174l;
  0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl;
  0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal;
  0x983e5152l; 0xa831c66dl; 0xb00327c8l; 0xbf597fc7l;
  0xc6e00bf3l; 0xd5a79147l; 0x06ca6351l; 0x14292967l;
  0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl; 0x53380d13l;
  0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
  0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l;
  0xd192e819l; 0xd6990624l; 0xf40e3585l; 0x106aa070l;
  0x19a4c116l; 0x1e376c08l; 0x2748774cl; 0x34b0bcb5l;
  0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl; 0x682e6ff3l;
  0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l;
  0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l;
|]

let digest_bytes (data : bytes) : bytes =
  let len = Bytes.length data in
  let bit_len = Int64.mul (Int64.of_int len) 8L in
  let pad_len =
    let rem = len mod 64 in
    if rem < 56 then 56 - rem
    else 64 + (56 - rem)
  in
  let total_len = len + pad_len + 8 in
  let padded = Bytes.make total_len '\000' in
  Bytes.blit data 0 padded 0 len;
  Bytes.set padded len '\x80';
  for i = 0 to 7 do
    let shift = (7 - i) * 8 in
    let b = Int64.to_int (Int64.logand (Int64.shift_right_logical bit_len shift) 0xFFL) in
    Bytes.set padded (total_len - 8 + i) (Char.chr b)
  done;

  let h0 = ref 0x6a09e667l in
  let h1 = ref 0xbb67ae85l in
  let h2 = ref 0x3c6ef372l in
  let h3 = ref 0xa54ff53al in
  let h4 = ref 0x510e527fl in
  let h5 = ref 0x9b05688cl in
  let h6 = ref 0x1f83d9abl in
  let h7 = ref 0x5be0cd19l in

  let w = Array.make 64 0l in
  let num_chunks = total_len / 64 in

  for chunk = 0 to num_chunks - 1 do
    let chunk_off = chunk * 64 in
    for i = 0 to 15 do
      let b0 = Int32.of_int (Char.code (Bytes.get padded (chunk_off + (i * 4)))) in
      let b1 = Int32.of_int (Char.code (Bytes.get padded (chunk_off + (i * 4) + 1))) in
      let b2 = Int32.of_int (Char.code (Bytes.get padded (chunk_off + (i * 4) + 2))) in
      let b3 = Int32.of_int (Char.code (Bytes.get padded (chunk_off + (i * 4) + 3))) in
      let open Int32 in
      w.(i) <- logor (logor (shift_left b0 24) (shift_left b1 16))
                     (logor (shift_left b2 8) b3)
    done;
    for i = 16 to 63 do
      let open Int32 in
      let s0 = sigma0 w.(i - 15) in
      let s1 = sigma1 w.(i - 2) in
      w.(i) <- add (add (add s1 w.(i - 7)) s0) w.(i - 16)
    done;

    let a = ref !h0 in
    let b = ref !h1 in
    let c = ref !h2 in
    let d = ref !h3 in
    let e = ref !h4 in
    let f = ref !h5 in
    let g = ref !h6 in
    let h_word = ref !h7 in

    for i = 0 to 63 do
      let open Int32 in
      let s1 = big_sigma1 !e in
      let ch_val = ch !e !f !g in
      let temp1 = add (add (add (add !h_word s1) ch_val) k.(i)) w.(i) in
      let s0 = big_sigma0 !a in
      let maj_val = maj !a !b !c in
      let temp2 = add s0 maj_val in
      h_word := !g;
      g := !f;
      f := !e;
      e := add !d temp1;
      d := !c;
      c := !b;
      b := !a;
      a := add temp1 temp2
    done;

    let open Int32 in
    h0 := add !h0 !a;
    h1 := add !h1 !b;
    h2 := add !h2 !c;
    h3 := add !h3 !d;
    h4 := add !h4 !e;
    h5 := add !h5 !f;
    h6 := add !h6 !g;
    h7 := add !h7 !h_word
  done;

  let out = Bytes.make 32 '\000' in
  let words = [| !h0; !h1; !h2; !h3; !h4; !h5; !h6; !h7 |] in
  for i = 0 to 7 do
    let w_val = words.(i) in
    for b = 0 to 3 do
      let shift = (3 - b) * 8 in
      let byte_val = Int32.to_int (Int32.logand (Int32.shift_right_logical w_val shift) 0xFFl) in
      Bytes.set out (i * 4 + b) (Char.chr byte_val)
    done
  done;
  out

let digest_string (s : string) : bytes =
  digest_bytes (Bytes.of_string s)

let hexdigest (digest : bytes) : string =
  let buf = Buffer.create 64 in
  for i = 0 to Bytes.length digest - 1 do
    Printf.bprintf buf "%02x" (Char.code (Bytes.get digest i))
  done;
  Buffer.contents buf

let constant_time_equal (a : bytes) (b : bytes) : bool =
  let len_a = Bytes.length a in
  let len_b = Bytes.length b in
  if len_a <> len_b then false
  else begin
    let diff = ref 0 in
    for i = 0 to len_a - 1 do
      diff := !diff lor (Char.code (Bytes.get a i) lxor Char.code (Bytes.get b i))
    done;
    !diff = 0
  end
