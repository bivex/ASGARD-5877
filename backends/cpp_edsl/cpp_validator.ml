(** Cpp_validator — Fast pre-flight structural syntax validation and compiler check for generated C++20/C11 code. *)

type validation_error = {
  line : int;
  col  : int;
  msg  : string;
}

let pp_validation_error fmt err =
  Format.fprintf fmt "C++ validation error at line %d, col %d: %s" err.line err.col err.msg

let validation_error_to_string err =
  Printf.sprintf "C++ validation error at line %d, col %d: %s" err.line err.col err.msg

let matching_bracket = function
  | ')' -> '('
  | ']' -> '['
  | '}' -> '{'
  | _ -> '\000'

let validate_structural ?(check_templates = true) (s : string) : (unit, validation_error) result =
  let len = String.length s in
  let line = ref 1 in
  let col = ref 1 in
  let i = ref 0 in
  let stack = ref [] in

  let advance () =
    if !i < len then begin
      if s.[!i] = '\n' then begin
        incr line;
        col := 1;
      end else begin
        incr col;
      end;
      incr i;
    end
  in

  let peek () =
    if !i < len then s.[!i] else '\000'
  in

  let peek_next () =
    if !i + 1 < len then s.[!i + 1] else '\000'
  in

  let err msg =
    Error { line = !line; col = !col; msg }
  in

  let err_at l c msg =
    Error { line = l; col = c; msg }
  in

  let rec loop () =
    if !i >= len then begin
      match !stack with
      | [] -> Ok ()
      | (b, l, c) :: _ ->
          err_at l c (Printf.sprintf "Unclosed delimiter '%c'" b)
    end else begin
      let c = peek () in
      let c_next = peek_next () in

      (* 1. Single-line comment: // ... *)
      if c = '/' && c_next = '/' then begin
        advance ();
        advance ();
        while !i < len && peek () <> '\n' do
          advance ()
        done;
        if !i < len && peek () = '\n' then advance ();
        loop ()
      end
      (* 2. Multi-line comment: /* ... */ *)
      else if c = '/' && c_next = '*' then begin
        let start_l = !line and start_c = !col in
        advance ();
        advance ();
        let closed = ref false in
        while !i < len && not !closed do
          if peek () = '*' && peek_next () = '/' then begin
            advance ();
            advance ();
            closed := true;
          end else begin
            advance ()
          end
        done;
        if not !closed then
          err_at start_l start_c "Unclosed block comment '/*'"
        else
          loop ()
      end
      (* 3. String literal: "..." *)
      else if c = '"' then begin
        let start_l = !line and start_c = !col in
        advance ();
        let closed = ref false in
        while !i < len && not !closed do
          let cur = peek () in
          if cur = '\\' then begin
            advance (); (* skip escape slash *)
            advance (); (* skip escaped char *)
          end else if cur = '"' then begin
            advance ();
            closed := true;
          end else begin
            advance ();
          end
        done;
        if not !closed then
          err_at start_l start_c "Unclosed string literal"
        else
          loop ()
      end
      (* 4. Char literal: '...' *)
      else if c = '\'' then begin
        let start_l = !line and start_c = !col in
        advance ();
        let closed = ref false in
        while !i < len && not !closed do
          let cur = peek () in
          if cur = '\\' then begin
            advance ();
            advance ();
          end else if cur = '\'' then begin
            advance ();
            closed := true;
          end else begin
            advance ();
          end
        done;
        if not !closed then
          err_at start_l start_c "Unclosed character literal"
        else
          loop ()
      end
      (* 5. Check for leftover Jingoo template tags: {{, }}, {%, %} *)
      else if check_templates &&
              ((c = '{' && (c_next = '{' || c_next = '%')) ||
               (c = '}' && c_next = '}') ||
               (c = '%' && c_next = '}')) then begin
        let marker = Printf.sprintf "%c%c" c c_next in
        err (Printf.sprintf "Unexpanded Jingoo template marker '%s' detected" marker)
      end
      (* 6. Opening brackets *)
      else if c = '(' || c = '[' || c = '{' then begin
        stack := (c, !line, !col) :: !stack;
        advance ();
        loop ()
      end
      (* 7. Closing brackets *)
      else if c = ')' || c = ']' || c = '}' then begin
        let expected = matching_bracket c in
        match !stack with
        | [] ->
            err (Printf.sprintf "Unexpected closing delimiter '%c' without matching open delimiter" c)
        | (top, top_l, top_c) :: rest ->
            if top <> expected then
              err (Printf.sprintf "Mismatched delimiter: expected closing '%c' for '%c' (opened at line %d, col %d), but found '%c'"
                     (match top with '(' -> ')' | '[' -> ']' | '{' -> '}' | x -> x)
                     top top_l top_c c)
            else begin
              stack := rest;
              advance ();
              loop ()
            end
      end
      else begin
        advance ();
        loop ()
      end
    end
  in
  loop ()

let validate_with_compiler
    ?(compiler = "clang++")
    ?(std = "c++20")
    ?(extra_includes = [])
    (code : string) : (unit, string) result =
  let temp_file = Filename.temp_file "asgard_syntax_check_" ".cpp" in
  let oc = open_out temp_file in
  output_string oc code;
  close_out oc;
  let inc_args =
    List.map (fun inc -> Printf.sprintf "-I%s" (Filename.quote inc)) extra_includes
    |> String.concat " "
  in
  let cmd =
    Printf.sprintf "%s -fsyntax-only -std=%s %s %s 2>&1"
      compiler
      std
      inc_args
      (Filename.quote temp_file)
  in
  let in_ch = Unix.open_process_in cmd in
  let output_buf = Buffer.create 512 in
  (try
     while true do
       let line = input_line in_ch in
       Buffer.add_string output_buf line;
       Buffer.add_char output_buf '\n';
     done
   with End_of_file -> ());
  let status = Unix.close_process_in in_ch in
  (try Sys.remove temp_file with _ -> ());
  match status with
  | Unix.WEXITED 0 -> Ok ()
  | Unix.WEXITED code ->
      Error (Printf.sprintf "Compiler %s returned code %d:\n%s" compiler code (Buffer.contents output_buf))
  | Unix.WSIGNALED s ->
      Error (Printf.sprintf "Compiler %s killed by signal %d" compiler s)
  | Unix.WSTOPPED s ->
      Error (Printf.sprintf "Compiler %s stopped by signal %d" compiler s)

let validate_cpp_syntax
    ?(check_templates = true)
    ?(use_compiler = false)
    ?compiler
    ?std
    ?extra_includes
    (code : string) : (unit, string) result =
  match validate_structural ~check_templates code with
  | Error err -> Error (validation_error_to_string err)
  | Ok () ->
      if use_compiler then
        validate_with_compiler ?compiler ?std ?extra_includes code
      else
        Ok ()
