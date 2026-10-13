(** Single-Block Self-Wiping Nano-JIT (Step 5 Tier-4+):
    Уничтожает инвариант 'RIP == Instruction' и защищает от дамперов памяти.
    Все базовые блоки поочередно расшифровываются в один и тот же 128-байтный слот,
    исполняются и немедленно перезаписываются псевдослучайной гаммой в эпилоге. *)

type nano_block_ticket = {
  block_id      : int;
  encrypted_bytes : bytes;
  stream_nonce  : int64;
  wipe_gamma    : int64;
}

(** Шифрование нативного блока инструкций (до 128 байт) потоковым ключом для Nano-JIT слота *)
val seal_nano_block :
  block_id:int -> raw_code:bytes -> master_key:int64 -> nonce:int64 -> nano_block_ticket

(** Симуляция цикла жизни Nano-JIT слота (Материализация -> Исполнение -> Самозатирание гаммой).
    Возвращает (расшифрованный код во время исполнения, состояние буфера после затирания) *)
val simulate_nano_slot_lifecycle :
  nano_block_ticket -> master_key:int64 -> bytes * bytes

(** Построение C++20 AST контроллера самозатирающегося 128-байтного слота Nano-JIT *)
val build_nano_jit_slot_ast : unit -> Cpp_codegen.Cpp_ast.top_decl list

(** Эмиссия C++20 контроллера самозатирающегося 128-байтного слота Nano-JIT *)
val emit_self_wiping_nano_jit_hpp : unit -> string
