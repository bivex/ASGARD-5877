type t = {
  name : string;
  class_weights : (Instruction_class.t * float) list;
}

let make ~name ~class_weights =
  if String.trim name = "" then
    Error (Errors.Invalid_profile "Profile name must be non-empty")
  else
    let rec check seen has_positive = function
      | [] ->
          if not has_positive then
            Error (Errors.Invalid_profile (Printf.sprintf "Profile '%s' must enable at least one class with positive weight" name))
          else
            Ok { name; class_weights }
      | (cls, w) :: rest ->
          if not (Instruction_class.is_supported cls) then
            Error (Errors.Invalid_profile (Printf.sprintf "Profile '%s' references unsupported class %s" name (Instruction_class.to_string cls)))
          else if List.mem cls seen then
            Error (Errors.Duplicate_class (Instruction_class.to_string cls))
          else if w < 0.0 then
            Error (Errors.Invalid_profile (Printf.sprintf "Profile '%s' has negative weight for %s: %f" name (Instruction_class.to_string cls) w))
          else
            check (cls :: seen) (has_positive || w > 0.0) rest
    in
    check [] false class_weights

let enabled_classes t =
  List.filter_map (fun (cls, w) -> if w > 0.0 then Some cls else None) t.class_weights

let weight_for t cls =
  match List.assoc_opt cls t.class_weights with
  | Some w -> w
  | None -> 0.0

let rvv_like =
  match make ~name:"rvv-like" ~class_weights:[
    (Instruction_class.Arith, 55.0);
    (Instruction_class.Saturating, 12.0);
    (Instruction_class.Widening, 18.0);
    (Instruction_class.Compare, 15.0);
  ] with
  | Ok p -> p
  | Error _ -> failwith "Failed to construct rvv-like profile"

let uniform =
  match make ~name:"uniform" ~class_weights:[
    (Instruction_class.Arith, 25.0);
    (Instruction_class.Saturating, 25.0);
    (Instruction_class.Widening, 25.0);
    (Instruction_class.Compare, 25.0);
  ] with
  | Ok p -> p
  | Error _ -> failwith "Failed to construct uniform profile"
