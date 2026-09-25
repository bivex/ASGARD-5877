# ASGARD-5877: Audit TODO — недоделанные фичи и тихие деградации

> **Источник**: аудит движка 2026-09-23 (HEAD `898a4ee`, `dune runtest` зелёный).
> Не путать с `CPP_TODO.md` — там все позиции помечены DONE; перечисленное ниже
> в этом роадмапе **не трекается**. Порядок = приоритет.
> **Текущий статус (2026-09-25)**: базовые P0–P4 ограничения устранены; реестр содержит 245 тестов в 34 suites. Ниже зафиксирован расширенный роадмап P5 по доведению lifters и VM-IR до промышленного покрытия.

---

## P0 — корректность движка (ломается на обычном `-O2` коде)

### 1. Нет 16-битного доступа к памяти: `ldrh`/`strh` читают/пишут 1 байт вместо 2 — ВЫПОЛНЕНО 2026-09-23

- Сделано по плану: опкоды `OP_LOAD_16`/`OP_STORE_16` в `vm_transform.ml` (аллокация
  слотов сдвинулась — OCaml-эмиттер и C++ dispatch-таблица синхронны, golden-векторы
  anti-pushan не зависят от опкодов и остались зелёными), C++ хендлеры `H_LOAD_16`/
  `H_STORE_16` в `vm_mem_handlers.ml` (`uint16_t`, zero-extend — точно семантика
  `ldrh wX`), ветки `B16` в матчах ширины load/store в `vm_emitter.ml`.
- Тесты: юнит `ARM64 Lift Halfword Memory (strh/ldrh)` в `test_arm64_lifter.ml`
  (пинит ровно 1 B16-store и 1 B16-load в IR + результат эвалюатора 0xBFAD); нативный
  `native_b16_word_memory` (word-слот через `[rsp-16]`, оба байта: 0xCACAFE; старый
  byte-only баг давал 0xFE); полный E2E `e2e_uint16_pipeline` (uint16-арифметика внутри
  `ASGARD_BEGIN_VIRTUALIZE` через весь пайплайн, protected-app exit 0) и
  `e2e_uint16_clang_o2_o3` (тот же регион под clang -O2/-O3, lift + `asgard_vm_call`,
  результат 0xF6AA; старый баг давал 0x5A) — вынесены в новый файл
  `test/test_native_semantics.ml` (сюда же переехали div/idiv и B32-тесты пунктов 5/6,
  чтобы `test_native_vm.ml` не стал god-module).
- **Найдено попутно (серьёзное, тот же класс что п.9)**: arm64-лифтер молча неверно
  поднимал 3-операндные ALU со сдвинутым операндом — `add w8, w8, w0, lsr #16`
  (канон clang для uint16-арифметики!) матчился catch-all'ом как `+0`, а старые
  явные паттерны `orr/eor` c `lsl/lsr` кодировали src1≠dst, который эмиттер
  отбрасывает. Фикс в `arm64_alu.ml`: общий `emit_shifted_alu` — сдвиг материализуется
  в `vtmp1`, затем op через `emit_3addr_alu` с сохранением конвенции src1=dst;
  add/sub/orr/eor теперь через один хелпер. Без него E2E-тест не проходил.
- Остаточные ограничения: `ldrsh` (знак-расширяющая загрузка) по-прежнему
  zero-extend'ит — это территория пункта 2.

### 2. Нет знакового расширения при загрузках: `ldrsb`/`ldrsh`/`movsx`/`movsxd` — ВЫПОЛНЕНО 2026-09-24

- Сделано по плану:
  - Опкоды `OP_LOAD_S8` / `OP_LOAD_S16` / `OP_LOAD_S32` в `vm_transform.ml`, нативные C++ хендлеры
    `H_LOAD_S8` / `H_LOAD_S16` / `H_LOAD_S32` в `vm_mem_handlers.ml` (`(uint64_t)(int64_t)(*reinterpret_cast<const int8_t*/int16_t*/int32_t*>)`),
    ветки в `vm_emitter.ml` с проверкой `m.is_signed`.
  - В `Ir.mem_ref` добавлен флаг `is_signed : bool`, поддержан в `Vm_eval.read_mem` со знаковым
    расширением до int64.
  - ARM64: в `arm64_parser.ml` и `arm64_mem.ml` разведены `ldrsb`/`ldrsh`/`ldrsw`/`ldursb`/`ldursh`/`ldursw`
    (`is_signed = true`, ширина B8/B16/B32) от `ldrb`/`ldrh`/`ldur`/`ldurb` (`is_signed = false`).
  - x86: в `lifter.ml` разведены `movsx`/`movsxd` (и псевдонимы `movsxb`/`movsxw`/`movsbq`/`movswq`/`movslq`)
    от `movzx`. Для памяти выставляется `is_signed = true`, для регистров материализуется точное знаковое
    расширение через пару `Shl`/`Sar` на B64 (с последующим `subreg_write` занулением верхней половины для B32 dst).
    Для `movzx` с регистровым источником добавлено маскирование через `And` (`0xFF`/`0xFFFF`).
  - **Найдено попутно (серьёзное)**: парсер регистров `Register.of_string` при проверке префикса `d` для FP-регистров
    `d0`..`d31` безусловно падал с ошибкой при нечисловом суффиксе, блокируя x86-регистры `dx`, `di`, `dil`, `dl`.
    Исправлено: нечисловые `d`- и `s`-регистры корректно проваливаются в общий `match s with`.
- Тесты: 6 новых тестов (200 всего в 32 сьютах):
  - ARM64: юнит `ARM64 Lift Signed Memory (ldrsb/ldrsh/ldrsw)` в `test_arm64_lifter.ml` (-5, -300, -100000 -> -100305).
  - x86: 3 юнита в `test_x86_lifter.ml` (`lift_and_eval_movsx_mem`, `lift_and_eval_movsx_reg`, `lift_and_eval_movzx_reg`).
  - Native & E2E: `native_signed_loads` (выполнение стековых знаковых загрузок в threaded VM) и
    `e2e_signed_loads_clang_o2_o3` (C-функция с `volatile signed char/short/int`, компиляция clang -O2/-O3,
    проверка наличия signed mem ops в IR и результат -100305 через `asgard_vm_call`) в `test_native_semantics.ml`.

---

## P1 — защита молча выключается (security-critical)

### 3. `gpu_synth` при сбое тихо возвращает небезопасные данные — ВЫПОЛНЕНО 2026-09-24

- **Где**: `lib/gpu_synth/gpu_synth.ml` и `lib/gpu_synth/gpu_synth.mli`.
- **Сделано**:
  - Убран тихий fallback, возвращавший открытый байткод (`List.map (fun _ -> bytecode) keys`),
    фейковую константу `0x9E3779B97F4A7C15L` и фейковый SAC `50.0`.
  - Введён явный тип ошибки `type gpu_error = Gpu_unavailable | Gpu_execution_failed of string` и
    функция форматирования `string_of_error : gpu_error -> string`.
  - Все функции (`synthesize_mba_gpu`, `batch_encrypt_gpu`, `verify_sac_gpu`) теперь возвращают
    `(..., gpu_error) result`.
  - Исключения из C stubs (`caml_failwith` при неуспешном статусе Metal/GPU) и `Sys_error` перехватываются
    и конвертируются в `Error (Gpu_execution_failed msg)`, а отсутствие GPU — в `Error Gpu_unavailable`.
- **Тесты**:
  - `test/test_gpu_synth.ml` обновлён: все тесты матчат `Ok` и громко падают при `Error`.
  - Добавлен тест форматирования ошибок `test_gpu_error_formatting`.
  - Все 205 тестов в сьютах проходят успешно.

### 4. SMC деградирует в no-op без диагностики — ВЫПОЛНЕНО 2026-09-24

- **Где**: `lib/native_vm/runtime_smc.ml`, `lib/native_vm/runtime_dual_map.ml`, `lib/native_vm/vm_runtime_emitter.ml`, `lib/native_vm/protection_types.ml(i)`, `lib/native_vm/protection_presets.ml`, `lib/native_vm/protection_json.ml`.
- **Сделано**:
  - Устранена молчаливая деградация без диагностики:
    - Введён `enum SmcStatus : uint32_t { SMC_STATUS_NOT_EXECUTED = 0, SMC_STATUS_ACTIVE = 1, SMC_STATUS_DEGRADED = 2, SMC_STATUS_FAILED = 3 };`
    - Добавлены функции диагностики `get_smc_status()`, `get_smc_status_string()`, `is_smc_active()`, `is_smc_degraded()`.
    - Добавлен метод проверки поддержки платформы `DualMappedBuffer::is_supported()`.
  - Реализован строгий режим SMC (`ASGARD_SMC_STRICT`):
    - Compile-time: если платформа не поддерживает dual-mapping (`!defined(__APPLE__) && (!defined(__linux__) || !defined(MFD_CLOEXEC))`) при активном strict SMC — генерируется `#error "ASGARD Security Violation: Strict SMC requested (max_security profile), but target platform does not support dual-mapping W^X memory aliasing!"`.
    - Runtime: при сбое аллокации dual-mapping в strict-режиме статус переводится в `SMC_STATUS_FAILED`, выводится диагностическая ошибка, и возвращается штраф `0xDEAD53C0CAFE0001ULL`, ломающий регистровый контекст VM (`ctx.reg_mask`) и предотвращающий скрытное продолжение выполнения.
    - В нестрогом режиме статус переводится в `SMC_STATUS_DEGRADED` с логированием при диагностическом режиме вместо молчаливого no-op.
  - Поддержан флаг `smc_strict : bool` в `anti_tamper_config` (активен по умолчанию в пресете `max_security`, поддержан в JSON serialization/roundtrip, при генерации VM header включает `#define ASGARD_SMC_STRICT 1`).
- **Тесты (2 новых теста, 207 всего в 33 сьютах)**:
  - `test_smc_diagnostics_and_modes` в `test_anti_tamper_smc.ml`: проверка начального состояния `NOT_EXECUTED`, перехода в `SMC_STATUS_ACTIVE` / `"FULL_SMC"`, работы предикатов `is_smc_active()`.
  - `test_smc_strict_mode_and_max_security` в `test_anti_tamper_smc.ml`: проверка флага `smc_strict` в `max_security`, генерации `#define ASGARD_SMC_STRICT 1` в заголовке, компиляции и выполнения под clang++ с активным `ASGARD_SMC_STRICT`.
  - JSON roundtrip в `test_protection_config.ml`: проверка сохранения и загрузки `anti_tamper.smc_strict`.

---

## P2 — покрытие лифтеров

### 5. x86-64 лифтер: нет `div`/`idiv`/`mul`, ноль SIMD — ВЫПОЛНЕНО 2026-09-24

- Сделано в `lib/x86_lifter/lifter.ml`:
  - `div`/`idiv` на B8/B16/B32/B64 (регистр/память): частное и остаток пишутся
    в архитектурные sub-регистры с корректной B8-разбивкой `AH:AL` и fault на ноль.
  - `cdq`/`cltd`/`cqo`/`cqto`/`cwd` и `cdqe`/`cltq` выдают корректное знаковое расширение.
  - 1-операндные `mul`/`imul` поддерживают B8/B16/B32/B64, включая 64-bit high half.
  - SSE/AVX mov и packed-операции разделены на integer lanes и IEEE F32/F64 lanes.
- Division-by-zero и signed-overflow приводят к VM fault; native runtime выставляет
  `ctx.trapped` и завершает исполнение с ошибкой.
- Тесты: B8/B16/B32/B64 arithmetic/division, zero-divisor fault, IEEE SSE/AVX,
  B8/B16 merge и native C++ E2E.

### 6. Частичная запись в 32-битные подрегистры не моделируется — ВЫПОЛНЕНО 2026-09-24

- Сделано: общий `lib/vm_ir/subreg_write.ml` нормализует B8/B16 merge и B32
  zero-extension для x86 GPR и ARM `w14`–`w28`/`w30` aliases.
- B8/B16 writes сохраняют старшие биты backing register; B32 writes добавляют
  `shl 32 / shr 32` без изменения flags.
- Подключён в x86/ARM lifter до terminator patching; native VM и evaluator
  используют одну нормализованную семантику.
- Тесты покрывают evaluator, native B32/idiv, native B8/B16 merge и ARM `w18`.

### 9. (новый, из разбора п.5) Эмиттер молча теряет src1 ≠ dst у RR-ALU — ВЫПОЛНЕНО 2026-09-24

- **Где было**: `lib/native_vm/vm_emitter.ml` и `lib/rd_jit_vm/rd_jit_emitter.ml` — все ветки вида
  `Alu { op; dst = d; src1 = Ir.Reg _; src2 = Ir.Reg s }` кодировали только `(d, s)` и игнорировали `src1`.
  Нативные хендлеры вычисляют `dst = dst OP src`, что требовало `src1 = dst`.
- **Сделано**:
  - Новый общий пасс нормализации `canonicalize_3addr_alu` в `lib/native_vm/vm_transform.ml`:
    - При `src1 = dst`: без изменений (2-адресный канон).
    - При `src1 ≠ dst`:
      - Для `src2 = Imm imm`: `Mov dst, src1` + `Alu dst, dst, imm`.
      - Для `src2 = Reg s2` при `s2 ≠ dst`: `Mov dst, src1` + `Alu dst, dst, s2` (без разрушения s2).
      - Для `src2 = Reg s2` при `s2 == dst` (hazard clobber case):
        - Коммутативные операции (`Add`, `Imul`, `Mul`, `Xor`, `And`, `Or`): обмен операндами `Alu dst, dst, src1` — 0 лишних инструкций, точное сохранение флагов.
        - Некоммутативные операции (`Sub`, `Div`, `Idiv`, сдвиги): сохранение старого `dst` в свободный темп (`vtmp0`/`vtmp1`/`vtmp2`), загрузка `dst := src1`, вычисление `Alu dst, dst, scratch`.
      - Для `Unary`: аналогично `Mov dst, src` + `Unary dst, dst`.
  - Подключён в `vm_emitter.ml` (до `fuse_block_instructions` и после MBA; благодаря этому `Mov + Alu` последовательности сворачиваются в fused super-ops `Fused_Mov_Add`) и в `rd_jit_emitter.ml`.
  - В `vm_emitter.ml` и `rd_jit_emitter.ml` добавлена строгая диагностика `assert_src1_eq_dst`: ненормализованная 3-адресная операция немедленно падает громким compile-time исключением вместо тихой порчи байткода.
  - Поддержан опкод `Ir.Mul` (наряду с `Ir.Imul`) в `vm_emitter.ml`, `rd_jit_emitter.ml` и `arm64_common.ml`.
  - В `arm64_alu.ml` исправлен баг `bic/bics/orn/eon`: операнд `src2` теперь явно копируется в `vtmp1` перед битовой инверсией `Not`.
- **Тесты (4 новых теста, 204 всего в 33 сьютах)**:
  - Unit `canonicalize_3addr_alu_unit` в `test_native_semantics.ml`: проверка всех веток разложения (distinct registers, commutative hazard swap, non-commutative scratch preservation, immediate).
  - Native `native_3addr_alu` в `test_native_semantics.ml`: прямое нативное исполнение 3-адресного IR (add, sub-hazard, imul, idiv) в `execute_threaded`.
  - Lifter unit `ARM64 Lift 3-Address ALU (madd/msub/sdiv/bic)` в `test_arm64_lifter.ml`: reference VM evaluation.
  - Native E2E `native_arm64_3addr_madd_msub_sdiv_bic` в `test_native_semantics.ml`: полный пайплайн от ARM64 assembly (madd, msub, sdiv, bic) до нативного исполнения в threaded VM (результат 310).

---

## P3 — новая фича (следующий кандидат stage-2)

### 7. Anti-VMPredator address-bound bytecode — ВЫПОЛНЕНО 2026-09-24

- **Контекст**: `docs/VM_PROTECTOR.md:187` фиксировал границу стандартных rolling keys —
  последовательный статический проход / дамп может восстановить keystream при отсутствии привязки
  к живому адресному пространству процесса.
- **Дизайн и реализация**:
  - Ключ дешифровки и keystream рантайма привязаны к реальным in-memory адресам хендлеров VM:
    - `lib/native_vm/protection_types.ml(i)`, `protection_config.mli`, `protection_presets.ml`, `protection_json.ml`:
      добавлено поле `address_bound : bool` в `anti_pushan_config` (активно в `max_security`, поддержано в JSON roundtrip).
    - `lib/native_vm/vm_context_emitter.ml`: функция `compute_handlers_hash(all_dispatch_domains, num_domains)`
      вычисляет криптографический хеш реальных указателей на хендлеры всех доменов диспетчеризации.
    - `anchor_key(seed, off, addr_hash)` и `reanchor_running_key(off, addr_hash)`:
      подмешивают хеш адресов в начальный ключ блока, обеспечивая нелинейную диффузию адресов хендлеров во все слова блока.
    - `lib/native_vm/vm_control_handlers.ml`: все терминаторы и ветвления (`H_JMP`, `H_JCC`, `H_CALL`)
      пере-анкорят цепочку с передачей `g_handlers_hash`.
    - `lib/native_vm/vm_runtime_emitter.ml`: генерирует метаданные блоков `g_block_offsets` и `g_block_lengths`,
      на этапе runtime-init в эфемерном буфере синтезирует `bound_bc[idx] = bytecode[idx] ^ k_pos ^ rk(g_handlers_hash)`,
      выполняет чтение из `bound_bc` и гарантирует его полное обнуление `SCRUB_WORD` при выходе из VM.
    - `lib/native_vm/vm_emitter.ml`: при включённом `address_bound` байткод в `.rodata` маскируется только `k_pos`,
      перенося наложение dynamic rolling key на этап runtime init с привязкой к адресам; вычисляются `block_spans` для рантайма.
    - Попутно исправлен дефект в `lib/native_vm/vm_mem_handlers.ml` и `vm_runtime_emitter.ml`:
      небезопасные SIMD-хендлеры NEON/SSE теперь строго ограждены `#if defined(ASGARD_VECTOR_ISA)`.
- **Тесты (2 новых теста, 209 всего в 33 сьютах)**:
  - `anti_vmpredator_address_bound_execution` в `test_anti_pushan.ml`: E2E компиляция и выполнение
    программы с циклами и ветвлениями под `address_bound = true`, верификация макроса и буфера `bound_bc`,
    100% точность результата (факториал 5 = 120).
  - `anti_vmpredator_tamper_detection` в `test_anti_pushan.ml`: проверка детекции вмешательства — любая модификация
    или эмуляция без связывания адресов (`g_handlers_hash`) рассинхронизирует `running_key` на ветвлениях
    и немедленно крашит/абортит выполнение.
  - JSON roundtrip в `test_protection_config.ml`: сохранение и загрузка `anti_pushan.address_bound`.

---

## P4 — документация

### 8. Рассинхрон заявленных цифр — ВЫПОЛНЕНО 2026-09-23

- Исправлено: бейдж и все вхождения в `README.md` (4 места) — «225 tests, 33 suites»;
  `CPP_TODO.md` — «225 Dune tests».
- Канонический счётчик: 225 зарегистрированных кейсов в 33 сьютах; реестр сьютов — `test/run_tests.ml`.
- Дополнительно найдено и исправлено: README сливал два сьюта в пункте «Native Threaded VM
  and Metrics» — разделён на «Native Threaded VM» (19) и «Devirtualization Metrics» (20),
  нумерация 19-31 → 19-32.
- В матрицу `CPP_TODO.md` возвращена строка 9 (GPU Metal) со статусом REMOVED и ссылкой
  на пункт 3 этого файла.

---

## P5 — Доведение RV64GCV / AArch64 / x86-64 Lifters и VM-IR до широкого промышленного покрытия

> **Контекст**: текущие лифтеры покрывают базовый `-O2` целочисленный код и простейшие векторные/атомарные операции.
> Для устойчивой виртуализации реальных бинарников требуется устранить семантические дыры в модели памяти,
> флагов, динамического вектора RVV и расширений битовых манипуляций.
>
> **Порядок реализации по приоритету**:
> 1. **VM flags + memory semantics** (базовый фундамент корректности)
> 2. **RVV (RISC-V Vector)** (параметризованная модель вместо плоских 128-бит)
> 3. **x86 bit/BMI + SSE/AVX FP** (фиксация границы SSE / AVX-128 / AVX2 vs AVX-512)
> 4. **AArch64 FP/NEON + bit manipulation + atomics**
> 5. **Системные инструкции, CSR и границы сред (System / CSR / Fence)**

---

### Архитектурное расширение ядра VM-IR (Примитивы вместо разрастания опкодов)

Вместо добавления десятков разрозненных платформозависимых опкодов расширить `lib/vm_ir/ir.ml` ортогональными IR-примитивами:

| Категория | IR Примитивы | Семантика |
| :--- | :--- | :--- |
| **FLAGS** | `Get_flag`, `Set_flag`, `Materialize_flags`, `Lazy_flags` | Разделение eager и lazy флагов, извлечение отдельных бит (CF, ZF, SF, OF, PF, AF / NZCV), материализация флагового слова. |
| **BIT** | `Clz`, `Ctz`, `Bswap`, `Bit_test`, `Bit_set`, `Bit_clear`, `Bit_toggle` | Подсчёт ведущих/замыкающих нулей, реверс байт, атомарное тестирование и модификация отдельных бит. |
| **EXT** | `Sign_ext`, `Zero_ext`, `Trunc` | Явное представление расширения/усечения разрядностей B8/B16/B32/B64 без эвристических сдвигов. |
| **SHIFT** | `Shld`, `Shrd`, `Rotate` | Двухоперандные сдвиги с затягиванием битов из соседнего регистра, циклические сдвиги произвольной ширины. |
| **FP** | `Fadd`, `Fsub`, `Fmul`, `Fdiv`, `Fcmp`, `Fconv` | Скалярная арифметика IEEE-754 (single & double precision), сравнения с установкой флагов, конвертации `int <-> fp`. |
| **VECTOR** | `Vadd`, `Vsub`, `Vmul`, `Vshift`, `Vcmp`, `Vperm`, `Vreduce` | Параметризованные векторные операции над элементами произвольного SEW с маскированием и редукциями. |
| **CONTROL** | `Indirect_jmp`, `Indirect_call`, `Tailcall`, `Trap`, `Syscall` | Чёткие границы вызовов, косвенных переходов и изоляции внешних системных шлюзов. |
| **ATOMIC** | `Atomic_lr`, `Atomic_sc`, `Atomic_cas`, `Atomic_rmw` | Load-Reserved / Store-Conditional, Compare-And-Swap, универсальные Fetch-And-Op (Add, Sub, And, Or, Xor, Min, Max). |
| **SYSTEM** | `Fence`, `Csr_read`, `Csr_write` | Барьеры упорядочивания памяти/инструкций и доступ к регистрам управления/статуса. |

---

### Этап 1: VM Flags + Memory Semantics & ABI (Приоритет 1)

1. **Полная работа с флагами**:
   - Явные операции `Materialize_flags` и `Lazy_flags` для разгрузки контекста.
   - x86-64: инструкции `lahf`, `sahf`, `pushf`, `popf` с сохранением и восстановлением флагового регистра.
   - Арифметика с переносом/заёмом: `adc` и `sbb` с точным моделированием входящего и исходящего флага `CF`.
2. **Семантика памяти и адресации**:
   - AArch64: поддержка всех форм адресации для `ldp`/`stp` (offset, pre-indexed `[sp, #-16]!`, post-indexed `[sp], #16`, signed offset `[x29, #32]`).
   - AArch64: некэшируемые/привилегированные доступы `ldtr`, `sttr`.
   - AArch64 атомики (аналог A-extension): `ldxr`/`stxr`, `ldar`/`stlr` с acquire/release барьерами, а также атомарные RMW: `swp`, `ldadd`, `ldclr`, `ldset`, `ldeor`.
   - x86-64: поддержка инструкций изменения порядка байт `movbe` и `bswap`.
   - Верификация полного декартова произведения `movsx`/`movzx`/`movsxd` для всех комбинаций размеров (B8->B16, B8->B32, B8->B64, B16->B32, B16->B64, B32->B64) как для регистров, так и для операндов в памяти.
3. **Stack & Function ABI**:
   - Корректная модель специальных архитектурных регистров:
     * AArch64: `x30` / `LR` (Link Register), `sp` (Stack Pointer, выравнивание по 16 байт), `xzr`/`wzr` (константный нуль при чтении, sinkhole при записи).
     * RISC-V: `x0` / `zero` (hardwired zero).

---

### Этап 2: Параметризованная модель RISC-V Vector (RVV) (Приоритет 2)

Текущая модель fixed-width 128-bit SIMD недостаточна для стандарта RV64GCV. Требуется полноценный движок динамической конфигурации вектора:

1. **Модель состояния RVV**:
   - Регистры конфигурации: `VLEN` (конфигурируемая длина вектора платформы, напр. 128, 256, 512 бит), `SEW` (Selected Element Width: 8, 16, 32, 64), `LMUL` (Register Group Multiplier: 1/8, 1/4, 1/2, 1, 2, 4, 8), `VL` (Vector Length), `vstart`, `vmask` (регистр маски `v0`).
2. **Конфигурация вектора**:
   - Инструкции `vsetvli`, `vsetivli`, `vsetvl` с вычислением активной длины вектора `vl` по запрошенному `avl` и типу `vtype`.
3. **Векторная память**:
   - `vle8.v`, `vle16.v`, `vle32.v`, `vle64.v` и парные `vse*.v`.
   - Strided-доступы (`vlse*.v`, `vsse*.v`) и indexed-доступы (`vluxei*.v`, `vsuxei*.v`).
   - Fault-only-first загрузки (`vle*ff.v`).
4. **Векторная арифметика и логика**:
   - Целочисленные операции: `vadd.vv/vx/vi`, `vsub`, `vmul`, `vdiv`, `vrem`.
   - Битовые операции: `vand`, `vor`, `vxor`, `vnot`.
   - Сдвиги: `vsll`, `vsrl`, `vsra` (логические и арифметические).
   - Сравнения: `vmseq`, `vmsne`, `vmslt`, `vmsle` (знаковые и беззнаковые) с генерацией битовой маски в регистр.
   - Редукции: `vredsum.vs`, `vredmax.vs`, `vredmin.vs` (схлопывание вектора в скаляр).
   - Widening / Narrowing операции: `vwaddu`, `vwadd`, `vwmul`, `vnsrl`.
   - Перестановки и сдвиги регистров: `vrgather`, `vslideup`, `vslidedown`, `vcompress`.

---

### Этап 3: x86 Bit / BMI + SSE/AVX Floating Point и фиксация границ (Приоритет 3)

1. **Архитектурная фиксация границ AVX**:
   - `SSE (128-bit)` $\to$ **Supported**
   - `AVX-128 (VEX 128-bit)` $\to$ **Supported**
   - `AVX2 (VEX 256-bit YMM)` $\to$ **Supported / Partial**
   - `AVX-512 (EVEX 512-bit ZMM + Opmask k0..k7)` $\to$ **Explicit Unsupported / Trap Boundary** (вызов аварийного выхода или native fallback вместо молчаливой ошибочной трансляции).
   - *Устранить дублирование в документации списков `and/or/xor/not` и `shl/sal/shr/sar`*.
2. **Битовые операции и расширения BMI1 / BMI2**:
   - Тестирование и модификация бит: `bt`, `bts`, `btr`, `btc`.
   - Сканирование бит: `bsf`, `bsr`.
   - Подсчёт бит: `popcnt`, `lzcnt`, `tzcnt`.
   - Сдвиги двойной точности: `shld`, `shrd` с регистровым и непосредственным сдвигом.
   - Инструкции BMI1 / BMI2: `andn`, `bextr`, `bzhi`, `pdep`, `pext`, `rorx`, `sarx`, `shlx`, `shrx`.
3. **SSE / AVX расширения**:
   - Векторные сдвиги: `vpsllw/d/q`, `vpsrlw/d/q`, `vpsraw/d`.
   - Векторные сравнения: `vpcmpeqb/w/d/q`, `vpcmpgtb/w/d/q`.
   - Переупаковка и перестановки: `vpmov*`, `vpunpckh*`, `vpunpckl*`, `vpshufb`, `vpshufd`, `vpalignr`, `vblend*`.
   - Векторный FP: `vaddps/pd`, `vsubps/pd`, `vmulps/pd`, `vdivps/pd`, `vminps/pd`, `vmaxps/pd`, `vcmpps/pd`.

---

### Этап 4: AArch64 FP / NEON & Bit Manipulation (Приоритет 4)

1. **Скалярная плавающая точка (VFP)**:
   - Пересылка данных: `fmov` (между GPR и FPR, а также непосредственные float-константы).
   - Арифметика и сравнения: `fadd`, `fsub`, `fmul`, `fdiv`, `fcmp`, `fcsel`.
   - Преобразования: `fcvt` (half $\leftrightarrow$ single $\leftrightarrow$ double), `fcvtzs`, `fcvtzu`, `scvtf`, `ucvtf`.
2. **Векторный NEON**:
   - Векторная арифметика/логика: packed `add`, `sub`, `mul`, `and`, `orr`, `eor`.
   - Векторные сдвиги: `shl`, `sshr`, `ushr`.
   - Векторные сравнения: `cmeq`, `cmge`, `cmgt`, `cmtst`.
3. **Условные инструкции и NZCV**:
   - Условные сравнения: `ccmp`, `ccmn` (с установкой флагов по условию).
   - Точное моделирование флагов NZCV для `cinc`, `cinv`, `cneg`.
4. **Битовые манипуляции AArch64**:
   - Битовые поля: `ubfx`, `sbfx`, `bfi`, `bfxil`.
   - Обобщённые битовые маски: `ubfm`, `sbfm`, `bfm`.
   - Реверс и подсчёт нулей: `rbit` (реверс бит в слове), `clz`, `cls`.
   - Реверс байт: `rev` (64-бит), `rev32`, `rev16`.
5. **Расширенные умножения AArch64**:
   - `umaddl`, `umsubl`, `smaddl`, `smsubl` (умножение 32-битных в 64-битные с накоплением).
   - `umulh`, `smulh` (получение старшей половины 64-битного умножения без RDX).

---

### Этап 5: Системные инструкции, CSR и границы сред (Приоритет 5)

1. **x86-64 System Boundaries**:
   - `syscall`, `sysret`: явная изоляция через `External_Boundary` трамплины (сохранение контекста VM, вызов хост-ядра).
   - Идентификация и таймеры: `cpuid`, `rdtsc`, `rdtscp` (эмуляция или безопасный passthrough).
   - Управление расширенными состояниями: `xgetbv`.
2. **AArch64 System Boundaries**:
   - `eret` / прерывания: изоляция в границу исключений / unsupported trap.
3. **RISC-V System & CSR & Scalar FP**:
   - Системные boundary-инструкции: `ecall`, `ebreak`, `fence`, `fence.i`.
   - Инструкции работы с регистрами CSR: `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci` (эмуляция стандартных таймеров, счетчиков тактов `cycle`/`time` и флагов FP `fcsr`).
   - Скалярный FP (F- и D-расширения RV64FD):
     * Арифметика: `fadd.s/d`, `fsub.s/d`, `fmul.s/d`, `fdiv.s/d`, `fsqrt.s/d`, `fmin.s/d`, `fmax.s/d`, `fsgnj.s/d`, `fsgnjn.s/d`, `fsgnjx.s/d`.
     * Сравнения: `feq.s/d`, `flt.s/d`, `fle.s/d`.
     * Fused-multiply-add: `fmadd.s/d`, `fmsub.s/d`, `fnmsub.s/d`, `fnmadd.s/d`.
     * Загрузки/сохранения: `flw`, `fld`, `fsw`, `fsd`.
     * Преобразования: `fcvt.w.s/d`, `fcvt.l.s/d`, `fcvt.s.w/l`, `fcvt.d.w/l`, `fcvt.s.d`, `fcvt.d.s`.

---

## Общая приёмка для всех пунктов

1. `dune runtest` — зелёный, без исключений (текущая планка: 245 тестов в 34 сьютах).
2. E2E: чистый C внутри `ASGARD_BEGIN_VIRTUALIZE`/`ASGARD_END()` компилируется, лифтится и
   выполняется с той же семантикой и exit code 0 (критерий из `CPP_TODO.md`).
3. `dpx arch` — 0 ошибок / 0 предупреждений.
4. После изменения опкод-таблицы — golden-векторы `test/test_anti_pushan.ml` обязательны
   (урок из `0x1335877` vs `0x13375877`: зеркала OCaml/C++ расходятся молча).
