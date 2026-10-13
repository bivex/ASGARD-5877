
type ('a, 'b) pass = {
  name : string;
  run : 'a -> 'b;
  pre_check : ('a -> (unit, string) result) option;
  post_check : ('b -> (unit, string) result) option;
}

let make_pass ~name ?pre ?post run_fn =
  {
    name;
    run = run_fn;
    pre_check = pre;
    post_check = post;
  }

let run_pass pass input =
  let pre_res =
    match pass.pre_check with
    | Some check -> check input
    | None -> Ok ()
  in
  match pre_res with
  | Error err ->
      Error (Printf.sprintf "Pass '%s' PRE-condition violation: %s" pass.name err)
  | Ok () ->
      let output = pass.run input in
      let post_res =
        match pass.post_check with
        | Some check -> check output
        | None -> Ok ()
      in
      match post_res with
      | Error err ->
          Error (Printf.sprintf "Pass '%s' POST-condition violation: %s" pass.name err)
      | Ok () -> Ok output

let rec run_pipeline passes input =
  match passes with
  | [] -> Ok input
  | p :: rest ->
      (match run_pass p input with
       | Ok next -> run_pipeline rest next
       | Error err -> Error err)
