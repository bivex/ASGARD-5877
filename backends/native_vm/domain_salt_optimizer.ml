(* lib/native_vm/domain_salt_optimizer.ml
   ASGARD-5877: Dispatch Table Domain Salt & Permutation Optimizer *)

open Random_visa_ports

let popcount8 (x : int) : int =
  let x = x - ((x lsr 1) land 0x55) in
  let x = (x land 0x33) + ((x lsr 2) land 0x33) in
  (x + (x lsr 4)) land 0x0F

let default_opcode_frequencies () : float array =
  let freqs = Array.make 256 0.0001 in
  (* High-frequency ALU, control-flow, and memory opcodes (first 32) *)
  for i = 0 to 31 do
    freqs.(i) <- 0.025
  done;
  (* Intermediate frequency helpers and flags (32..63) *)
  for i = 32 to 63 do
    freqs.(i) <- 0.005
  done;
  (* Normalize to probability distribution *)
  let sum = Array.fold_left ( +. ) 0.0 freqs in
  for i = 0 to 255 do
    freqs.(i) <- freqs.(i) /. sum
  done;
  freqs

let calculate_frequency_variance
    ~(domain_salts : int array)
    ?(frequencies = default_opcode_frequencies ())
    () : float =
  let k = Array.length domain_salts in
  if k <= 0 then 0.0
  else
    let k_float = float_of_int k in
    let slot_freqs = Array.make 256 0.0 in
    for d = 0 to k - 1 do
      let salt = domain_salts.(d) in
      for op = 0 to 255 do
        let slot = op lxor salt in
        slot_freqs.(slot) <- slot_freqs.(slot) +. (frequencies.(op) /. k_float)
      done
    done;
    let mean = 1.0 /. 256.0 in
    let var_sum = ref 0.0 in
    for i = 0 to 255 do
      let diff = slot_freqs.(i) -. mean in
      var_sum := !var_sum +. (diff *. diff)
    done;
    !var_sum /. 256.0

let score_salts (salts : int array) (freqs : float array) : float =
  let k = Array.length salts in
  let variance = calculate_frequency_variance ~domain_salts:salts ~frequencies:freqs () in
  let hamming_sum = ref 0 in
  let pairs = ref 0 in
  for i = 0 to k - 1 do
    for j = i + 1 to k - 1 do
      incr pairs;
      hamming_sum := !hamming_sum + popcount8 (salts.(i) lxor salts.(j))
    done
  done;
  let avg_hamming =
    if !pairs > 0 then float_of_int !hamming_sum /. float_of_int (!pairs * 8)
    else 0.5
  in
  (* Minimize variance (frequency peaking) while maximizing Hamming dispersion *)
  (variance *. 10000.0) -. (avg_hamming *. 0.1)

let optimize_domain_salts
    ~rng
    ~num_domains
    ?(frequencies = default_opcode_frequencies ())
    ?(iterations = 1200)
    () : int array =
  if num_domains <= 1 then [| 0x5A land 0xFF |]
  else
    let k = num_domains in
    (* 1. Initialize with distinct non-zero salts *)
    let used = Hashtbl.create k in
    let current_salts = Array.make k 0 in
    for d = 0 to k - 1 do
      let rec pick () =
        let s = (Random.State.int rng 255) + 1 in
        if Hashtbl.mem used s then pick ()
        else begin
          Hashtbl.replace used s ();
          s
        end
      in
      current_salts.(d) <- pick ()
    done;

    let best_salts = Array.copy current_salts in
    let current_score = ref (score_salts current_salts frequencies) in
    let best_score = ref !current_score in
    let temp = ref 1.0 in
    let cooling = 0.996 in

    (* 2. Simulated annealing local search *)
    for _iter = 1 to iterations do
      let d = Random.State.int rng k in
      let old_val = current_salts.(d) in
      let candidate = (Random.State.int rng 255) + 1 in
      let already_used =
        let found = ref false in
        for i = 0 to k - 1 do
          if i <> d && current_salts.(i) = candidate then found := true
        done;
        !found
      in
      if not already_used then begin
        current_salts.(d) <- candidate;
        let new_score = score_salts current_salts frequencies in
        let delta = new_score -. !current_score in
        if delta <= 0.0 || Random.State.float rng 1.0 < exp (-. delta /. max 1e-4 !temp) then begin
          current_score := new_score;
          if new_score < !best_score then begin
            best_score := new_score;
            Array.blit current_salts 0 best_salts 0 k
          end
        end else begin
          (* Revert mutation *)
          current_salts.(d) <- old_val
        end;
        temp := !temp *. cooling
      end
    done;

    Logger.debugf ~loc:__LOC__ ~section:"DOMAIN_SALT"
      "Optimized %d domain salts: [%s] (spectral score: %.4f)"
      k
      (String.concat "; " (List.map (Printf.sprintf "0x%02X") (Array.to_list best_salts)))
      !best_score;
    best_salts
