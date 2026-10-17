(** Oblivious Memory Layout & Decoy Access Engine (Step 3 Tier-4+):
    Скрывает граф обращений к памяти в DBI-трассировщиках (Tenet / Pin) через:
    1. Биективное перемешивание слотов локального фрейма
    2. Позиционное твик-шифрование (Tweakable Memory Masking)
    3. Множественные чтения (1 истинное + 3 ложных) с арифметическим мультиплексором *)

type frame_scrambler = {
  n_slots     : int;     (** Количество 64-битных слотов во фрейме *)
  coprime_p   : int;     (** Взаимно простой шаг с n_slots: gcd(p, n_slots) = 1 *)
  inv_p       : int;     (** Обратный индекс по модулю n_slots *)
  offset_q    : int;     (** Сдвиг слота *)
  frame_key   : int64;   (** Ключ твик-шифрования ячеек памяти *)
}

(** Создание скремблера фрейма памяти для заданного количества слотов *)
val gen_frame_scrambler : Random.State.t -> n_slots:int -> frame_scrambler

(** Отображение логического индекса слота [0 .. n_slots-1] в физический индекс *)
val logical_to_physical_slot : frame_scrambler -> int -> int

(** Обратное отображение физического индекса в логический *)
val physical_to_logical_slot : frame_scrambler -> int -> int

(** Позиционная гамма для слота (зависящая от логического адреса и ключа фрейма) *)
val slot_tweak_mask : frame_scrambler -> logical_idx:int -> int64

(** Запись в защищенный фрейм памяти *)
val oblivious_store : frame_scrambler -> int64 array -> logical_idx:int -> int64 -> unit

(** Чтение из защищенного фрейма с генерацией 3 ложных обращений (Decoy Reads)
    и выбором истинного значения без ветвлений. Возвращает (значение, список 4 физических адресов трассы) *)
val oblivious_load_with_decoys :
  frame_scrambler -> int64 array -> logical_idx:int -> noise_seed:int64 -> int64 * int list

(** Генерация C++ EDSL AST для asgard::oblivious_mem *)
val emit_oblivious_mem_decls : Random.State.t -> Cpp_codegen.Cpp_ast.top_decl list

(** Генерация заголовочного файла C++ asgard::oblivious_mem *)
val emit_oblivious_mem_hpp : Random.State.t -> string
