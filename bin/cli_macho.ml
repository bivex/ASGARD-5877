open Random_visa_ports

open Cmdliner
open Macho

(* MACHO-UNWIND COMMAND: inspect and repair the compact unwind information
   of a Mach-O image through its LC_ROUTINES / LC_ROUTINES64 load commands. *)

let run_macho_unwind input repair_to =
  match Macho_image.of_file input with
  | exception Macho_image.Parse_error msg ->
      Logger.errorf ~section:"MACHO" "macho-unwind: %s" msg;
      `Error (false, msg)
  | img ->
      let report = Macho_unwind.check img in
      print_string (Macho_unwind.format_report report);
      (match repair_to with
      | None ->
          if report.Macho_unwind.issues = [] then `Ok ()
          else `Error (false, "the compact unwind information is inconsistent")
      | Some path ->
          (match Macho_unwind.repair_to_file img report path with
          | Error err ->
              Logger.errorf ~section:"MACHO" "macho-unwind: %s" err;
              `Error (false, err)
          | Ok () ->
              Logger.infof ~section:"MACHO" "repaired image written to %s" path;
              (* the repair is only useful when it settles the image, so the
                 repaired copy is checked again before the command reports
                 success *)
              let repaired =
                match Macho_image.of_file path with
                | exception Macho_image.Parse_error _ -> None
                | repaired_img -> Some (Macho_unwind.check repaired_img)
              in
              (match repaired with
              | None -> `Error (false, "the repaired image cannot be read back")
              | Some r ->
                  print_string (Macho_unwind.format_report r);
                  if r.Macho_unwind.issues = [] then `Ok ()
                  else `Error (false, "the compact unwind information is still inconsistent"))))

let macho_unwind_cmd =
  let doc =
    "Inspect the compact unwind information of a Mach-O image through its \
     LC_ROUTINES and LC_ROUTINES64 load commands"
  in
  let input =
    let doc = "Mach-O image to inspect" in
    Arg.(required & opt (some string) None & info [ "i"; "input" ] ~docv:"FILE" ~doc)
  in
  let repair_to =
    let doc = "Write the repaired image to this path" in
    Arg.(value & opt (some string) None & info [ "o"; "output" ] ~docv:"FILE" ~doc)
  in
  let term = Term.(ret (const run_macho_unwind $ input $ repair_to)) in
  Cmd.v (Cmd.info "macho-unwind" ~doc) term
