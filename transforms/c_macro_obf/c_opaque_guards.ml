(** C_opaque_guards — Automatic C/C++ if-condition opaque predicate injection.
    Scans `if (cond)` in C source and rewrites to:
    `if (ASG_OPAQUE_P<k>(<salt>) && (cond))`
    using a polymorphic rotation of the 8 invariant families. *)


let skip_ws s i =
  let len = String.length s in
  let j = ref i in
  while !j < len && (s.[!j] = ' ' || s.[!j] = '\t' || s.[!j] = '\n' || s.[!j] = '\r') do
    incr j
  done;
  !j

let scan_balanced_parens s i =
  let len = String.length s in
  let depth = ref 0 in
  let j = ref i in
  let in_str = ref false in
  let in_char = ref false in
  let escape = ref false in
  while !j < len && (not (!depth = 0 && !j > i)) do
    let c = s.[!j] in
    (if !escape then escape := false
     else match c with
       | '\\' when !in_str || !in_char -> escape := true
       | '"' when not !in_char -> in_str := not !in_str
       | '\'' when not !in_str -> in_char := not !in_char
       | '(' when not !in_str && not !in_char -> incr depth
       | ')' when not !in_str && not !in_char -> decr depth
       | _ -> ());
    incr j
  done;
  if !depth = 0 then !j else -1

let random_opaque_guard prefix rng_state =
  let variant = Random.State.int rng_state 8 in
  let s1 = Random.State.int64 rng_state 0xFFFF_FFFFL in
  let s2 = Random.State.int64 rng_state 0xFFFF_FFFFL in
  match variant with
  | 0 -> Printf.sprintf "%sOPAQUE_P1(0x%LXULL)" prefix s1
  | 1 -> Printf.sprintf "%sOPAQUE_P2(0x%LXULL)" prefix s1
  | 2 -> Printf.sprintf "%sOPAQUE_P3(0x%LXULL)" prefix s1
  | 3 -> Printf.sprintf "%sOPAQUE_P4(0x%LXULL, 0x%LXULL)" prefix s1 s2
  | 4 -> Printf.sprintf "%sOPAQUE_P5(0x%LXULL)" prefix s1
  | 5 -> Printf.sprintf "%sOPAQUE_P6(0x%LXULL, 0x%LXULL)" prefix s1 s2
  | 6 -> Printf.sprintf "%sOPAQUE_P7(0x%LXULL, 0x%LXULL)" prefix s1 s2
  | _ -> Printf.sprintf "%sOPAQUE_P8(0x%LXULL)" prefix s1

let inject_opaque_predicates_in_source ?(prefix = "ASG_") ~(seed : int) src =
  let rng = Random.State.make [| seed |] in
  let len = String.length src in
  let buf = Buffer.create (len + 512) in
  let i = ref 0 in
  let in_str = ref false in
  let in_char = ref false in
  let in_line_comm = ref false in
  let in_blk_comm = ref false in
  let in_preproc = ref false in
  let last_char = ref ' ' in

  while !i < len do
    let c = src.[!i] in
    if !in_line_comm then begin
      Buffer.add_char buf c;
      if c = '\n' then (in_line_comm := false; in_preproc := false);
      incr i
    end
    else if !in_blk_comm then begin
      Buffer.add_char buf c;
      if c = '*' && !i + 1 < len && src.[!i + 1] = '/' then begin
        Buffer.add_char buf '/';
        in_blk_comm := false;
        i := !i + 2
      end else
        incr i
    end
    else if !in_str then begin
      Buffer.add_char buf c;
      if c = '\\' && !i + 1 < len then begin
        Buffer.add_char buf src.[!i + 1];
        i := !i + 2
      end
      else if c = '"' then begin
        in_str := false;
        incr i
      end else
        incr i
    end
    else if !in_char then begin
      Buffer.add_char buf c;
      if c = '\\' && !i + 1 < len then begin
        Buffer.add_char buf src.[!i + 1];
        i := !i + 2
      end
      else if c = '\'' then begin
        in_char := false;
        incr i
      end else
        incr i
    end
    else if c = '/' && !i + 1 < len && src.[!i + 1] = '/' then begin
      Buffer.add_string buf "//";
      in_line_comm := true;
      i := !i + 2
    end
    else if c = '/' && !i + 1 < len && src.[!i + 1] = '*' then begin
      Buffer.add_string buf "/*";
      in_blk_comm := true;
      i := !i + 2
    end
    else if c = '#' && (!last_char = '\n' || !last_char = ' ' || !i = 0) then begin
      Buffer.add_char buf c;
      in_preproc := true;
      incr i
    end
    else if c = '"' then begin
      Buffer.add_char buf c;
      in_str := true;
      incr i
    end
    else if c = '\'' then begin
      Buffer.add_char buf c;
      in_char := true;
      incr i
    end
    else if not !in_preproc && c = 'i' && !i + 1 < len && src.[!i + 1] = 'f' &&
            (!i = 0 || not (let p = src.[!i - 1] in (p >= 'a' && p <= 'z') || (p >= 'A' && p <= 'Z') || (p >= '0' && p <= '9') || p = '_')) &&
            (!i + 2 >= len || not (let a = src.[!i + 2] in (a >= 'a' && a <= 'z') || (a >= 'A' && a <= 'Z') || (a >= '0' && a <= '9') || a = '_')) then begin
      let after = skip_ws src (!i + 2) in
      if after < len && src.[after] = '(' then begin
        let cond_end = scan_balanced_parens src after in
        if cond_end > 0 then begin
          let cond_inner = String.sub src (after + 1) (cond_end - after - 2) in
          let guard = random_opaque_guard prefix rng in
          Buffer.add_string buf "if (";
          Buffer.add_string buf guard;
          Buffer.add_string buf " && (";
          Buffer.add_string buf cond_inner;
          Buffer.add_string buf "))";
          i := cond_end;
          last_char := ')'
        end else begin
          Buffer.add_string buf "if";
          i := !i + 2;
          last_char := 'f'
        end
      end else begin
        Buffer.add_string buf "if";
        i := !i + 2;
        last_char := 'f'
      end
    end
    else begin
      Buffer.add_char buf c;
      if c <> ' ' && c <> '\t' && c <> '\r' then last_char := c;
      if c = '\n' then in_preproc := false;
      incr i
    end
  done;
  Buffer.contents buf
