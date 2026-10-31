open Random_visa_constants.Magic_numbers

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

let k = sha256_k

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

  let h0 = ref sha256_iv.(0) in
  let h1 = ref sha256_iv.(1) in
  let h2 = ref sha256_iv.(2) in
  let h3 = ref sha256_iv.(3) in
  let h4 = ref sha256_iv.(4) in
  let h5 = ref sha256_iv.(5) in
  let h6 = ref sha256_iv.(6) in
  let h7 = ref sha256_iv.(7) in

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
