let () =
  let base = Yojson.Safe.from_file "samples/protection_config.multivm.json" in
  let rec top j = match j with
    | `Assoc fields ->
        List.iter (fun (k, v) ->
          let single = `Assoc [ k, v ] in
          match Native_vm.Protection_json.from_yojson single with
          | Ok _ -> ()
          | Error e -> Printf.printf "field '%s' REJECTED (%s)\n" k e)
          fields
    | _ -> ()
  in
  top (Yojson.Safe.to_basic base)
