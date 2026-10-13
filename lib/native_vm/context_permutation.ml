type t = {
  perm     : int array;
  inv_perm : int array;
}

let gen_permutation ~(rng : Random.State.t) ~(n : int) : t =
  let perm = Array.init n (fun i -> i) in
  for i = n - 1 downto 1 do
    let j = Random.State.int rng (i + 1) in
    let tmp = perm.(i) in
    perm.(i) <- perm.(j);
    perm.(j) <- tmp
  done;
  let inv_perm = Array.make n 0 in
  for i = 0 to n - 1 do
    inv_perm.(perm.(i)) <- i
  done;
  { perm; inv_perm }

let decompose_into_swaps (perm : int array) : (int * int) list =
  let n = Array.length perm in
  let visited = Array.make n false in
  let swaps = ref [] in
  for i = 0 to n - 1 do
    if not visited.(i) && perm.(i) <> i then begin
      let curr = ref i in
      visited.(!curr) <- true;
      while not visited.(perm.(!curr)) do
        let next = perm.(!curr) in
        swaps := (!curr, next) :: !swaps;
        visited.(next) <- true;
        curr := next
      done
    end
  done;
  List.rev !swaps

let emit_epoch_rotation_cpp (t : t) : string =
  let swaps = decompose_into_swaps t.perm in
  let lines = List.map (fun (i, j) ->
    Printf.sprintf "    std::swap(ctx.regs[%d], ctx.regs[%d]);" i j
  ) swaps in
  String.concat "\n" lines
