open Vm_ir
let () =
  let asm = {|
    mov x0, #42
    cmp x0, #40
    b.gt .Lgreater
    mov x0, #1
    ret
.Lgreater:
    add x0, x0, #8
    ret
  |} in
  match Arm64_lifter.lift_function asm with
  | Error e -> Printf.eprintf "lift: %s\n" e; exit 1
  | Ok func ->
      (* simulate post-inject B0: [mov; cmp; Bridge_to_flow d; Bridge_to_math d; jcc] *)
      let digest = 0x17BFD8FFBDBB3042L in
      let b0 = Hashtbl.find func.Ir.cfg.blocks 0 in
      (* pair BEFORE terminator, as inject_bridge_transitions does *)
      let rev = List.rev b0.Ir.instrs in
      let injected = match rev with
        | (Ir.Jcc _ as j) :: rest -> List.rev rest @ [ Ir.Bridge_to_flow digest; Ir.Bridge_to_math digest; j ]
        | _ -> b0.Ir.instrs @ [ Ir.Bridge_to_flow digest; Ir.Bridge_to_math digest ] in
      let b0' = { b0 with Ir.instrs = injected } in
      Hashtbl.replace func.Ir.cfg.blocks 0 b0';
      for seed = 1 to 8 do
        let rng = Random.State.make [| seed |] in
        (* replicate the emitter's per-block junk pass *)
        let junked = Native_vm.Vm_transform.inject_junk_instructions ~density:0.5 ~rng b0'.Ir.instrs in
        let pos = List.fold_left (fun (i, acc) (instr : Ir.instr) ->
          (i+1, (match instr with
            | Ir.Bridge_to_flow _ -> acc @ [Printf.sprintf "%d:FLOW" i]
            | Ir.Bridge_to_math _ -> acc @ [Printf.sprintf "%d:MATH" i]
            | Ir.Jcc _ -> acc @ [Printf.sprintf "%d:JCC" i]
            | Ir.Cmp _ -> acc @ [Printf.sprintf "%d:CMP" i]
            | _ -> acc)))
          (0, []) junked |> snd in
        let pair_ok = match pos with
          | a :: b :: _ when a="2:FLOW" && b="3:MATH" -> "pair-adjacent"
          | a :: b :: _ when a="3:FLOW" && b="4:MATH" -> "pair-adjacent(junk-before)"
          | _ -> "*** PAIR SPLIT *** " ^ String.concat "," pos
        in
        Printf.printf "seed=%d len=%d  %s %s\n" seed (List.length junked)
          (String.concat "," pos) pair_ok
      done
