open Random_visa_ports
open Protect_ports
open Native_vm

let wrap (cfg : Protection_config.t) : protection_config =
  wrap_config
    ~c_macro_enabled:cfg.c_macro.enabled
    ~cff_enabled:cfg.cff.enabled
    ~mba_enabled:cfg.mba.enabled
    ~mba_depth:cfg.mba.depth
    ~seed:cfg.seed
    cfg

let unwrap (pcfg : protection_config) : Protection_config.t =
  unwrap_config pcfg

let default = wrap Protection_config.default

let from_preset name =
  match Protection_config.from_preset name with
  | Ok c -> Ok (wrap c)
  | Error e -> Error e

let from_file path =
  match Protection_config.from_file path with
  | Ok c -> Ok (wrap c)
  | Error e -> Error e

let save_to_file path cfg =
  Protection_config.save_to_file path (unwrap cfg)

let init_config ~out_file ~preset =
  let res =
    match preset with
    | Some p -> from_preset p
    | None -> Ok default
  in
  match res with
  | Ok cfg ->
      save_to_file out_file cfg;
      Printf.printf "[ASGARD-5877] Protection configuration saved: %s\n" out_file;
      Ok ()
  | Error err -> Error err

let resolve ~config_file ~preset ~enable_cff ~enable_mba ~mba_depth ~seed =
  let base =
    match config_file with
    | Some path -> (
        match from_file path with
        | Ok c -> c
        | Error err ->
            prerr_endline (Printf.sprintf "[Config] Warning: %s, using default" err);
            default)
    | None -> (
        match preset with
        | Some p -> (
            match from_preset p with
            | Ok c -> c
            | Error err ->
                prerr_endline (Printf.sprintf "[Preset] Warning: %s, using default" err);
                default)
        | None -> default)
  in
  let raw = unwrap base in
  let resolved_cff = if enable_cff then true else raw.cff.enabled in
  let resolved_mba = if enable_mba then true else raw.mba.enabled in
  let resolved_mba_depth = if mba_depth <> 2 then mba_depth else raw.mba.depth in
  let resolved_seed =
    match seed with
    | Some s -> Some s
    | None -> raw.seed
  in
  let effective = {
    raw with
    seed = resolved_seed;
    cff = { raw.cff with enabled = resolved_cff };
    mba = { raw.mba with enabled = resolved_mba; depth = resolved_mba_depth };
  } in
  wrap effective
