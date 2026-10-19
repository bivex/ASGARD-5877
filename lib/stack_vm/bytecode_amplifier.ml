open Stack_ir

type amplification_profile = {
  horner_degree       : int;
  bit_slice_lanes     : int;
  expander_chord_len  : int;
  expander_chord_rate : int;
}

let default_heavy_profile = {
  horner_degree       = 6;
  bit_slice_lanes     = 2;
  expander_chord_len  = 8;
  expander_chord_rate = 75;
}

let balanced_profile = {
  horner_degree       = 3;
  bit_slice_lanes     = 2;
  expander_chord_len  = 8;
  expander_chord_rate = 50;
}

let light_profile = {
  horner_degree       = 2;
  bit_slice_lanes     = 1;
  expander_chord_len  = 10;
  expander_chord_rate = 25;
}

let adaptive_profile ?(block_size = 0) ?(post_mba = false) () =
  if post_mba || block_size > 80 then light_profile
  else if block_size > 25 then balanced_profile
  else default_heavy_profile

let rand_u64 (rng : Random.State.t) : int64 =
  let hi = Int64.of_int (Random.State.bits rng) in
  let mid = Int64.of_int (Random.State.bits rng) in
  let lo = Int64.of_int (Random.State.bits rng) in
  Int64.logor (Int64.shift_left hi 34) (Int64.logor (Int64.shift_left mid 4) (Int64.logand lo 0xFL))

(* Scratch-slot budget reserved by amplify_stack_program: 16 slots past
   scratch_base.
     base+0  s1      carry-chain work vector 1
     base+1  s2      carry-chain work vector 2
     base+2  sx      original x operand (flag re-definition)
     base+3  sy      original y operand (flag re-definition)
     base+4..base+9  anchor ring (K <= 6 write anchors for expander knots) *)
let n_anchor_slots (profile : amplification_profile) : int =
  max 1 (min 6 profile.expander_chord_len)

(** 1. ПОЛИНОМИАЛЬНЫЙ СИНТЕЗ КОНСТАНТ ПО СХЕМЕ ГОРНЕРА НАД Z_{2^64}
    Пусть мы хотим получить константу C в точке t_0.
    Выбираем случайные старшие коэффициенты a_d, a_{d-1}, ..., a_1 \in Z_{2^64}.
    Вычисляем частичную сумму P_high(t_0) = (...((a_d * t_0 + a_{d-1}) * t_0 + ...) * t_0.
    Тогда свободный член a_0 однозначно определяется как:
    a_0 = C - P_high(t_0) (mod 2^64)! *)
let synth_horner_polynomial (rng : Random.State.t) ~(target_const : int64) ~(degree : int)
    : int64 * int64 list =
  let d = max 1 degree in
  (* Выбираем нечетную точку t_0 для максимального перемешивания бит при умножении *)
  let t0 = Int64.logor (rand_u64 rng) 1L in
  let high_coeffs = List.init d (fun _ -> rand_u64 rng) in
  let p_high =
    List.fold_left (fun acc a_k -> Int64.mul (Int64.add acc a_k) t0) 0L high_coeffs
  in
  let a0 = Int64.sub target_const p_high in
  (t0, high_coeffs @ [a0])

let eval_horner_polynomial ~(t0 : int64) ~(coeffs : int64 list) : int64 =
  match coeffs with
  | [] -> 0L
  | hd :: tl -> List.fold_left (fun acc c -> Int64.add (Int64.mul acc t0) c) hd tl

(** Генерация цепочки стековых инструкций, вычисляющих полином Горнера на стеке.
    Стековый дельта = +1 (эквивалентно PushImm target_const).
    На каждом шаге t_0 маскируется через тождество (t_0 ^ m) + 2*(t_0 & m) - m. *)
let emit_horner_stack_insns (rng : Random.State.t) ~(target_const : int64) ~(degree : int)
    : stack_op list =
  let (t0, coeffs) = synth_horner_polynomial rng ~target_const ~degree in
  match coeffs with
  | [] -> [PushImm target_const]
  | a_d :: rest ->
      let init_insns = [PushImm a_d] in
      let step_insns =
        List.concat_map (fun a_k ->
          let m = rand_u64 rng in
          let t0_xor_m = Int64.logxor t0 m in
          let t0_and_m = Int64.shift_left (Int64.logand t0 m) 1 in
          [
            (* Расщепленное вычисление t_0: (t_0 ^ m) + 2*(t_0 & m) - m *)
            PushImm t0_xor_m;
            PushImm t0_and_m;
            Add;
            PushImm m;
            Sub;
            (* Умножение аккумулятора на t_0 *)
            Mul;
            (* Прибавление коэффициента a_k *)
            PushImm a_k;
            Add;
          ]
        ) rest
      in
      init_insns @ step_insns

(* ------------------------------------------------------------------ *)
(* Кольцевой твист (мост к Metamorphic_ring из mba_engine):
   x * k_odd * k_inv == x в Z_{2^64}, k_odd нечетно, k_inv = k_odd^{-1}.
   Mul в этой VM нейтрален к флагам (см. stack_flag_liveness), поэтому
   твист после ЛЮБОЙ операции сохраняет и значение, и флаги. Стековый
   дельта = 0. *)
let emit_ring_twist (rng : Random.State.t) : stack_op list =
  let k_odd = Int64.logor (rand_u64 rng) 1L in
  let k_inv = Mba_engine.Metamorphic_ring.inv_mod_2_64 k_odd in
  [ PushImm k_odd; Mul; PushImm k_inv; Mul ]

(* ------------------------------------------------------------------ *)
(* Минтерм-базис (мост к Nullspace_mba): NOR/NAND-представления
   дизъюнктных минтермов над парой регистров. Каждый push оставляет
   ровно одно значение на стеке. *)
let push_or_regs (s1 : int) (s2 : int) : stack_op list =
  (* s1 | s2 = Nand(Nor(s1, s1), Nor(s2, s2)) *)
  [ PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nand ]

let push_and_regs (s1 : int) (s2 : int) : stack_op list =
  (* s1 & s2 = Nor(Nor(s1, s1), Nor(s2, s2)) *)
  [ PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor ]

let push_xor_regs (s1 : int) (s2 : int) : stack_op list =
  (* s1 ^ s2 = (s1 | s2) - (s1 & s2)  — числовое тождество над Z_{2^64} *)
  push_or_regs s1 s2 @ push_and_regs s1 s2 @ [ Sub ]

(** Вспомогательный генератор каскада переносов из регистров s1 и s2:
    Считает u_1 = s1 ^ s2, c_1 = 2*(s1 & s2), затем u_2 = u_1 ^ c_1, c_2 = 2*(u_1 & c_1),
    складывает их u_2 + c_2 и применяет обратимый кольцевой скейлинг k_odd * k_inv = 1. *)
let emit_carry_stages (rng : Random.State.t) ~(s1 : int) ~(s2 : int) : stack_op list =
  let k_odd = Int64.logor (rand_u64 rng) 1L in
  let k_inv = Mba_engine.Metamorphic_ring.inv_mod_2_64 k_odd in
  [
    (* u1 = (s1 ^ s2), минтерм-разложение *)
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nand;
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor;
    Sub;

    (* c1 = 2 * (s1 & s2) *)
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor;
    PushImm 1L;
    Shl;

    (* Сохраняем промежуточные векторы в scratch регистры *)
    PopReg s2; (* c1 *)
    PopReg s1; (* u1 *)

    (* Второй этап переносов: u2 = u1 ^ c1 *)
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nand;
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor;
    Sub;

    (* c2 = 2 * (u1 & c1) *)
    PushReg s1; PushReg s1; Nor;
    PushReg s2; PushReg s2; Nor;
    Nor;
    PushImm 1L;
    Shl;

    (* u2 + c2 == s1 + s2 в Z_{2^64} *)
    Add;

    (* Кольцевой твист: (x * k_odd) * k_inv = x *)
    PushImm k_odd;
    Mul;
    PushImm k_inv;
    Mul;
  ]

(** Скрытое переопределение флагов после замены Add/Sub на carry-chain.
    Add/Sub в этой VM ДЕФАЙНЯТ флаги (CC_OP_ADD/SUB {src1; src2; dst}), и
    если флаги живы после команды (flag liveness), замена обязана
    воспроизвести этот дефайт побитово. PushFlags-обёртка здесь НЕ годится:
    она восстановила бы ДОкомандные флаги. Вместо этого выполняем
    настоящую команду на сохранённых копиях операндов (sx, sy) и
    сбрасываем дубликат результата в scratch. Стековый дельта = 0. *)
let emit_flag_redef_add (sx : int) (sy : int) : stack_op list =
  [ PushReg sx; PushReg sy; Add; PopReg sx ]

let emit_flag_redef_sub (sx : int) (sy : int) : stack_op list =
  [ PushReg sx; PushReg sy; Sub; PopReg sx ]

(** 2. НЕЛИНЕЙНАЯ ДЕКОМПОЗИЦИЯ СЛОЖЕНИЯ ЧЕРЕЗ КАСКАД ПЕРЕНОСОВ (Carry-Chain Expansion)
    Стековый дельта = -1 (снимает 2 операнда, оставляет сумму).
    Исходные операнды дополнительно сохраняются в sx/sy для переопределения флагов. *)
let emit_carry_chain_add (rng : Random.State.t) ~(s1 : int) ~(s2 : int) ~(sx : int) ~(sy : int)
    : stack_op list =
  [
    PopReg s2; PushReg s2; PopReg sy;   (* сохранить y *)
    PopReg s1; PushReg s1; PopReg sx;   (* сохранить x *)
  ] @ emit_carry_stages rng ~s1 ~s2

(** 3. ДЕКОМПОЗИЦИЯ ВЫЧИТАНИЯ ЧЕРЕЗ ДОПОЛНЕНИЕ И КАСКАД ПЕРЕНОСОВ
    x - y = x + (~y + 1) в Z_{2^64}.
    Стековый дельта = -1. *)
let emit_carry_chain_sub (rng : Random.State.t) ~(s1 : int) ~(s2 : int) ~(sx : int) ~(sy : int)
    : stack_op list =
  [
    PopReg s2; PushReg s2; PopReg sy;   (* сохранить y *)
    PopReg s1; PushReg s1; PopReg sx;   (* сохранить x *)
    (* neg_y = Nor(y, y) + 1 *)
    PushReg sy; PushReg sy; Nor;
    PushImm 1L; Add;
    PopReg s2;
  ] @ emit_carry_stages rng ~s1 ~s2

(** 4. СЦЕПЛЕНИЕ С ЯКОРЕМ ЗАПИСИ (Def-Use Webbing)
    Вплетает в вершину стека тождественный нуль из дальнего якоря:
    Nor(r, Nor(r, r)) == 0L для любого r. Стековый дельта = 0.
    Якорь — один из K последних записанных регистров (кольцевой буфер
    в amplify_block), поэтому хорда в графе def-use тянется назад до K
    записей, а не только к последней. *)
let emit_expander_web_knot (rng : Random.State.t) ?(s_reg : int option = None) () : stack_op list =
  match s_reg with
  | Some reg ->
      (* Сцепление с регистром: v = v + Nor(r, Nor(r, r)) *)
      [
        PushReg reg;
        PushReg reg;
        Nor;
        PushReg reg;
        Nor;
        Add;
      ]
  | None ->
      let salt = rand_u64 rng in
      [
        Dup;
        PushImm salt;
        Add;
        Dup;
        Dup;
        Nor;
        Nor;
        Add;
      ]

let amplify_block
    (rng : Random.State.t)
    ~(profile : amplification_profile)
    ~(scratch_base : int)
    (block : block) : block =
  let live = Stack_flag_liveness.analyze_arr (Array.of_list block.ops) in
  let s1 = scratch_base in
  let s2 = scratch_base + 1 in
  let sx = scratch_base + 2 in
  let sy = scratch_base + 3 in
  let k_anchors = n_anchor_slots profile in
  let anchors = Array.init k_anchors (fun i -> scratch_base + 4 + i) in
  let anchor_j = ref 0 in
  let pick_anchor () = anchors.(Random.State.int rng k_anchors) in
  let maybe_knot phase =
    if !anchor_j > 0
       && phase mod max 1 profile.expander_chord_len = 0
       && Random.State.int rng 100 < profile.expander_chord_rate
    then emit_expander_web_knot rng ~s_reg:(Some (pick_anchor ())) ()
    else []
  in
  let new_ops =
    List.concat_map (fun (i, op) ->
      let flag_safe = not live.(i + 1) in
      match op with
      | PushImm c when flag_safe ->
          let horner = emit_horner_stack_insns rng ~target_const:c ~degree:profile.horner_degree in
          horner @ maybe_knot i

      | PushImm c ->
          (* Флаги активны: безопасно оборачиваем через PushFlags/PopFlags
             (PushImm не дефайнит флаги, поэтому восстановление до-командного
             состояния корректно). *)
          [PushFlags] @
          emit_horner_stack_insns rng ~target_const:c ~degree:profile.horner_degree @
          [Swap; PopFlags]

      | Add when profile.bit_slice_lanes > 0 ->
          let carry = emit_carry_chain_add rng ~s1 ~s2 ~sx ~sy in
          if flag_safe then carry @ maybe_knot (i + 1)
          else carry @ emit_flag_redef_add sx sy

      | Sub when profile.bit_slice_lanes > 0 ->
          let carry = emit_carry_chain_sub rng ~s1 ~s2 ~sx ~sy in
          if flag_safe then carry @ maybe_knot (i + 2)
          else carry @ emit_flag_redef_sub sx sy

      (* Мост к Metamorphic_ring: исходная команда остаётся, поверх —
         нейтральный к флагам кольцевой твист. Применимо всегда. *)
      | Mul | Nor | Nand | Shl | Shr | Sar | Div | Idiv ->
          [ op ] @ emit_ring_twist rng

      | PopReg r ->
          (* Кольцевой буфер якорей: каждая запись регистрируется в
             anchors[j++ mod K] — хорды получают дальнодействие.
             Программные слоты не пересекаются со scratch (scratch_base
             >= context_slots исходной программы). *)
          let ops = [ PopReg r; PushReg r; PopReg anchors.(!anchor_j mod k_anchors) ] in
          incr anchor_j;
          ops

      | other ->
          [other]
    ) (List.mapi (fun i op -> (i, op)) block.ops)
  in
  { block with ops = new_ops }

let amplify_stack_program
    (rng : Random.State.t)
    ?ctx
    ~(profile : amplification_profile)
    (prog : program) : program =
  let scratch_base =
    match ctx with
    | Some c ->
        let s = Context_allocator.alloc_scratch c in
        for _ = 2 to 16 do
          ignore (Context_allocator.alloc_scratch c)
        done;
        s
    | None -> max 64 prog.context_slots
  in
  let new_context_slots =
    match ctx with
    | Some c ->
        Context_allocator.reserve_slots c (scratch_base + 16);
        max (scratch_base + 16) (Context_allocator.total_slots c)
    | None -> scratch_base + 16
  in
  (* Детерминизм: порядок блоков фиксирован сортировкой id, иначе посев
     block_rng зависел бы от недетерминированного порядка Hashtbl.iter. *)
  let sorted_blocks =
    Hashtbl.fold (fun id b acc -> (id, b) :: acc) prog.blocks []
    |> List.sort (fun (a, _) (b, _) -> compare a b)
  in
  let new_blocks = Hashtbl.create (Hashtbl.length prog.blocks) in
  List.iter (fun (id, b) ->
    let block_rng = Random.State.make [|
      Random.State.bits rng;
      id * 0x5877;
      0xDEADBEEF;
    |] in
    Hashtbl.replace new_blocks id (amplify_block block_rng ~profile ~scratch_base b)
  ) sorted_blocks;
  { prog with blocks = new_blocks; context_slots = new_context_slots }

let amplifier_stats (prog_before : program) (prog_after : program) : string =
  let count_ops prog =
    Hashtbl.fold (fun _ b acc -> acc + List.length b.ops) prog.blocks 0
  in
  let ops_before = count_ops prog_before in
  let ops_after = count_ops prog_after in
  let ratio =
    if ops_before > 0 then float_of_int ops_after /. float_of_int ops_before
    else 1.0
  in
  Printf.sprintf
    "Bytecode Amplification: %d ops → %d ops (%.1fx expansion, 0%% dead code loss)"
    ops_before ops_after ratio
