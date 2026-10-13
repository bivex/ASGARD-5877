(** Алгебраический синтезатор метаморфной ISA для ASGARD-5877:
    - Несепарабельное Mixed-Radix кодирование (защита от DSE/Triton bit-tainting)
    - Синтез функционально полного базиса АЛУ в GL(2, Z_{2^64})
    - Потоковый автомат Мили для динамического переключения архетипов длин
    - Континуум адресации Stack-Reg-Accumulator *)

type addressing_endpoint =
  | EpStack                 (** Выборка/запись через вершину виртуального стека (TOS) *)
  | EpReg of int            (** Индекс виртуального регистра 0 .. n_regs - 1 *)
  | EpAcc of int            (** Внутренний теневой аккумулятор диспетчера 0 .. 3 *)

type hybrid_routing = {
  dst  : addressing_endpoint;
  src1 : addressing_endpoint;
  src2 : addressing_endpoint;
}

type synthetic_alu_op = {
  opcode_id : int;
  c_xor     : int64;        (** Коэффициент при (x ^ y) *)
  c_and     : int64;        (** Коэффициент при (x & y) *)
  bias      : int64;        (** Аддитивная константа смещения в Z_{2^64} *)
}

type alu_basis_pair = {
  psi1   : synthetic_alu_op;
  psi2   : synthetic_alu_op;
  inv_11 : int64;
  inv_12 : int64;
  inv_21 : int64;
  inv_22 : int64;
}

type std_alu_op =
  | StdAdd
  | StdSub
  | StdXor
  | StdAnd
  | StdOr

type isa_radix_spec = {
  n_opcodes   : int;        (** Нечетная/простая база опкодов (не степень 2) *)
  n_regs      : int;        (** Простая база регистров (не степень 2) *)
  n_routes    : int;        (** Число гибридных маршрутов адресации *)
  affine_a    : int64;      (** Нечетный множитель скремблирования в Z_{2^64} *)
  affine_ainv : int64;      (** Мультипликативно обратный элемент a^{-1} mod 2^64 *)
  affine_b    : int64;      (** Аддитивный сдвиг *)
}

type raw_instruction = {
  opcode   : int;
  rd       : int;
  rs1      : int;
  rs2      : int;
  route_id : int;
  imm16    : int;
}

(** Вычисление a^{-1} mod 2^64 методом Ньютона-Гензеля для нечетного a *)
val inv_odd_64 : int64 -> int64

(** Генерация пары синтетических операторов (\Psi_1, \Psi_2), образующих обратимый базис в GL(2, Z_{2^64}) *)
val synth_orthogonal_alu_basis :
  Random.State.t -> op1_id:int -> op2_id:int -> alu_basis_pair

(** Исполнение синтетического оператора \Psi(x, y) в эталонной семантике *)
val eval_synthetic_op : synthetic_alu_op -> int64 -> int64 -> int64

(** Понижение стандартной операции (ADD, XOR, AND, OR) в линейную комбинацию
    двух синтетических операторов: w1 * \Psi_1(x,y) + w2 * \Psi_2(x,y) + w_const *)
val lower_std_op_to_basis :
  alu_basis_pair -> std_alu_op -> int64 * int64 * int64

(** Генерация спецификации несепарабельного Mixed-Radix кодека *)
val gen_non_separable_isa_spec : Random.State.t -> isa_radix_spec

(** Упаковка инструкции в 64-битное слово без выделенных битовых полей *)
val encode_mixed_radix_insn : isa_radix_spec -> raw_instruction -> int64

(** Декодирование 64-битного слова обратно в структуру инструкции (для верификации и тестов) *)
val decode_mixed_radix_insn : isa_radix_spec -> int64 -> raw_instruction

(** Шаг автомата Мили для контекстно-зависимой грамматики потока байткода *)
val step_mealy_grammar_state :
  state:int64 -> insn_word:int64 -> data_invariant:int64 -> int64

(** Определение длины следующей инструкции в байтах (3, 5, 8) по состоянию автомата Мили *)
val next_insn_byte_width : state:int64 -> int

(** Эмиссия C++20 заголовка декодера и синтетических хендлеров для заданной спецификации *)
val emit_cpp20_decoder_header : isa_radix_spec -> alu_basis_pair -> string
