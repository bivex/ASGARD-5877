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
> 1. **VM flags + memory semantics** (базовый фундамент корректности: EFLAGS/NZCV, адресация, atomics/fence)
> 2. **RVV (RISC-V Vector)** (параметризованная модель VL/VTYPE/VLMUL/SEW вместо плоских 128-бит)
> 3. **x86 bit/BMI + SSE/AVX FP** (скалярный FP, AVX-256 zeroing, фиксация границы AVX-512)
> 4. **AArch64 FP/NEON + bit manipulation + atomics**
> 5. **Системные инструкции, CSR и границы сред (System / CSR / Fence)**

---

### 1. Архитектурное состояние VM (VMContext Core State Model)

Для исполнения произвольного бинарного кода `VMContext` обязан явно выражать:
* **GPR**: 64-битные регистры общего назначения хост/гостевой архитектуры.
* **PC & SP**: счётчик команд и указатель стека с платформенным выравниванием (16 байт для ARM64/x86-64 ABI).
* **Архитектурный Condition State**:
  * *x86-64*: каноническая шестёрка `CF`, `OF`, `SF`, `ZF`, `AF`, `PF`.
  * *AArch64*: биты условий `NZCV` (Negative, Zero, Carry, oVerflow).
  * *RISC-V*: прямое сравнение регистров в ветвлениях, плюс флаги статуса FP (`NV`, `DZ`, `OF`, `UF`, `NX`).
  * *Принцип*: отказ от принудительного сведения ARM64/RISC-V к x86 EFLAGS — поддержка нативного моделирования состояний.
* **Память и Memory Ordering**:
  * Барьеры памяти: `SeqCst`, `Acquire`, `Release`, `AcqRel`, `Relaxed`.
  * Явное представление барьеров упорядочивания (`FENCE` / `DMB` / `MFENCE`) для всех трёх ISA, без которых SMP/атомики неполны.
* **FP / Vector Registers & Control/Status**:
  * 128/256-битные векторные банки и скалярные FP-аккумуляторы.
  * Управляющие регистры FP-окружения: `MXCSR` (x86), `FPCR`/`FPSR` (ARM64), `fcsr` (RISC-V).

---

### 2. Ортогональное расширение примитивов VM-IR

Вместо разрастания ad-hoc опкодов расширить ядро `lib/vm_ir/ir.ml` универсальными примитивами:

| Группа IR | Примитивы | Семантика |
| :--- | :--- | :--- |
| **FLAGS** | `Flags_get`, `Flags_set`, `Flags_merge`, `Flags_materialize`, `Lazy_flags` | Прямое извлечение/запись флагов, слияние частичных апдейтов, материализация в GPR, SSA-трекинг флагов. |
| **MEMORY** | `Load`, `Store`, `Load_signed`, `Load_zero_ext`, `Atomic_rmw`, `Fence` | Типизированный доступ с размерами B8–B64, атомарные RMW (Add, Sub, And, Or, Xor, Min, Max), барьеры памяти. |
| **ADDRESS** | `Lea`, `Address`, `Pc_rel` | Вычисление эффективного адреса (Base + Index*Scale + Disp), сегментные базы, PC-relative адресация. |
| **CONTROL** | `Indirect_jmp`, `Indirect_call`, `Return`, `Switch`, `Tailcall`, `Trap`, `Syscall` | Косвенная диспетчеризация, jump tables (switch), границы системных вызовов и изоляция исключений. |
| **EXT / BIT** | `Sign_ext`, `Zero_ext`, `Trunc`, `Bitcast`, `Clz`, `Ctz`, `Bswap`, `Bit_test`, `Bit_set`, `Bit_clear`, `Bit_toggle` | Манипуляции разрядностями без хаков со сдвигами, битовые тесты, подсчёт нулей, реверс байт/бит. |
| **SHIFT** | `Shld`, `Shrd`, `Rotate`, `Rcl`, `Rcr` | Двухоперандные сдвиги, циклические сдвиги, сдвиги через флаг переноса (carry). |
| **FP** | `Fadd`, `Fsub`, `Fmul`, `Fdiv`, `Fsqrt`, `Fcmp`, `Fconv` | Скалярная арифметика single (F32) и double (F64), квадратный корень, сравнения, конвертации `int <-> fp`. |
| **VECTOR** | `Vec_splat`, `Vec_extract`, `Vec_insert`, `Vec_shift`, `Vec_compare`, `Vec_shuffle`, `Vadd`, `Vsub`, `Vmul`, `Vperm`, `Vreduce` | Параметризованные векторные примитивы: broadcasting, вставка/извлечение элементов, сдвиги, перестановки, редукции. |
| **SYSTEM** | `Fence`, `Csr_read`, `Csr_write` | Синхронизация инструкций/памяти, доступ к системным/пользовательским CSR-регистрам. |

---

### 3. Спецификация покрытия x86_64

1. **Память, сегментация и строковые операции**:
   - Изменение порядка байт: `movbe`, `bswap`.
   - Табличная трансляция: `xlat` / `xlatb`.
   - Строковые инструкции: `stosb/stosw/stosd/stosq`, `lodsb/lodsw/lodsd/lodsq`, `scasb/scasw/scasd/scasq`, `cmpsb/cmpsw/cmpsd/cmpsq`.
   - Префиксы повторения строк: `rep`, `repe`/`repz`, `repne`/`repnz` с автоматическим декрементом `RCX` и проверкой `ZF`.
   - Адресация сегментов: префиксы переопределения `FS:` и `GS:` (TLS / thread-local storage).
   - Прямая адресация смещением: `moffs`-формы `mov` (`mov al/ax/eax/rax, [moffs]`).
   - push/pop сегментных регистров при виртуализации низкоуровневых контекстов.
2. **Целочисленная арифметика и EFLAGS**:
   - `adc` и `sbb`: для всех размеров (B8, B16, B32, B64) с точным расчётом всей шестёрки флагов (`CF`, `ZF`, `SF`, `OF`, `AF`, `PF`).
   - `imul`: полная поддержка всех трёх форм (1-операндная с implicit RDX:RAX, 2-операндная `reg, r/m`, 3-операндная `reg, r/m, imm`).
   - Битовые тесты: `bt`, `bts`, `btr`, `btc` (с установкой флага `CF`).
   - Сканирование и подсчёт бит: `bsf`, `bsr`, `tzcnt`, `lzcnt`, `popcnt`.
   - Инструкции BMI1 / BMI2: `bextr`, `bzhi`, `pdep`, `pext`, `andn`, `rorx`, `sarx`, `shlx`, `shrx`.
   - Сдвиги: `shld`, `shrd` (двухоперандные сдвиги), `rcl`, `rcr` (циклические сдвиги через carry).
3. **Управление флагами**:
   - Инструкции: `lahf`, `sahf`, `pushf`/`pushfq`, `popf`/`popfq`, `clc`, `stc`, `cmc`, `cld`, `std`.
   - Единая каноническая модель EFLAGS для предикатов `setcc`, `cmovcc`, `jcc`.
4. **SSE / AVX / AVX2**:
   - Граница поддержки:
     * `SSE (128-bit)` $\to$ **Supported**
     * `AVX-128 (VEX 128-bit)` $\to$ **Supported**
     * `AVX2 (VEX 256-bit YMM ymm0..ymm15/31)` $\to$ **Supported** с обязательным занулением верхней 128-битной половины YMM при записи в XMM.
     * `AVX-512 (EVEX 512-bit ZMM + Opmask k0..k7)` $\to$ **Explicit Unsupported / Trap Boundary**.
   - Целочисленные SIMD: `vpsll*`, `vpsrl*`, `vpsra*`, `vpcmpeq*`, `vpcmpgt*`, `vpmov*`, `vpunpck*`, `vpack*`, `vpshuf*`, `vperm*`, `vblend*`, `vmin*`, `vmax*`, `vpabs*`, `vpmuludq`, `vpmadd*`, `vpsadbw`, `vzeroupper`.
   - Скалярный FP: `addss/addsd`, `subss/subsd`, `mulss/mulsd`, `divss/divsd`, `comiss/ucomiss`, `comisd/ucomisd`, `sqrtss/sqrtsd`, конвертации `cvtsi2ss/cvtsi2sd`, `cvtss2si/cvtsd2si`, `cvtsd2ss`, `cvtss2sd`.
5. **Атомики (SMP)**:
   - Префикс `lock` для шинных блокировок.
   - Инструкции: `xadd`, `cmpxchg`, `cmpxchg8b`, `cmpxchg16b`.
   - `xchg` с операндом в памяти (неявная атомарность без префикса lock).

---

### 4. Спецификация покрытия ARM64 (AArch64)

1. **Память и эксклюзивные доступы**:
   - Загрузки/сохранения: `ldrb/ldrh/ldrsb/ldrsh`, привилегированные `ldtr/sttr` (включая знако-расширяющие).
   - Парные нетемпоральные доступы: `ldnp/stnp`.
   - Векторные NEON load/store: `ld1/st1` (одно- и многоструктурные).
   - One-way barriers (Acquire/Release): `ldar/ldarb/ldarh`, `stlr/stlrb/stlrh`.
   - Эксклюзивные доступы: `ldxrb/ldxrh/ldxr`, `stxrb/stxrh/stxr`, `ldaxrb/ldaxrh/ldaxr`, `stlxrb/stlxrh/stlxr`.
   - Атомарные RMW (LSE / Large System Extensions): `swp`, `ldadd`, `ldclr`, `ldset`, `ldeor` (все с версиями `a`/`l`/`al`).
2. **Условные инструкции**:
   - `ccmp`, `ccmn` (Conditional Compare с дефолтными NZCV флагами).
   - `cinc`, `cinv`, `cneg`, `csinc`, `csinv`, `csneg` (Conditional Select с инкрементом/инверсией/отрицанием).
3. **Битовые манипуляции**:
   - `clz`, `cls` (подсчёт ведущих нулей / знаковых бит).
   - `rbit` (реверс битов).
   - Реверс байт: `rev`, `rev16`, `rev32`.
   - Битовые поля: `ubfx`, `sbfx`, `ubfm`, `sbfm`, `bfi`, `bfxil`.
   - Извлечение битовых полей из двух регистров: `extr`.
4. **Целочисленная арифметика**:
   - Умножения: `smaddl`, `smsubl`, `umaddl`, `umsubl`, `smulh`, `umulh`.
   - Знаковое/нулевое расширение: `sxtb/sxth/sxtw`, `uxtb/uxth/uxtw`.
   - Арифметика с флагом переноса: `adc`, `adcs`, `sbc`, `sbcs`, `ngc`, `ngcs`.
5. **NEON и Floating Point**:
   - Скалярный FP: `fadd/fsub/fmul/fdiv`, `fmin/fmax`, `fcmp`, `fcsel`, `fcvt` (half/single/double), `scvtf/ucvtf`, `fcvtzs/fcvtzu`.
   - NEON векторная память: `ldr/str` SIMD.
   - NEON арифметика/логика: векторные `add/sub/mul`, `and/orr/eor/bic`.
   - Табличные подстановки и перестановки: `tbl`, `tbx`, `ext`, `dup`, `zip1/zip2`, `uzp1/uzp2`, `trn1/trn2`.

---

### 5. Спецификация покрытия RISC-V (RV64GCV)

1. **Скалярная плавающая точка (F- и D-расширения RV64FD)**:
   - Память: `flw`, `fld`, `fsw`, `fsd`.
   - Арифметика: `fadd.s/d`, `fsub.s/d`, `fmul.s/d`, `fdiv.s/d`, `fsqrt.s/d`, `fmin.s/d`, `fmax.s/d`.
   - Сравнения: `feq.s/d`, `flt.s/d`, `fle.s/d`.
   - Копирование знака: `fsgnj.s/d`, `fsgnjn.s/d`, `fsgnjx.s/d`.
   - Fused Multiply-Add: `fmadd.s/d`, `fmsub.s/d`, `fnmsub.s/d`, `fnmadd.s/d`.
   - Преобразования: `fcvt.*` (между FP и целыми числами, а также float $\leftrightarrow$ double).
2. **Векторное расширение V (RVV Dynamic Vector Engine)**:
   - *Архитектурный инвариант*: динамическая параметризация `VL/VTYPE/VLMUL/SEW`, поддержка `vlen` $\ge 128$.
   - Конфигурация: `vsetvli`, `vsetivli`, `vsetvl`.
   - Память:
     * Unit-stride: `vle8/16/32/64.v`, `vse8/16/32/64.v`.
     * Strided: `vlse*.v`, `vsse*.v`.
     * Indexed: `vluxei*`, `vloxei*`, `vsuxei*`, `vsoxei*`.
   - Арифметика и логика:
     * `vadd`, `vsub`, `vrsub`, `vmul`, `vdiv`, `vrem`.
     * `vand`, `vor`, `vxor`, `vnot`.
     * `vsll`, `vsrl`, `vsra`.
     * `vmin`, `vmax`.
   - Сравнения и маски:
     * `vmseq`, `vmsne`, `vmslt`, `vmsle` (signed/unsigned).
     * `vmerge`, `vmv`.
     * Логика масок: `vmand`, `vmor`, `vmxor`.
   - Редукции и перестановки:
     * `vredsum`, `vredmax`, `vredmin`.
     * `vslideup`, `vslidedown`.
     * `vrgather`, `vcompress`.
3. **Системные инструкции, барьеры и CSR**:
   - `ecall`, `ebreak`.
   - Память и упорядочивание: `fence`, `fence.i`, `fence.tso`.
   - Регистры управления и статуса: `csrrw`, `csrrs`, `csrrc`, `csrrwi`, `csrrsi`, `csrrci`.

---

## Общая приёмка для всех пунктов

1. `dune runtest` — зелёный, без исключений (текущая планка: 245 тестов в 34 сьютах).
2. E2E: чистый C внутри `ASGARD_BEGIN_VIRTUALIZE`/`ASGARD_END()` компилируется, лифтится и
   выполняется с той же семантикой и exit code 0 (критерий из `CPP_TODO.md`).
3. `dpx arch` — 0 ошибок / 0 предупреждений.
4. После изменения опкод-таблицы — golden-векторы `test/test_anti_pushan.ml` обязательны
   (урок из `0x1335877` vs `0x13375877`: зеркала OCaml/C++ расходятся молча).
