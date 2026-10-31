type t = {
  mnemonic_base : string;
  klass : Instruction_class.t;
  weight : float;
  formats : Types.Instruction_format.t list;
  binary_op : Types.Binary_op.t option;
  unary_op : Types.Unary_op.t option;
  element_kind : Types.Element_kind.t;
  is_widening : bool;
}

let has_duplicates lst =
  let rec check seen = function
    | [] -> false
    | x :: xs -> if List.mem x seen then true else check (x :: seen) xs
  in
  check [] lst

let make
    ~mnemonic_base
    ~klass
    ~weight
    ~formats
    ?binary_op
    ?unary_op
    ?(element_kind = Types.Element_kind.Int)
    ?is_widening
    () =
  let widening_flag =
    match is_widening with
    | Some w -> w
    | None -> (klass = Instruction_class.Widening)
  in
  if String.length mnemonic_base = 0 || mnemonic_base.[0] <> 'v' || String.contains mnemonic_base '_' then
    Error (Errors.Invalid_mnemonic (Printf.sprintf "Family mnemonic_base must be a 'v'-prefixed token: %s" mnemonic_base))
  else if (binary_op = None && unary_op = None) || (binary_op <> None && unary_op <> None) then
    Error (Errors.General_error (Printf.sprintf "Family %s must define exactly one of binary or unary operator" mnemonic_base))
  else if formats = [] then
    Error (Errors.Invalid_format (Printf.sprintf "Family %s must declare at least one format" mnemonic_base))
  else if has_duplicates formats then
    Error (Errors.Invalid_format (Printf.sprintf "Family %s has duplicate formats" mnemonic_base))
  else if widening_flag <> (klass = Instruction_class.Widening) then
    Error (Errors.General_error (Printf.sprintf "Family %s: is_widening flag must match WIDENING class membership" mnemonic_base))
  else if weight <= 0.0 then
    Error (Errors.Invalid_weight (mnemonic_base, weight))
  else
    Ok {
      mnemonic_base;
      klass;
      weight;
      formats;
      binary_op;
      unary_op;
      element_kind;
      is_widening = widening_flag;
    }
