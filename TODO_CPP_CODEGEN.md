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
| **Stage 3** | Control Flow, супер-операторы, VMContext и модульные заголовки | ⏳ В планах | — |
| **Stage 4** | Stack-VM, Multi-VM шаблоны и финальная декомпозиция Jingoo | ⏳ В планах | — |

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

---

## 📋 План реализации: Stage 3 (Control Flow, Context & Dispatcher)

### 3.1. Миграция управляющих инструкций ветвления (`lib/native_vm/vm_control_handlers.ml`)
- [ ] Переписать генераторы основных переходов на типизированные `stmt list`:
  - `H_JMP` (прямой переход, поддержка наномитов через кросс-платформенные макросы `__debugbreak()` / `raise(SIGTRAP)`).
  - `H_JCC` (ветвление по условию флагов, branchless вычисление vIP).
  - `H_CMOV` (условное копирование регистров).
  - `H_SETCC` (установка байта регистра по флагу).
  - `H_CALL` / `H_RET` (эмуляция стековых фреймов вызова, пересчет указателей).
- [ ] Миграция супер-операторов (`emit_super_operators`):
  - `H_SUPER_ADD_JMP`
  - `H_SUPER_XOR_STORE`
  - `H_SUPER_AND_TEST`
  - `H_SUPER_MOV_LOAD`
- [ ] Сохранение строгой разметки меток диспетчера `    H_<NAME>:` для совместимости с `transform_domain_labels`.

### 3.2. Миграция структуры контекста VM (`lib/native_vm/vm_context_emitter.ml`)
- [ ] Перевод генерации `VMContext` на типизированные декларации C++:
  - Поля регистров: аффинная рандомизация смещений `affine_a * idx + affine_b`.
  - Защитные канарейки `canary_head`, `canary_tail` с динамическими валидаторами.
  - Аксессоры `get_reg`, `set_reg`, `get_vreg_lane`, `set_vreg`.
  - Методы обновления скользящего ключа `reanchor_running_key`.
  - Логика очистки и маскирования регистров (`reg_mask`).

### 3.3. Модуляризация монолитных шаблонов (`native_vm_templates.ml`)
- [ ] Вынесение статических рантайм-компонентов из гигантского литерала Jingoo (`threaded_header_template`, ~800 строк) в модульные `.hpp` заголовки под `runtime/include/vanguard/`:
  - `platform_compat.hpp` (макросы MSVC / Clang / GCC, интринсики `__builtin_expect`, `clock_gettime`).
  - `crypto_primitives.hpp` (FNV-1a, AES/Chacha PRF, White-box seed derivation).
  - `sanitization.hpp` (эфемеральное затирание памяти `SCRUB_WORD`, canary checks).
- [ ] Замена Jingoo-переменных на типизированную конфигурацию (`Runtime_config` / `Policy_flags`).

---

## 📋 План реализации: Stage 4 (Stack-VM, Multi-VM & Final Cleanup)

### 4.1. Миграция Stack-VM (`lib/stack_vm/stack_vm_templates.ml`)
- [ ] Замена строковых блоков стековой виртуальной машины на EDSL стейтменты.
- [ ] Типизация хендлеров манипуляции стеком (`PUSH`, `POP`, `DUP`, `SWAP`, `ROT`).
- [ ] Генерация типизированного диспетчера Stack-VM.

### 4.2. Миграция Multi-VM и адаптеров мостов (`lib/multi_vm/multi_vm_templates.ml`)
- [ ] Перевод интер-доменных трансляторов и роутеров между Native-VM и Stack-VM на типизированные структуры C++.
- [ ] Подключение валидатора C++ синтаксиса перед записью артефактов на диск.

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
