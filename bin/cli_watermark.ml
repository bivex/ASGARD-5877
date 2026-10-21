open Cmdliner

let run_extract (manifest_file : string) (candidates : string list) =
  if not (Sys.file_exists manifest_file) then begin
    prerr_endline (Printf.sprintf "Error: Manifest file not found: %s" manifest_file);
    `Error (false, Printf.sprintf "Manifest file not found: %s" manifest_file)
  end else
    match Watermark.Wm_chooser.load_manifest manifest_file with
    | Error err ->
        prerr_endline (Printf.sprintf "Error loading manifest: %s" err);
        `Error (false, err)
    | Ok manifest ->
        Printf.printf "==================================================================\n";
        Printf.printf "🔍  ASGARD-5877: Offline Build-Seed Watermark Extraction\n";
        Printf.printf "==================================================================\n";
        Printf.printf "Build ID:        %s\n" manifest.build_id;
        Printf.printf "Derivation Key:  0x%016LX\n" manifest.derivation_key;
        Printf.printf "Recorded Points: %d choice sites\n\n" (List.length manifest.carrier_points);

        let candidate_ints =
          List.filter_map
            (fun s ->
              try Some (Int64.of_string s)
              with _ ->
                prerr_endline (Printf.sprintf "Warning: ignoring invalid candidate payload: %s" s);
                None)
            candidates
        in

        let candidates_to_eval =
          if candidate_ints = [] then [ manifest.client_payload ]
          else candidate_ints
        in

        List.iteri
          (fun idx cand ->
            let res =
              Watermark.Wm_extract.evaluate_candidate
                ~derivation_key:manifest.derivation_key
                ~candidate_payload:cand
                ~observed_points:manifest.carrier_points
            in
            let is_match = res.confidence >= 0.70 && res.total_carrier_pts > 0 in
            Printf.printf "[Candidate %d] Payload: 0x%016LX\n" (idx + 1) cand;
            Printf.printf "    Confidence:      %.2f%%\n" (res.confidence *. 100.0);
            Printf.printf "    Carrier Points:  %d observed (%d matched)\n" res.total_carrier_pts res.matching_points;
            Printf.printf "    Recovered ID:    0x%016LX\n" res.recovered_payload;
            Printf.printf "    Status:          %s\n\n"
              (if is_match then "✅ WATERMARK VERIFIED (GENUINE LICENSE MATCH)"
               else "❌ REJECTED (NO MATCH)"))
          candidates_to_eval;

        Printf.printf "==================================================================\n";
        `Ok ()

let manifest_arg =
  let doc = "Path to vendor build manifest JSON file" in
  Arg.(required & opt (some string) None & info [ "m"; "manifest" ] ~docv:"FILE" ~doc)

let candidates_arg =
  let doc = "Candidate client payload IDs (hex or decimal) to test against manifest" in
  Arg.(value & opt_all string [] & info [ "c"; "candidate" ] ~docv:"PAYLOAD" ~doc)

let extract_cmd =
  let doc = "Offline build-seed watermark verification and client ID extraction" in
  let info = Cmd.info "extract-watermark" ~doc in
  let term = Term.(ret (const run_extract $ manifest_arg $ candidates_arg)) in
  Cmd.v info term
