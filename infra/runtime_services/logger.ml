type level =
  | Debug
  | Info
  | Warn
  | Error
  | Quiet

let level_to_int = function
  | Debug -> 0
  | Info -> 1
  | Warn -> 2
  | Error -> 3
  | Quiet -> 4

let level_to_string = function
  | Debug -> "DEBUG"
  | Info -> "INFO"
  | Warn -> "WARN"
  | Error -> "ERROR"
  | Quiet -> "QUIET"

let level_of_string s =
  match String.lowercase_ascii (String.trim s) with
  | "debug" -> Some Debug
  | "info" -> Some Info
  | "warn" | "warning" -> Some Warn
  | "error" -> Some Error
  | "quiet" | "silent" -> Some Quiet
  | _ -> None

let init_level () =
  match Sys.getenv_opt "ASGARD_LOG_LEVEL" with
  | Some s -> (match level_of_string s with Some lvl -> lvl | None -> Info)
  | None ->
      (match Sys.getenv_opt "ASGARD_VERBOSE" with
      | Some s when s <> "" && s <> "0" -> Debug
      | _ ->
          (match Sys.getenv_opt "ASGARD_QUIET" with
          | Some s when s <> "" && s <> "0" -> Quiet
          | _ -> Info))

let current_level = ref (init_level ())

let set_level lvl = current_level := lvl
let get_level () = !current_level
let is_enabled lvl = level_to_int lvl >= level_to_int !current_level

let init_color () =
  match Sys.getenv_opt "NO_COLOR" with
  | Some _ -> false
  | None ->
      (try Unix.isatty Unix.stderr
       with Unix.Unix_error _ -> false)

let color_enabled = ref (init_color ())

let set_color_enabled b = color_enabled := b
let is_color_enabled () = !color_enabled

let format_loc raw =
  try
    Scanf.sscanf raw "File %S, line %d" (fun f n ->
      Printf.sprintf "%s:%d" (Filename.basename f) n)
  with _ -> raw

let resolve_loc ?loc ?file ?line () =
  match loc with
  | Some l -> format_loc l
  | None ->
      (match file with
       | Some f ->
           let base = Filename.basename f in
           (match line with
            | Some n -> Printf.sprintf "%s:%d" base n
            | None -> base)
       | None -> "")

type sink = {
  write : level -> string option -> string -> string -> unit;
  flush : unit -> unit;
}

let default_sink_write lvl section loc msg =
  let use_color = !color_enabled in
  let tag =
    if use_color then
      match lvl with
      | Debug -> "\027[36m[DEBUG]\027[0m"
      | Info  -> "\027[32m[INFO ]\027[0m"
      | Warn  -> "\027[33m[WARN ]\027[0m"
      | Error -> "\027[1;31m[ERROR]\027[0m"
      | Quiet -> ""
    else
      match lvl with
      | Debug -> "[DEBUG]"
      | Info  -> "[INFO ]"
      | Warn  -> "[WARN ]"
      | Error -> "[ERROR]"
      | Quiet -> ""
  in
  let sec_tag =
    match section with
    | None -> ""
    | Some s ->
        if use_color then
          Printf.sprintf " \027[35m[%s]\027[0m" s
        else
          Printf.sprintf " [%s]" s
  in
  let loc_tag =
    if loc = "" then ""
    else if use_color then
      Printf.sprintf " \027[90m(%s)\027[0m" loc
    else
      Printf.sprintf " (%s)" loc
  in
  Printf.eprintf "%s%s%s %s\n%!" tag sec_tag loc_tag msg

let default_sink = {
  write = default_sink_write;
  flush = (fun () -> flush stderr);
}

let current_sink = ref default_sink

let set_sink s = current_sink := s
let reset_sink () = current_sink := default_sink

let log ?loc ?file ?line ?section lvl msg =
  if is_enabled lvl then
    let l_str = resolve_loc ?loc ?file ?line () in
    !current_sink.write lvl section l_str msg

let logf ?loc ?file ?line ?section lvl fmt =
  if not (is_enabled lvl) then
    Printf.ikfprintf (fun () -> ()) () fmt
  else
    Printf.ksprintf (fun msg -> log ?loc ?file ?line ?section lvl msg) fmt

let debug ?loc ?file ?line ?section msg = log ?loc ?file ?line ?section Debug msg
let debugf ?loc ?file ?line ?section fmt = logf ?loc ?file ?line ?section Debug fmt

let info ?loc ?file ?line ?section msg = log ?loc ?file ?line ?section Info msg
let infof ?loc ?file ?line ?section fmt = logf ?loc ?file ?line ?section Info fmt

let warn ?loc ?file ?line ?section msg = log ?loc ?file ?line ?section Warn msg
let warnf ?loc ?file ?line ?section fmt = logf ?loc ?file ?line ?section Warn fmt

let error ?loc ?file ?line ?section msg = log ?loc ?file ?line ?section Error msg
let errorf ?loc ?file ?line ?section fmt = logf ?loc ?file ?line ?section Error fmt

let format_step_prefix ~step ~total =
  if !color_enabled then
    Printf.sprintf "\027[1;34m[%d/%d]\027[0m" step total
  else
    Printf.sprintf "[%d/%d]" step total

let step ?loc ?file ?line ?section ~step:cur ~total msg =
  let prefix = format_step_prefix ~step:cur ~total in
  info ?loc ?file ?line ?section (Printf.sprintf "%s %s" prefix msg)

let stepf ?loc ?file ?line ?section ~step:cur ~total fmt =
  if not (is_enabled Info) then
    Printf.ikfprintf (fun () -> ()) () fmt
  else
    Printf.ksprintf (fun msg -> step ?loc ?file ?line ?section ~step:cur ~total msg) fmt
