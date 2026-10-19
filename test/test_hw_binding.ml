(* Hardware binding of the decryption key.

   The stack runtime mixes the emulation differential (CPUID / timer
   consistency) into the rolling key: on real hardware the penalty is
   zero and the decryption is untouched, but in a slow emulator the key
   becomes wrong and the bytecode decrypts into garbage, so the
   protected program fails closed.  Patching the probe out therefore also
   breaks the decryption - the check cannot simply be removed.

   These tests pin that the probe is emitted and mixed into the key
   when the binding is enabled, and that it is left out when it is not. *)

open Stack_vm.Stack_ir
module Rt = Stack_vm.Stack_runtime

let make_prog () =
  let blocks = Hashtbl.create 4 in
  Hashtbl.replace blocks 0
    { id = 0; label = "entry"; ops = [ PushImm 42L; PopReg 0; Exit ] };
  { entry_id = 0; blocks; context_slots = 16 }

let header ?(hw_binding = true) () =
  let cfg = Rt.default_config Rt.X86_64 in
  let cfg = { cfg with enable_hw_binding = hw_binding } in
  Rt.generate_c_runtime cfg (make_prog ())

let find_sub (hay : string) (needle : string) =
  let hl = String.length hay and nl = String.length needle in
  let rec scan i =
    if i + nl > hl then None
    else if String.sub hay i nl = needle then Some i
    else scan (i + 1)
  in
  if nl = 0 then Some 0 else scan 0

let contains hay needle = find_sub hay needle <> None

let test_probe_is_emitted () =
  let h = header () in
  Alcotest.(check bool) "the emulation probe is in the runtime" true
    (contains h "evaluate_emulation_differential");
  Alcotest.(check bool) "the probe namespace is in the runtime" true
    (contains h "asgard_anti_emulation");
  Alcotest.(check bool) "the penalty is mixed into the rolling key" true
    (contains h "vm.vkey ^= asgard_anti_emulation::evaluate_emulation_differential()");
  Alcotest.(check bool) "the probe is defined before it is used" true
    (match
       ( find_sub h "vm.vkey ^= asgard_anti_emulation",
         find_sub h "static inline __attribute__((always_inline)) uint64_t evaluate_emulation_differential()" )
     with
     | Some mixing, Some definition -> definition < mixing
     | _ -> false)

let test_binding_can_be_disabled () =
  let h = header ~hw_binding:false () in
  Alcotest.(check bool) "no probe when the binding is off" false
    (contains h "evaluate_emulation_differential");
  Alcotest.(check bool) "no key mixing when the binding is off" false
    (contains h "vm.vkey ^= asgard_anti_emulation")

let test_hypervisor_is_not_penalised_by_default () =
  (* A virtual machine is a legitimate deployment target: the hypervisor
     bit must not contribute to the default penalty, otherwise every
     licensed VM would break. *)
  let h = header () in
  (* the body of the default differential probe must not contain the
     hypervisor penalty *)
  let body =
    match find_sub h "uint64_t evaluate_emulation_differential() noexcept {" with
    | None -> ""
    | Some i ->
        let rest = String.sub h i (String.length h - i) in
        let stop =
          match find_sub rest "\n}" with Some j -> j | None -> String.length rest
        in
        String.sub rest 0 stop
  in
  Alcotest.(check bool) "the hypervisor bit is not in the default penalty" false
    (contains body "Hypervisor bit detected");
  (* ... but the probe is still available for an explicit opt-in *)
  Alcotest.(check bool) "the hypervisor probe is available separately" true
    (contains h "evaluate_hypervisor_bit")

let () =
  Alcotest.run "asgard hardware binding"
    [
      ( "stack runtime",
        [
          Alcotest.test_case "the probe is emitted and mixed into the key" `Quick
            (fun () -> test_probe_is_emitted ());
          Alcotest.test_case "the binding can be disabled" `Quick
            (fun () -> test_binding_can_be_disabled ());
          Alcotest.test_case "a hypervisor is not penalised by default" `Quick
            (fun () -> test_hypervisor_is_not_penalised_by_default ());
        ] );
    ]
