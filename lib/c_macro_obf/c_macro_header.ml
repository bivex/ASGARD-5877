open C_macro_config

let generate_header ?(config = default_config) () =
  let p = config.macro_prefix in
  let b = Buffer.create 4096 in
  C_macro_templates.emit_base_macros b ~p;
  C_macro_guards.emit_guards_macros b ~p;
  Buffer.contents b
