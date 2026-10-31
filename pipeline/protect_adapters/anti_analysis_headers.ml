(* Anti-analysis runtime header emission adapter.
   Writes the opt-in hardening headers produced by the transformation engines
   (shadow unwind, dispatch permutation, trace chaff, emulation stall) next to
   the protected application.  This is the single place in the codebase that
   knows both the engines and the filesystem layout of the output directory. *)

let write_runtime_headers ~(out_dir : string) ~(eh : bool) ~(vpc : bool) ~(chaff : bool)
    ~(stall : bool) ~(skip_existing : bool) : unit =
  let write name source =
    let path = Filename.concat out_dir name in
    if not (skip_existing && Sys.file_exists path) then begin
      let oc = open_out path in
      output_string oc source;
      close_out oc
    end
  in
  if eh then write "asg_shadow_unwind.hpp" Shadow_unwind.Shadow_unwind_engine.runtime_header_source;
  if vpc then
    write "asg_dispatch_permutation.hpp"
      (Dispatch_permutation.Dispatch_permutation_engine.emit_dispatch_permutation_cpp_header ());
  if chaff then
    write "asg_trace_chaff.hpp" (Trace_chaff.Trace_chaff_engine.emit_trace_chaff_cpp_header ());
  if stall then
    write "asg_emulation_stall.hpp"
      (Emulation_stall.Emulation_stall_engine.emit_emulation_stall_cpp_header ())
