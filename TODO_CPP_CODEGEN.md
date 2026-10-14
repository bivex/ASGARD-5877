# Roadmap: Миграция кодогенерации C++20/C11 на Typed EDSL (ASGARD-5877)

## 📌 Обзор задачи
Устранение уязвимостей строковой склейки (`Printf.sprintf`, `Buffer.add_string`, сырые текстовые блоки) в пользу безопасного, типизированного AST-генератора C++20/C11 ([`lib/cpp_codegen/`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/)).

### Цели миграции:
1. **Строгая типизация (Type Safety):** Исключение синтаксических ошибок, опечаток в спецификаторах формата (`%` vs `%%`) и несоответствия типов C++ на этапе сборки OCaml.
2. **Гарантия отсутствия Undefined Behavior (UB):** Контроль знаковости типов, переполнений и выравнивания при кодогенерации.
3. **AST-мутации и обфускация:** Возможность применения трансформаций непосредственно к синтаксическому дереву C++ (перемешивание независимых стейтментов, замена выражений, внедрение барьеров памяти `std::atomic_signal_fence`).
4. **Кросс-платформенная поддержка C++20 / C11:** Единое дерево AST с возможностью генерации диалектов для LLVM/Clang, MSVC и GCC.

---

## 🚦 Статус этапов

| Этап | Описание | Статус | Коммит |
|---|---|:---:|:---:|
| **Stage 1** | Ядро типизированного EDSL (`Cpp_ast`, `Cpp_dsl`, `Cpp_printer`, `Cpp_ast_obf`) + 5 модулей Tier 4 Next-Gen | ✅ Завершен | `33c1a54` |
| **Stage 2** | E-graph равенства, ALU и Decoy хендлеры (`egraph_cpp_emitter.ml`, `vm_alu_handlers.ml`, `vm_mem_handlers.ml`) | ✅ Завершен | `62f984a` |
| **Stage 3** | Control Flow, супер-операторы, VMContext и модульные заголовки Vanguard | ✅ Завершен | `3.1, 3.2, 3.3` |
| **Stage 4** | Stack-VM хендлеры, Multi-VM контексты и pre-flight синтаксический валидатор | ✅ Завершен | `4.1, 4.2` |
| **Stage 5** | RD-JIT VM, Vector ISA, Tech-2603/2608, Vanguard 9292 Decoder, Stack-VM Superops & Trampoline | ✅ Завершен | `1c22026`, `e8aacea` |
| **Stage 6** | C11 ISA, GPU MBA, C Nanomites, Multi-VM Bridge, Whitebox & RNS-4 Garner CRT | ✅ Завершен | `e548e9c` .. `1d493ad` |

---

## ✅ Завершенные этапы

### Stage 1: Ядро типизированного EDSL и Tier 4 Next-Gen (`33c1a54`)
- [x] Создан базовый модуль AST [`lib/cpp_codegen/cpp_ast.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_ast.ml) (типы, литералы, бинарные/унарные операции, вызовы функций, конструкции `If`, `While`, `Goto`, `Label`, `Raw`).
- [x] Реализован комбинаторный DSL [`lib/cpp_codegen/cpp_dsl.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_dsl.ml) с хелперами регистров VM (`reg_dst`, `reg_src`, `set_reg`, `fetch_next`, `probe_start`, `probe_check`).
- [x] Реализован pretty-printer [`lib/cpp_codegen/cpp_printer.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_printer.ml) с автоматическим форматированием и отступами.
- [x] Создан рандомизированный AST-скремблер [`lib/cpp_codegen/cpp_ast_obf.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_ast_obf.ml).
- [x] Переведены 5 модулей Tier 4 Next-Gen:
  - Branchless VIP (`branchless_vip.ml`)
  - 2D Variable Entanglement (`two_dim_entanglement.ml`)
  - Oblivious Memory (`oblivious_mem.ml`)
  - VM-to-VM Bridge (`vm_bridge.ml`)
  - Self-Wiping Nano-JIT (`nano_jit.ml`)
- [x] Тесты: `test_tier4_nextgen.exe` — 100% PASS.

### Stage 2: E-graph, ALU & Decoy хендлеры (`62f984a`)
- [x] Расширение EDSL знаковыми и вещественными типами (`Int8`..`Int64`, `Float`, `Double`), литералами строк (`LitStr`) и операторами управления циклом (`Break`, `Continue`).
- [x] Полный переход [`lib/native_vm/egraph_cpp_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/egraph_cpp_emitter.ml) на генерацию AST `Cpp_ast.expr`.
- [x] Миграция всех 5 алгебраических полиномиальных расширений ALU (`pick_poly_add_ast`, `pick_poly_sub_ast`, `pick_poly_xor_ast`, `pick_poly_and_ast`, `pick_poly_or_ast`) в [`lib/native_vm/vm_alu_handlers.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_alu_handlers.ml).
- [x] Миграция хендлеров барьеров памяти (`H_FENCE`), пересылки векторных регистров (`H_MOV_VR`, `H_MOV_RV`) и 16 классов ложных decoy-хендлеров (`H_DECOY_0`..`H_DECOY_15`, `H_DECOY`) в [`lib/native_vm/vm_mem_handlers.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_mem_handlers.ml).
- [x] Тесты: `test_cpp_codegen.exe`, `E-graph Equality Expansion.*` (11/11), `Metamorphic ISA & Ring Codec` (6/6) — PASS.

### Stage 3.1: Control Flow & супер-операторы (`lib/native_vm/vm_control_handlers.ml`)
- [x] Расширение ядра EDSL: поддержка `ReinterpretCast of ctype * expr` в [`lib/cpp_codegen/`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/).
- [x] Полная миграция инструкций управления и переходов на типизированные `stmt list`:
  - `H_JMP` (прямой переход, поддержка наномитов через макросы `__debugbreak()` / `raise(SIGTRAP)`).
  - `H_JCC` (ветвление по условию флагов, branchless вычисление vIP).
  - `H_CMOV` (условное копирование регистров).
  - `H_SETCC` (установка байта регистра по флагу).
  - `H_CALL` / `H_RET` / `H_EXIT` (эмуляция стековых фреймов вызова, пересчет указателей).
  - `H_IJMP_R` / `H_ICALL_R` (косвенные переходы и нативные FFI вызовы).
  - `H_BRIDGE_TO_FLOW` / `H_BRIDGE_TO_MATH` (доменные мосты Multi-VM).
- [x] Миграция супер-операторов (`emit_super_operators`):
  - `H_FUSED_MOV_ADD_RRI`
  - `H_FUSED_ADD_IMUL_RRI`
  - `H_FUSED_ADD_XOR_RRI`
  - `H_FUSED_SUB_XOR_RRI`
  - `H_FUSED_XOR_ADD_RRI`
  - `H_FUSED_CMP_CMOV`
- [x] Сохранение строгой разметки меток диспетчера `    H_<NAME>:` для совместимости с `transform_domain_labels`.
- [x] Тесты: Step 6 и Step 7 в `test_cpp_codegen.ml` — 100% PASS.

### Stage 3.2: VMContext & Структурные Декларации (`lib/native_vm/vm_context_emitter.ml`)
- [x] Расширение ядра EDSL: добавлены `StructDef`, `struct_member` (`MemberField`, `MemberMethod`, `MemberStaticConstexpr`, `MemberRaw`), `EnumDecl`, `RawTop`, `CommentTop` и оператор присваивания `( *= )`.
- [x] Полная миграция `VMContext` на типизированные декларации C++:
  - Поля регистров: аффинная рандомизация смещений `(REG_AFFINE_A * idx + REG_AFFINE_B) & 31` через `reg_phys_idx`.
  - Защитные канарейки `canary_head`, `canary_tail` и массив динамических межфреймовых канареек `mid_canaries` с валидатором `verify_canaries()`.
  - Аксессоры регистров `get_reg`, `set_reg`, векторные `get_vreg_lane`, `set_vreg`, а также именованные регистры ABI.
  - Методы скользящего крипто-ключа `advance_running_key`, `reanchor_running_key`, `apply_poly_merge_update`.
  - Динамическое маскирование: `evolve_mask`, `evolve_slot_mask`, виртуальный стек Speck-64 `scramble_stack_idx`, `push`, `pop`.
  - Свободные типизированные функции C++: `eval_condition`, `compute_sub_flags`, `compute_add_flags`, `key64_for_offset`, `compute_handlers_hash`.
- [x] Тесты: Step 8 в `test_cpp_codegen.ml` — 100% PASS (эмитировано 63040 байт валидного C++20).

### Stage 3.3: Модуляризация монолитных шаблонов (`native_vm_templates.ml`)
- [x] Вынесение статических рантайм-компонентов из гигантского литерала Jingoo (`threaded_header_template`) в модульные `.hpp` заголовки под `runtime/include/vanguard/`:
  - [`platform_compat.hpp`](file:///Volumes/External/Code/ASGARD-5877/runtime/include/vanguard/platform_compat.hpp) (макросы MSVC / Clang / GCC, интринсики `__builtin_expect`, `clock_gettime`).
  - [`crypto_primitives.hpp`](file:///Volumes/External/Code/ASGARD-5877/runtime/include/vanguard/crypto_primitives.hpp) (FNV-1a, Mach-O Dyld Exports Trie Resolver, Dynamic Symbol Decryption).
  - [`sanitization.hpp`](file:///Volumes/External/Code/ASGARD-5877/runtime/include/vanguard/sanitization.hpp) (эфемеральное затирание памяти `SCRUB_WORD`, canary checks).
- [x] Двойная стратегия поставки: директива `#if __has_include("vanguard/platform_compat.hpp")` для модульной сборки + инлайнинг для автономных single-header артефактов без нарушения границ гексагональной архитектуры.
- [x] Замена loose-флагов Jingoo на строго типизированный модуль `Runtime_policy` в [`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml).
- [x] Тесты: Step 9 в `test_cpp_codegen.ml` — 100% PASS (298323 байт эмитировано).

### Stage 4.1: Миграция Stack-VM хендлеров (`lib/stack_vm/stack_handlers_emitter.ml`)
- [x] Создан типизированный генератор Stack-VM хендлеров манипуляции стеком [`lib/stack_vm/stack_handlers_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_handlers_emitter.ml).
- [x] Типизированные AST хендлеры:
  - `h_push_imm`, `h_push_imm32`
  - `h_push_reg`, `h_pop_reg`
  - `h_dup`, `h_dup2`, `h_rot`, `h_swap`
- [x] Полная интеграция с макросами VSP-вайтнинга (`VSP_ENCODE(slot, val)`).
- [x] Замена хардкодных строк в [`lib/stack_vm/stack_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_vm_templates.ml) и подключение в [`lib/stack_vm/stack_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_runtime.ml).
- [x] Тесты: Step 10 в `test_cpp_codegen.ml` (5034 байт) + все 38 тестов `Stack-VM Execution Engine` — 100% PASS.

### Stage 4.2: Multi-VM структуры, мосты и валидация (`lib/multi_vm/multi_vm_context_emitter.ml`, `lib/cpp_codegen/cpp_validator.ml`)
- [x] Расширение ядра EDSL: поддержка `UnionDecl` и `UnionDef` в `Cpp_ast`, `Cpp_dsl`, `Cpp_printer`, `Cpp_ast_obf`.
- [x] Создан типизированный генератор контекстов Multi-VM [`lib/multi_vm/multi_vm_context_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/multi_vm_context_emitter.ml):
  - `MathVMContext` (GPRs, VIP, RNS-слоты, trace digest, метод `init`).
  - `FlowVMContext` (виртуальный стек vstack, vsp, vip, state_var, trace digest, метод `init`).
  - `SharedVMContext` (`union` из `MathVMContext`, `FlowVMContext`, `raw[1024]`).
  - Междоменные аффинные мосты `bridge_switch_to_flow`, `bridge_switch_to_math`.
- [x] Замена хардкодного блока `asgard_multi_vm` в [`lib/multi_vm/multi_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/multi_vm_templates.ml) на типизированную генерацию.
- [x] Реализован pre-flight структурный и компиляторный валидатор [`lib/cpp_codegen/cpp_validator.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/cpp_codegen/cpp_validator.ml):
  - Посимвольный лексический трекер строк и колонок.
  - Проверка баланса скобок `()`, `[]`, `{}` со стеком позиций открытия.
  - Пропуск строковых/символьных литералов, raw strings, экранирований, однострочных и блочных комментариев.
  - Проверка отсутствия неразрешенных тегов шаблонизатора (`{{`, `}}`, `{%`, `%}`).
  - Интеграция с компилятором `clang++ -fsyntax-only` для строгой проверки перед записью на диск.
- [x] Тесты: Step 11 и Step 12 в `test_cpp_codegen.ml` + 8/8 тестов `Multi-VM & Direct Zero-Bridge` (включая E2E сборку Clang и запуск) — 100% PASS.

### Stage 5.1: Vanguard 9292, Stack-VM Superops, RD-JIT & Chunks (`1c22026`)
- [x] Расширение ядра EDSL: добавлена конструкция `MemberConstructor` (`Cpp_ast`, `Cpp_dsl`, `Cpp_printer`, `Cpp_ast_obf`) для типизированного описания C++ конструкторов с explicit, inline, noexcept и списками инициализации полей (`init_list`).
- [x] Полная миграция Vanguard-9292 Decoder ([`lib/vanguard_9292/vanguard_decoder.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vanguard_9292/vanguard_decoder.ml)):
  - Структура `RollingKey` переведена на `Cpp_ast.StructDef` с typed конструктором и методами `next()`, `next64()`.
  - Класс `VanguardDecoder` переведен на типизированный AST с `decode_and_execute`, битовыми масками, заполнением `DecodedInstruction` и switch-инструкциями / ловушками junk-кодов.
- [x] Миграция Stack-VM супер-операторов ([`lib/stack_vm/stack_handlers_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_handlers_emitter.ml)):
  - Хендлеры `h_cmp`, `h_test`, `h_add_imm`, `h_sub_imm`, `h_add_ii`, `h_sub_ii` переведены на типизированные `FuncDecl`.
  - Замена строковых определений в [`lib/stack_vm/stack_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_vm_templates.ml) на `{{ stack_superop_handlers }}`.
- [x] Миграция структур Trampoline Chunk ([`lib/adapters/protect_adapters/c_trampoline_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml)):
  - Декларация `AsgardBytecodeChunk` переведена на типизированный `Cpp_ast.StructDecl`.
- [x] Тесты: Steps 13 и 14 в `test_cpp_codegen.ml` + 38/38 тестов `Stack-VM Execution Engine` + `Vanguard Emulator E2E` (Clang++ E2E) — 100% PASS.

### Stage 5.2: Завершение миграции всех хендлеров Stack-VM (`e8aacea`)
- [x] Перевод оставшихся 10 хендлеров Stack-VM в [`lib/stack_vm/stack_handlers_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_handlers_emitter.ml):
  - Control & Lifecycle: `h_jmp_rel`, `h_jcc_rel` (с поддержкой `layout_jcc_target_first`), `h_key_adjust`, `h_exit`.
  - Conditionals & Symbols: `h_resolve_sym` (через strict C++20 `reinterpret_cast<uint64_t>`), `h_setcc`, `h_cmov` (с поддержкой `layout_cmov_slot_first`).
  - Register Immediates & Feedback: `h_set_reg_imm`, `h_add_reg_imm`, `h_key_feedback`.
- [x] Замена сырых строк в [`lib/stack_vm/stack_vm_templates.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_vm_templates.ml) на `{{ stack_control_handlers }}`, `{{ stack_cond_handlers }}`, `{{ stack_reg_imm_handlers }}`.
- [x] Тесты: Step 15 в `test_cpp_codegen.ml` + 38/38 тестов `Stack-VM Execution Engine` — 100% PASS.

### Stage 5.3: Vector ISA C++ Emulator и Tech-2603 NonLinearVPCDispatcher
- [x] Расширение ядра EDSL:
  - Добавлены атрибуты `InlineFn`, `Nodiscard`.
  - Добавлены элементы структуры `MemberMethodDecl`, `MemberVisibility (Public | Private | Protected)`, `MemberStaticAssert`.
  - Добавлены декларации классов и шаблонов `ClassDef`, `TemplateStructDef`, `TemplateClassDef`.
- [x] Миграция Vector ISA C++ Emulator:
  - [`lib/adapters/cpp_emitter/cpp_header_emitters.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_header_emitters.ml): классы `VRegFile`, `EmulatorState`, `Decoder` и `InstructionExecutor` переведены на типизированный AST.
  - [`lib/adapters/cpp_emitter/cpp_emitter_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_emitter_adapter.ml): генератор бинарных и унарных операций `generate_c_op_expr`, диспетчер `InstructionExecutor::execute`, хендлеры инструкций `exec_<mnemonic>` и класс `VectorEmulator` переведены на типизированные `FuncDecl` и `ClassDef`.
- [x] Миграция Tech-2603 NonLinearVPCDispatcher ([`lib/tech_2603/tech_2603_engine.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/tech_2603/tech_2603_engine.ml)):
  - Структура `NonLinearVPCDispatcher` переведена на `TemplateStructDef` с проверкой `static_assert`, методами `logical_to_physical`, `physical_to_logical`, `next_physical`.
- [x] Тесты: Steps 16 и 17 в `test_cpp_codegen.ml`, `C++ Emulator E2E` (Clang++ E2E компиляция и запуск) и `Tech-2603 Anti-VPC Tracking` (7/7) — 100% PASS.

### Stage 5.4: C11 ISA, GPU MBA, C Nanomites, Multi-VM Bridge, Whitebox, RNS-4, Tech-2603/2608, Trampoline & E2E Mains (`e548e9c` .. `HEAD`)
- [x] Расширение ядра EDSL:
  - Добавлены `GlobalVar` (с поддержкой 1D/2D массивов, `static`, `constexpr`, `const`, `volatile`), `InitList` (с авто-форматированием вложенных списков и скаляров), `LitU8` (байтовые литералы), `CCast` (C-style cast `(T)(e)` без `static_cast` syntax error в C11).
  - Добавлены `let_u32`, `const_u32`, `namespace_def`, атрибут `Constructor` (`__attribute__((constructor))`).
  - Добавлено экранирование спецсимволов C-строк (`\n`, `\t`, `\"`, `\\`) в `LitStr` для предотвращения многострочных разрывов строковых литералов.
  - Исправлен рендеринг неинициализированных локальных переменных `DeclVar` (`T name;` вместо `T name{};` для 100% совместимости со стандартом C11).
- [x] Миграция C11 Vector ISA Emulator ([`lib/adapters/c11_emitter/c11_emitter_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/c11_emitter/c11_emitter_adapter.ml)):
  - Структуры `CSRState`, `EmulatorState`, `DecodedInst`, прототипы `emit_c11_prototypes` переведены на типизированные `StructDecl` и `FuncProto`.
- [x] Миграция Vector ISA C++ Emulator Main & Constants ([`lib/adapters/cpp_emitter/cpp_header_emitters.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_header_emitters.ml), [`lib/adapters/cpp_emitter/cpp_emitter_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/cpp_emitter/cpp_emitter_adapter.ml)):
  - Константы `VLEN`, `VLEN_BYTES`, `NUM_VREGS`, `NUM_XREGS` переведены на типизированные `ConstexprGlobal`.
  - Функции `setup_test_state`, `run_self_tests`, `main` в `emit_main_cpp` полностью переведены на типизированные `FuncDecl`.
- [x] Миграция RD-JIT VM массивов, дескрипторов и точки входа ([`lib/rd_jit_vm/rd_jit_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/rd_jit_emitter.ml)):
  - Генерация массивов `JITInstr` и `JITBlock` переведена на typed `global_var` и `init_list`.
  - Точка входа `main` автономного раннера RD-JIT переведена на типизированный AST `emit_rd_jit_main_def`.
  - Модули RNS-4 (`RNS_M1`..`M4`), CRT-декодер и метод умножения `RNS_Register::mul` в [`lib/rd_jit_vm/rd_jit_buffer.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/rd_jit_buffer.ml) переведены на typed EDSL.
  - Таблица внешних символов `g_rd_jit_external_symbols` в [`lib/rd_jit_vm/rd_jit_synth.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/rd_jit_vm/rd_jit_synth.ml) переведена на typed `global_var`.
- [x] Миграция Trampoline Chunk & Assembler ([`lib/adapters/protect_adapters/c_trampoline_adapter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/adapters/protect_adapters/c_trampoline_adapter.ml)):
  - Массивы байткода `chunks[]`, глобальный буфер сборки `embedded_bytecode[]`, переменная `assembled`, функция проверки канареек и расшифровки `embedded_bytecode_ensure_assembled()`, конструктор `auto_init()` и тело трамплина `build_trampoline_body` переведены на typed `global_var`, `func_decl` и типизированные стейтменты.
- [x] Миграция GPU MBA Substitution Matrix ([`lib/gpu_synth/gpu_matrix.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/gpu_synth/gpu_matrix.ml)):
  - Матрицы подстановок `MBA_FORWARD_MATRIX` и `MBA_INVERSE_MATRIX` переведены на типизированный AST `emit_cpp_constants_ast`.
- [x] Миграция C Nanomite Preamble ([`lib/c_macro_obf/c_nanomites.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/c_macro_obf/c_nanomites.ml)):
  - Функции ветвления `asgbranch_t_*`, `asgbranch_f_*` и конструктор авто-инициализации `_asg_nanomite_init` переведены на typed `FuncDecl`.
- [x] Миграция Multi-VM Direct Zero-Bridge ([`lib/multi_vm/bridge.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/multi_vm/bridge.ml)):
  - Аффинные матрицы $GL_{16}(\mathbb{Z}/2^{64}\mathbb{Z})$ `BRIDGE_FWD_MAT`, `BRIDGE_INV_MAT`, `ASGARD_INITIAL_DIGEST` и функции `in_place_morph_*` переведены на typed AST.
- [x] Миграция Whitebox Seed Derivation ([`lib/native_vm/vm_runtime_emitter.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/native_vm/vm_runtime_emitter.ml)):
  - Таблицы `T0_0`..`T1_3`, функции `rotl32`, `derive_seed` внутри `namespace asgard_whitebox` и `asgard_wbox_derive_seed` переведены на typed EDSL.
- [x] Миграция Residue Number System (RNS-4) Garner CRT ([`lib/vm_ir/rns.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/vm_ir/rns.ml)):
  - Заголовок `asgard_rns` с константами модулей, инверсий, структурой `RNSVal` и функциями `encode`, `add`, `sub`, `mul`, `decode` полностью переведен на typed EDSL (`emit_cpp_rns_ast`).
- [x] Миграция заголовков Tech-2603 и Tech-2608 ([`lib/tech_2603/tech_2603_engine.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/tech_2603/tech_2603_engine.ml), [`lib/tech_2608/tech_2608_engine.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/tech_2608/tech_2608_engine.ml)):
  - `ChaffMemoryPool` переведен на `template_struct_def`, а генераторы заголовков `emit_tech_2603_cpp_header` и `emit_tech_2608_cpp_header` переведены на `render_top_decls`.
- [x] Тесты: Steps 1..27 в `test_cpp_codegen.ml` (все 27 шагов) + `C++ Emulator E2E` + `C11 Emulator E2E` + `Multi-VM & Direct Zero-Bridge` (8/8) + `Register-Driven JIT VM & RNS` (5/5) + `C Macro Obfuscation` (12/12) + `Tech-2603` (7/7) + `Tech-2608` (4/4) — 100% PASS.

---

## ⚠️ Архитектурные инварианты и правила безопасности

1. **Сохранение разметки лейблов диспетчера:**
   Любой эмитируемый AST-хендлер обязан форматироваться с префиксом `    H_<OPCODE>:` (4 пробела), чтобы функция `Vm_handlers_emitter.transform_domain_labels` могла прозрачно добавлять суффиксы доменов (`_D1`, `_D2`) для multi-domain диспетчеров.

2. **Безопасность типов в C++:**
   - Все целочисленные регистровые операции должны использовать суффиксы `ULL` (`LitU64`) во избежание знакового переполнения UB в `clang -O3`.
   - Для знаковых операций явно указывать тип приведения `static_cast<int64_t>`.

3. **Локальный запуск тестов:**
   - **ЗАПРЕЩЕНО** запускать `dune runtest` целиком.
   - Запускать строго таргетные тестовые бинарники:
     ```bash
     eval $(opam env) && ./_build/default/test/test_cpp_codegen.exe
     eval $(opam env) && ./_build/default/test/test_tier4_nextgen.exe
     eval $(opam env) && ./_build/default/test/run_tests.exe test "Metamorphic ISA.*"
     eval $(opam env) && ./_build/default/test/run_tests.exe test "E-graph Equality Expansion.*"
     ```
