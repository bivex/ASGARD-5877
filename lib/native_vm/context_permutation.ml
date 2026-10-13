open Int64

type t = {
  perm     : int array;
  inv_perm : int array;
}

type epoch_schedule = {
  n_regs       : int;
  epoch_perms  : int array array;
  inv_perms    : int array array;
  epoch_masks  : int64 array;
}

let fisher_yates (rng : Random.State.t) (n : int) : int array =
  let a = Array.init n (fun i -> i) in
  for i = n - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let tmp = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- tmp
  done;
  a

let invert_perm (p : int array) : int array =
  let n = Array.length p in
  let inv = Array.make n 0 in
  for i = 0 to n - 1 do
    inv.(p.(i)) <- i
  done;
  inv

let gen_permutation ~(rng : Random.State.t) ~(n : int) : t =
  let perm = fisher_yates rng n in
  let inv_perm = invert_perm perm in
  { perm; inv_perm }

let gen_epoch_schedule (rng : Random.State.t) ~(n_regs : int) ~(n_epochs : int) : epoch_schedule =
  let epoch_perms = Array.init n_epochs (fun _ -> fisher_yates rng n_regs) in
  let inv_perms = Array.map invert_perm epoch_perms in
  let epoch_masks = Array.init n_epochs (fun _ -> Random.State.int64 rng max_int) in
  { n_regs; epoch_perms; inv_perms; epoch_masks }

let physical_slot (sched : epoch_schedule) ~(epoch : int) ~(reg_id : int) : int =
  let ep = epoch mod (Array.length sched.epoch_perms) in
  sched.epoch_perms.(ep).(reg_id)

(** ИСПРАВЛЕНИЕ P0-BUG-01:
    Пусть массив A должен перейти в состояние B, где для каждого старого индекса i
    значение перемещается в целевой слот target.(i): B.(target.(i)) = A.(i).
    Любой цикл (i_0 -> i_1 -> ... -> i_{k-1} -> i_0) реализуется ровно (k - 1)
    последовательными транспозициями:
    swap(i_0, i_1); swap(i_0, i_2); ...; swap(i_0, i_{k-1}). *)
let decompose_into_swaps (target : int array) : (int * int) list =
  let n = Array.length target in
  let visited = Array.make n false in
  let swaps = ref [] in
  for i = 0 to n - 1 do
    if not visited.(i) && target.(i) <> i then begin
      let cycle = ref [i] in
      visited.(i) <- true;
      let curr = ref target.(i) in
      while !curr <> i do
        visited.(!curr) <- true;
        cycle := !curr :: !cycle;
        curr := target.(!curr)
      done;
      let elements = List.rev (List.filter (fun x -> x <> i) !cycle) in
      List.iter (fun x -> swaps := (i, x) :: !swaps) elements
    end
  done;
  List.rev !swaps

let apply_swaps_in_place (regs : int64 array) (swaps : (int * int) list) : unit =
  List.iter (fun (u, v) ->
    if u <> v then begin
      let tmp = regs.(u) in
      regs.(u) <- regs.(v);
      regs.(v) <- tmp
    end
  ) swaps

let emit_epoch_rotation_cpp (t : t) : string =
  let swaps = decompose_into_swaps t.inv_perm in
  let lines = List.map (fun (i, j) ->
    Printf.sprintf "    std::swap(ctx.regs[%d], ctx.regs[%d]);" i j
  ) swaps in
  String.concat "\n" lines

let emit_schedule_epoch_rotation_cpp (sched : epoch_schedule) ~(from_epoch : int) ~(to_epoch : int) : string =
  let n_ep = Array.length sched.epoch_perms in
  let e_from = from_epoch mod n_ep in
  let e_to   = to_epoch mod n_ep in
  let target = Array.init sched.n_regs (fun s ->
    let r = sched.inv_perms.(e_from).(s) in
    sched.epoch_perms.(e_to).(r)
  ) in
  let swaps = decompose_into_swaps target in
  let buf = Buffer.create 512 in
  Buffer.add_string buf (Printf.sprintf
    "__attribute__((always_inline)) inline void rotate_context_epoch_%d_to_%d(uint64_t* regs) noexcept {\n"
    e_from e_to);
  List.iter (fun (u, v) ->
    Buffer.add_string buf (Printf.sprintf
      "    { uint64_t t = regs[%d]; regs[%d] = regs[%d]; regs[%d] = t; }\n" u u v v)
  ) swaps;
  Buffer.add_string buf "}\n";
  Buffer.contents buf
