# ASGARD-5877: Audit TODO — недоделанные фичи и тихие деградации

> **Источник**: аудит движка 2026-09-23 (HEAD `898a4ee`, `dune runtest` зелёный).
> Не путать с `CPP_TODO.md` — там все позиции помечены DONE; перечисленное ниже
> в этом роадмапе **не трекается**. Порядок = приоритет.

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

### 3. `gpu_synth` при сбое тихо возвращает небезопасные данные

- **Где**: `lib/gpu_synth/gpu_synth.ml` (весь файл, 29 строк):
  - `batch_encrypt_gpu` при недоступном GPU/errors → `List.map (fun _ -> bytecode) keys` —
    **открытый байткод для каждого ключа** вместо шифрованного;
  - `synthesize_mba_gpu` → константа-заглушка `0x9E3779B97F4A7C15`;
  - `verify_sac_gpu` → фейковые `50.0`.
- **Следствие**: на машине без Metal (или после сбоя компиляции шейдера) защитный слой
  выглядит включённым, но работает вхолостую / отдаёт plaintext.
- **Чинить**: убрать тихий fallback — вернуть `Result`/`option` и обрабатывать на вызовах;
  путь «GPU недоступен» должен быть явным решением конфигурации, а не исключением `Sys_error`.
  Если фича заморожена — вырезать модуль из пайплайна и убрать бейдж «GPU Metal 3.0 (65k Threads)»
  из `README.md` (он удалён из роадмапа ещё в коммите `9b90920`).

### 4. SMC деградирует в no-op без диагностики

- **Где**: `lib/native_vm/runtime_smc.ml:14` — `return 0; // If dual-mapping is unsupported,
  degrade gracefully`. На W^X-платформах слой самомодификации молча выключен.
- **Чинить**: как минимум — лог/флаг сборки, отражающий реальный режим (full SMC / degraded);
  в идеале — отказ сборки при требуемом профиле `maxsec` и недоступном dual-mapping
  (сейчас `protected_arm64_maxsec` может собраться без SMC и никто не узнает).

---

## P2 — покрытие лифтеров

### 5. x86-64 лифтер: нет `div`/`idiv`/`mul`, ноль SIMD — ВЫПОЛНЕНО 2026-09-24

- Сделано в `lib/x86_lifter/lifter.ml`:
  - `div`/`idiv` на B64 и B32 (регистр/память): частное в rax, остаток реконструируется
    как `dividend − quotient·divisor` через зарезервированные `vx18`/`vx19`; флаги не
    трогаются (по x86 после div/idiv UB). Компиляторный канон rdx (`cqo`/`cdq` или
    `xor edx,edx`) делает 64-битное деление точным.
  - `cdq`/`cltd`/`cqo`/`cqto` → Nop (канонизация не нужна при реконструкции из rax),
    `cdqe`/`cltq` → пара Shl32/Sar32 (сигнум-расширение rax).
  - 1-операндный `mul`/`imul` и SIMD — намеренно громкий `Error` с внятным сообщением
    (честный отказ вместо тихой неправильной семантики).
- Тесты: 6 эвалюаторных (`test_x86_lifter.ml` 8-13: div/idiv 64/32 signed/unsigned,
  cdqe, zext) + 2 нативных E2E (`test_native_vm.ml` 9-10: частное и остаток через
  `get_reg(REG_RDX)`, полный B32-idiv-лоуэринг и изолированный zext).
- **Найдено попутно (серьёзное)**: эмиттер `lib/native_vm/vm_emitter.ml` во всех
  RR-формах ALU молча отбрасывает `src1` при `src1 ≠ dst` (кодируются только dst и src2,
  нативный хендлер считает `dst OP src`). Все старые тесты использовали форму src1=dst,
  поэтому баг был невидим — div-реконструкция вскрыла его первым же нативным запуском.
  Обход в лифтере: все инструкции держат src1=dst (остаток аккумулируется в vx19).
  Системный фикс (3 поля в слове или MOV-прелюдия с защитой от clobber src2=dst) —
  отдельная задача: то же минное поле латентно для arm64, где ассемблер естественно
  3-операндный (`add x0, x1, x2`); см. новый пункт 9 ниже.
- Остаточные ограничения: B8/B16-ширины div — громкая ошибка; `Ir.Div`/`Idiv` на 0
  дают 0 (модель, не x86 #DE).

### 6. Частичная запись в 32-битные подрегистры не моделируется — ВЫПОЛНЕНО 2026-09-24

- Сделано: новый общий пасс `lib/vm_ir/subreg_write.ml` (x86 и arm64): после каждой
  GPR-записи в B32 дописывает бесплатную по флагам пару `shl 32 / shr 32` на B64.
  В эвалюаторе пара — no-op (`set_reg` уже обрезает), в нативной width-blind VM —
  выполняет зануление верхней половины, которое делает ISA. Подключён в
  `x86_lifter/lift_lines` и `arm64_lifter/lift_lines` до патчинга терминаторов.
- Тесты: эвалюаторно (`mov eax, esi` зануляет верх rax) и нативно
  (`native_b32_subregister_semantics`: idiv-лоуэринг с B32-записями + изолированный zext).
- Остаточные ограничения (осознанно): B8/B16 — merge-семантика не моделируется;
  `Fp_conv`/`Atomic_mem` исключены (эвалюатор их no-op'ит); arm64 w18–w28
  (Vreg-B32) проходят мимо фильтра GPR — зануление для них не добавляется.

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

### 7. Anti-VMPredator address-bound bytecode (не начат)

- **Контекст**: `docs/VM_PROTECTOR.md:187` честно фиксирует границу текущих rolling keys —
  последовательный статический проход всё равно восстанавливает keystream.
- **Дизайн**: ключ дешифровки секции байткода = хеш реальных адресов хендлеров в памяти
  (dump/relocation/patch рендерит байткод бесполезным; даёт настоящее межблочное
  history-связывание, которого нет у rolling keys).
- **Чинить** (= реализовать): считать хеш на этапе init C++-рантайма, миксовать в
  `anchor_key`, зеркалить в OCaml-энкодере невозможно (адреса известны только в рантайме) —
  поэтому шифрование байткода переносится в runtime-init, обновить `test_anti_pushan.ml`.

---

## P4 — документация

### 8. Рассинхрон заявленных цифр — ВЫПОЛНЕНО 2026-09-23

- Исправлено: бейдж и все вхождения в `README.md` (4 места) — «175 tests, 32 suites»;
  `CPP_TODO.md` — «175 project tests» и «All 175 Dune tests».
- Канонический счётчик: 175 зарегистрированных кейсов (124 `Alcotest.test_case` + 51
  кортежный стиль) в 32 сьютах; реестр сьютов — `test/run_tests.ml`.
- Дополнительно найдено и исправлено: README сливал два сьюта в пункте «Native Threaded VM
  and Metrics» — разделён на «Native Threaded VM» (19) и «Devirtualization Metrics» (20),
  нумерация 19-31 → 19-32.
- В матрицу `CPP_TODO.md` возвращена строка 9 (GPU Metal) со статусом REMOVED и ссылкой
  на пункт 3 этого файла.

---

## Общая приёмка для всех пунктов

1. `dune runtest` — зелёный, без исключений.
2. E2E: чистый C внутри `ASGARD_BEGIN_VIRTUALIZE`/`ASGARD_END()` компилируется, лифтится и
   выполняется с той же семантикой и exit code 0 (критерий из `CPP_TODO.md`).
3. `dpx arch` — 0 ошибок / 0 предупреждений.
4. После изменения опкод-таблицы — golden-векторы `test/test_anti_pushan.ml` обязательны
   (урок из `0x1335877` vs `0x13375877`: зеркала OCaml/C++ расходятся молча).
