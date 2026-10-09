# ASGARD-5877: Project Roadmap & Status

> **Статус**: Все пункты исторического аудита P0–P5 закрыты на 100%.  
> Полная архивная спецификация аудита и лифтеров сохранена в [`docs/archive/AUDIT_TODO.md`](docs/archive/AUDIT_TODO.md).  
> **Текущий статус (2026-10)**: 387 тестов в 36 сьютах проходят успешно (100% pass rate, 0 предупреждений под `-warn-error -a`).

---

## 1. Завершённые этапы (Архив)

- [x] **P0: Корректность базового движка** — 16-битный доступ к памяти (`ldrh`/`strh`), знаковое расширение при загрузках (`ldrsb`/`ldrsh`/`movsx`/`movsxd`).
- [x] **P1: Безопасность и отказоустойчивость** — устранение тихого fallback в `gpu_synth`, строгий режим SMC (`ASGARD_SMC_STRICT`) с диагностикой статусов.
- [x] **P2: Покрытие лифтеров** — x86-64 `div`/`idiv`/`mul` во всех ширинах B8–B64, нормализация частичной записи в подрегистры (`subreg_write`), 3-адресное ALU (`canonicalize_3addr_alu`).
- [x] **P3: Продвинутая защита** — Anti-VMPredator address-bound bytecode с криптографической привязкой keystream к реальным адресам хендлеров.
- [x] **P4: Документация и матрицы** — синхронизация канонических счётчиков тестов и архитектурных инвариантов.
- [x] **P5: Расширение архитектурных лифтеров и VM-IR**:
  - [x] **Уровень 1 (Quick Wins)**: скалярный FP (ARM64/RISC-V), битовые инструкции хоста (`clz`/`ctz`/`popcnt`/`rev8`/`bswap`/`bt*`), x86 флаги (`clc`/`stc`/`cmc`/`cld`/`std`), системные traps (`syscall`, `cpuid`, `rdtsc`, `ecall`, `ebreak`, `eret`, CSR).
  - [x] **Уровень 2 (Medium)**: битовые поля (`ubfx`/`sbfx`/`bfi`/`extr`, BMI1/BMI2), 2-операндные сдвиги (`shld`/`shrd`/`rcl`/`rcr`), умножения с накоплением (`smaddl`/`umaddl`/`smsubl`/`umsubl`/`smulh`/`umulh`), FP<->Int преобразования и квадратный корень (`cvtsi2ss/sd`, `cvtss2si/sd`, `fcvt.*`, `sqrtss`, `sqrtsd`, `fsqrt.s/d`), сложная адресация (`ldp`/`stp`, `movbe`, `xlat`).
  - [x] **Уровень 3 (Hard)**: полная каноническая модель EFLAGS (`adc`/`sbb` B8–B64, `pushf`/`popf`, `lahf`/`sahf`, единый диспетчер флагов), условные сравнения ARM64 (`ccmp`/`ccmn`, селекторы `csinc`/`csinv`/`csneg`, `adcs`/`sbcs`), строковые инструкции x86 с префиксами повторения (`rep`, `repe`, `repne`), атомики и барьеры SMP (`fence`, `dmb`, `mfence`, `lock`, `xadd`, `cmpxchg`, `cmpxchg8b/16b`, `xchg`, LSE `swp`/`ldadd`, `lr`/`sc`/`amo*`), AVX-256 YMM регистры (256/512 бит, верхнее зануление VEX-128, целочисленный SIMD, явный EVEX/ZMM trap).
  - [x] **Уровень 4 (Architectural)**: параметризованный векторный движок RISC-V RVV 1.0 (`vsetvli`/`vsetivli`/`vsetvl`, CSR `vl`/`vtype`/`vlenb`, память unit-stride/strided/indexed, арифметика/логика/сдвиги/деление/остатки, сравнения, маски, редукции, слайды и перестановки).
  - [x] **Спецификация x86_64**: moffs прямая адресация смещением (`mov al/ax/eax/rax, [moffs]`), сегментные регистры (`push/pop ds/es/fs/gs/ss`, `mov`, `rdfsbase/wrfsbase/rdgsbase/wrgsbase`), полная поддержка всех трёх форм `imul`.

---

## 2. Реализованный Stage 3 Focus (2026-10)

- [x] **Windows PE / MSVC Toolchain & Native Runtime Parity (`lib/native_vm`)**:
  - [x] `runtime_syscalls`: учёт `target_os = [ \`Darwin | \`Linux | \`Windows | \`Auto ]`, стелс-проверка PEB (`__readgsqword(0x60)` / `__readfsdword(0x30)` -> `BeingDebugged`, `NtGlobalFlag`), Win32 I/O и процессные примитивы.
  - [x] `runtime_dual_map`: W^X dual-mapping для Windows через `CreateFileMappingW` (секционный маппинг страничного файла) + раздельные RW и RX `MapViewOfFile` с корректным `UnmapViewOfFile`.
  - [x] `runtime_smc`: поддержка `_WIN32` в `ASGARD_SMC_STRICT`, сброс кеша инструкций через `FlushInstructionCache`, таймер `__rdtsc()`, диспетчер наномитов через `AddVectoredExceptionHandler`.
  - [x] `vm_control_handlers`: эмиссия ловушек наномитов `__debugbreak()` для таргета `_WIN32`.
  - [x] `runtime_probes`: сканирование аппаратных точек останова `Dr0..Dr7` через `GetThreadContext`, проверка подозрительных RWX-регионов через `VirtualQuery`, тайминг-дифференциал через `QueryPerformanceCounter`.
  - [x] `runtime_ephemeral_jit`: сброс кеша инструкций `FlushInstructionCache` и Windows headers для эфемерного JIT.
- [x] **Продвинутый синтез MBA 5-го порядка (`lib/mba_engine`)**:
  - [x] `mba.ml`: нуль-полиномы 5-й степени над $\mathbb{Z}_{2^{64}}$ ($2^{61} \cdot x(x-1)(x-2)(x-3)(x-4) \equiv 0$) и нелинейные кросс-композиции 5-й степени на дизъюнктных булевых разбиениях.
  - [x] `mba.mli`: тип `order = [ \`Deg4 | \`Deg5 ]`, расширение сигнатур `rewrite`, `obfuscate_alu`, экспорт нуль-инвариантов.
  - [x] `egraph_rules.ml`: правила расширения 5-го порядка (`mul_nl_deg5_poly`, `mul_nl_deg5_cross`, `add_deg5_opaque`, `xor_deg5_opaque`), `rules_deg5`, `all_rules` (28 правил), `verify_all_rules`.
  - [x] Спецификация и свойственные тесты эквивалентности для MBA 5-й степени (`test_mba_deg5_polynomial_invariants`, `test_mba_deg5_rewrite_equivalence`).
- [x] **Управляемая плотность Junk-кода и размерный бюджет (`bloat_config.junk_density` & `target_size_budget_kb`)**:
  - [x] Параметризованная инжекция мусорных инструкций `inject_junk_instructions ?(density = 0.5)`: от 0.0 (полное отключение) до 2.0 (100% вероятность + мульти-пачки junk-инструкций).
  - [x] Подключение в `vm_emitter`: связывание `junk_density` и динамическое сжатие плотности при строгих бюджетах `target_size_budget_kb`.
- [x] **Диверсификация доменов диспетчеризации (`vm_runtime_emitter.ml`)**:
  - [x] Структурная диверсификация 216+ decoy-слотов между всеми доменами $d \in [0, num\_domains - 1]$ (`(base_idx + d * 7 + i * 3) mod 16`).
  - [x] Сохранение идентичности рабочих опкодов между доменами при полной разнородности jump-таблиц в памяти и совместном хешировании в `compute_handlers_hash`.
- [x] **Активация Opaque Predicates в CFF (`cff.ml` & `protection_presets.ml`)**:
  - [x] Корректное расщепление базовых блоков на предикатный заголовок `pred_block` и рабочее тело `body_block`, предотвращающее зацикливание `Ir.Jcc`.
  - [x] Математический инвариант $((x \land (x + 1)) \land 1 \equiv 0)$ с маршрутизацией в `trap_block_id` при нарушении.
  - [x] Включение непрозрачных предикатов по умолчанию в пресетах `max_security`, `high` и `stealth`.
  - [x] Сквозные тесты компиляции и нативного выполнения C++ рантайма с CFF и непрозрачными предикатами.

---

## 3. Перспективные направления (Stage 3 Backlog)

- [ ] **JIT-движок (`rd_jit_vm`)**:
  - [ ] Расширение JIT-эмиттера для поддержки векторных и атомарных инструкций в нативном рантайме.
  - [ ] Оптимизация горячих циклов с динамической девиртуализацией и компиляцией в машинный код хоста.
- [ ] **E2E бенчмарки и стресс-тесты**:
  - [ ] Набор реальных C/C++ бинарников (OpenSSL, SQLite, Coreutils), компилируемых под Clang `-O3`.
  - [ ] Стресс-тестирование против автоматических деобфускаторов (angr, Triton, Ghidra, IDA Pro).
- [ ] **Обогащение грамматик NCFG новыми типами нелинейных операторов**.
