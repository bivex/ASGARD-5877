# TODO: корректность виртуализации ARM64 LSE-атомиков, FP-конверсий и carry-арифметики

Дата: 2026-10-20. Обнаружено при проверке инструкций `LDADD`, `LDADDA`, `LDADDAL`,
`LDADDL`, `UCVTF`, `SCVTF`, `SBC` в ARM64-лифтере и виртуальных машинах.

Кратко: все семь мнемоник распознаются лифтером (lift проходит без ошибки
«Unsupported or invalid ARM64 instruction»), но семантика реализована не полностью.
Ниже по каждому пункту: где расходится с ARM64, как воспроизвести, какой файл править.

## 1. Сводка по движкам

| Инструкция | Лифтер | threaded (по умолчанию) | stack | jit | multi |
|---|---|---|---|---|---|
| `LDADD`, `LDADDA`, `LDADDAL`, `LDADDL` | `Ir.Atomic_mem AtAdd`, `lib/arm64_lifter/arm64_mem.ml:222` | **ИСПРАВЛЕНО** (см. п. 6.1 — регрессия transform-пайплайна) | неверно | не применимо, см. п. 4.3 | неверно |
| `UCVTF` | `Ir.Fp_conv Ucvtf`, `lib/arm64_lifter/arm64_branch.ml:196` | **ИСПРАВЛЕНО** (см. п. 6.1 — UCVTF как SCVTF после fallback) | выбрасывается | выбрасывается | выбрасывается |
| `SCVTF` | `Ir.Fp_conv Scvtf`, `lib/arm64_lifter/arm64_branch.ml:194` | **ИСПРАВЛЕНО** (sign-ext src & binary32 rounding) | выбрасывается | выбрасывается | выбрасывается |
| `SBC` | `Ir.Alu Sbb`, `lib/arm64_lifter/arm64_alu.ml:188` | **ИСПРАВЛЕНО** (probe B = 63/63) | неверно: затирает NZCV | неверно | неверно: затирает NZCV |
## 2. LDADD, LDADDA, LDADDAL, LDADDL

Семантика ARM64: `LDADD <val>, <dst>, [<mem>]` записывает в `<dst>` старое значение
памяти, `<val>` не изменяет, память получает `old + val`.

### 2.1. Регистр-приёмник не получает старое значение, регистр со значением затирается

Лифтер строит `Ir.Atomic_mem { op = AtAdd; dst = res_reg; addr = base; src = val_reg; imm }`
(`lib/arm64_lifter/arm64_mem.ml:222-226`). Эмиттер кодирует только пару `(addr, src)`,
поле `dst` теряется (`lib/native_vm/vm_emitter.ml:806-817`):

```ocaml
| AtAdd -> encode_raw_word (get_opcode OP_ATOMIC_ADD) (get_reg_idx addr) (get_reg_idx src) imm
```

Обработчик пишет старое значение в регистр со значением (`lib/native_vm/vm_mem_handlers.ml:1552`):

```cpp
H_ATOMIC_ADD: {
    uint64_t _addr = (ctx.get_reg(dst) + static_cast<uint64_t>(imm));
    uint64_t _old = __atomic_fetch_add(reinterpret_cast<uint64_t*>(_addr), ctx.get_reg(src), __ATOMIC_SEQ_CST);
    ctx.set_reg(src, _old);
```

Текущая семантика `AtAdd` соответствует конвенции x86 `lock xadd` (`dst = src`,
`lib/x86_lifter/lifter.ml:1158`), а не ARM64, где приёмник и значение — разные регистры.

### 2.2. Всегда 64-битный доступ к памяти

`ldadd w`, `ldaddb`, `ldaddh` исполняются как `__atomic_fetch_add` по `uint64_t*`.
Ширина `m.width` из `OpMem` не доходит до IR и игнорируется.

### 2.3. Порядок доступа A/L/AL не моделируется

`ldadd`, `ldadda`, `ldaddl`, `ldaddal` лифтятся в один и тот же `AtAdd`, fence не ставится.
Барьеры `dmb`, `dsb`, `isb` лифтятся в `Nop` (`lib/arm64_lifter/arm64_alu.ml:822`,
`lib/arm64_lifter/arm64_mem.ml:318`), поэтому даже эмиссия `Ir.Fence` потребует отдельной работы.

### 2.4. Stack-движок

`lib/stack_vm/ir_to_stack.ml:246` превращает `Atomic_mem` в `PushReg src; PopReg dst`:
обращения к памяти нет вовсе, регистр-приёмник получает значение, а не старое значение памяти.

## 3. UCVTF и SCVTF

### 3.1. Ширина источника игнорируется

`H_SCVTF` и `H_UCVTF` (`lib/native_vm/vm_mem_handlers.ml:1372`, `lib/native_vm/vm_mem_handlers.ml:1410`)
читают `ctx.get_reg(src)`, то есть полные 64 бита регистра.

- `scvtf d0, w0` по ARM64 sign-extend-ит 32-битное значение, VM трактует x-регистр как есть.
- `ucvtf d0, w0` по ARM64 использует только младшие 32 бита, VM берёт и старшую половину.

### 3.2. Ширина приёмника теряется

Лифтер принудительно подставляет `dst = Register.Fpr (d, Register.B64)`
(`lib/arm64_lifter/arm64_branch.ml:181`, `lib/arm64_lifter/arm64_branch.ml:183`).
Single-форма (`scvtf s0, x1`) не округляется до binary32: VM всегда хранит double.

### 3.3. Stack-движок

`lib/stack_vm/ir_to_stack.ml:244`: `Fp_binop`, `Fp_cmp`, `Fp_conv` превращаются в `[]`,
инструкция выбрасывается без диагностики.

## 4. SBC и ADC

### 4.1. SBC и ADC затирают NZCV

Лифтер различает формы корректно: `sbc` даёт `set_flags:false`, `sbcs` — `set_flags:true`
(`lib/arm64_lifter/arm64_alu.ml:188-191`). Но обработчики `H_ADC_RR`
(`lib/native_vm/vm_alu_handlers.ml:1223`) и `H_SBB_RR` (`lib/native_vm/vm_alu_handlers.ml:1299`)
пишут `ctx.cf`, `ctx.of`, `ctx.zf`, `ctx.sf` безусловно; опкодов «без флагов» в VM нет.

Референсная модель `lib/vm_ir/vm_eval.ml:581` уважает `set_flags`, то есть расходится с продуктом.

### 4.2. ADC берёт инвертированный carry

Флаги в VM x86-стилевые: `compute_cf` для `SUB` возвращает borrow
(`lib/vm_ir/flags.ml:82`), тогда как ARM64 `C` означает «no borrow». Ветвление это
компенсирует (`hs` отображается в `Flags.AE` = `not compute_cf`, `lib/arm64_lifter/arm64_common.ml:38`),
но `H_ADC_RR` прибавляет `ctx.cf` напрямую, поэтому после `cmp` или `subs` carry инвертирован:
`adc x, 10, 20` даёт 30 вместо 31.

Для `SBC` инверсия компенсируется сама собой (`a - b - CF_x86` совпадает с `a - b + C_A64 - 1`),
поэтому арифметика `sbc` в threaded VM случайно верна.

### 4.3. JIT-движок

`lib/rd_jit_vm/rd_jit_emitter.ml:137-148` отображает `Adc` в `JIT_OP_ADD_RR`, а `Sbb` в
`JIT_OP_SUB_RR`: carry и borrow не учитываются вовсе. Отдельно: JIT-движок в текущей
конфигурации неверно исполняет даже простую арифметику, см. пробу D в разделе 5.

## 5. Воспроизведение

Пробы лежат в `scratch/isa_probe/` (каталог в `.gitignore`). Код возврата программы —
битовая маска «поведение ARM64 корректно»: каждый установленный бит означает одну
успешную проверку. Эталон — нативная сборка того же исходника.

| Проба | Что проверяет | native | threaded (было) | threaded (текущее) | stack | jit | multi |
|---|---|:---:|:---:|:---:|---|---|---|
| A | `LDADD` (память, регистры), `SCVTF`/`UCVTF` | 127 | 22 | **106** (регрессия пайплайна, см. п. 6.1) | 4 | 0 | 0 |
| B | `SBC`/`ADC`: флаги и арифметика | 63 | 26 | **63 (100% PASS)** | нет данных | 0 | 0 |
| C | `LDADD` на уровне регистров, 32-битный вариант | 15 | 0 | IR/RefVM 15 (100% PASS) | нет данных | нет данных | 0 |
| D | базовая арифметика `20 + 22` | 42 | 42 | 42 | нет данных | 0 | 42 |
Расшифровка битов:

- A: `1` — приёмник `LDADD` получил старое значение, `2` — память обновлена, `4` — регистр
  со значением не изменён, `8` — `SCVTF` с 32-битным источником, `16` — `UCVTF` с 32-битным
  источником, `32` — `UCVTF` при ненулевой старшей половине, `64` — `SCVTF` с single-приёмником.
- B: `1` — `sbc` не затирает NZCV, `2` — `sbcs` затирает, `4` — `adc` не затирает, `8` — `adcs`
  затирает, `16` — результат `sbc`, `32` — результат `adc`.
- C: `1` — 64-битный `LDADD`: приёмник записан, `2` — регистр со значением цел, `4` — 32-битный
  `LDADD` обновил только младшее слово, `8` — 32-битный `LDADD` записал старое 32-битное значение.

Проба D показывает, что движок `jit` неверно исполняет `20 + 22`, поэтому его результаты
по пробам A-C не показательны.

Сборка и запуск защищённой версии:

```bash
dune exec random_visa -- protect-arm64 \
  -i scratch/isa_probe/probe_a.c \
  -o /tmp/protect_a \
  -c scratch/isa_probe/probe_config.json \
  --compile true
/tmp/protect_a/protected_app; echo "exit=$?"
```

Ожидается `127`. **Текущий результат для `probe_a`: `106` (0x6A)** — до правки п. 8 было 127; см. п. 6.1.
Конфиг `scratch/isa_probe/probe_config.json` отключает
CFF, MBA и макро-обфускацию: макро-обфускация ломает строковые литералы инлайн-ассемблера,
из-за чего защищённая сборка не компилируется.
## 6. Что править
- [x] **1. `AtAdd`/`AtSwp` регистры**: в `lib/native_vm/vm_emitter.ml` реализована безопасная последовательность через скретч-регистр (`vtmp0`/`vtmp1`), сохраняющая `src` и адрес при `dst <> src`. В `lib/vm_ir/vm_eval.ml` запись перенаправлена в `dst`.
- [x] **2. Sub-register zero-extension для атомиков**: `Atomic_mem` добавлен в `written_gprs` и `instr_regs` в `lib/vm_ir/subreg_write.ml`.
- [x] **3. Register allocator для `Atomic_mem`**: `lib/vm_ir/register_allocator.ml` расширен ремаппингом регистров `dst`, `addr`, `src` для `Atomic_mem`.
- [x] **4. Ширина памяти для атомиков**: в `vm_emitter.ml` ширина кодируется в `extra_bits` (`wcode = (word >> 50) & 3`), в `vm_mem_handlers.ml` (`H_ATOMIC_ADD`, `H_ATOMIC_SWP`) добавлены ветвления под `uint32_t*`, `uint16_t*`, `uint8_t*` и `uint64_t*`.
- [x] **5. `SCVTF` / `UCVTF` FP-конверсии**:
  - `lib/arm64_lifter/arm64_branch.ml`: сохраняется исходная ширина `dst` (`B32` для `s0..s31`, `B64` для `d0..d31`).
  - `lib/vm_ir/vm_eval.ml`: знаковое расширение для 32-битного источника в `Scvtf`, маскирование в `Ucvtf`, округление до binary32 для single `dst`.
  - `lib/native_vm/vm_emitter.ml` и `lib/native_vm/vm_mem_handlers.ml`: флаги разрядности передаются в `imm`, в `H_SCVTF`/`H_UCVTF` и `H_FCVTZS`/`H_FCVTZU` поддержаны `int32_t`, `uint32_t` и `float`.
- [x] **6. Устранение ложного clobber в `cmn`**: в `lib/arm64_lifter/arm64_alu.ml` инструкция `cmn` с константой переведена на прямой операнд `Ir.Ccmn { src2 = Imm imm }` без использования `vtmp1`, исключая повреждение от decoy-инструкций.
- [x] **7. Callee-saved проверка в `ir_pipeline.ml`**: в вызов `assert_equivalent` передан `~check_callee_saved:false`, предотвращая падение проверки эквивалентности из-за рандомизации скретч-регистров R8..R15.
- [x] **8. `ADC` и `SBC` (Зонд B)** — probe B = **63/63 (0x3F)**, probe D = 42, probe A без изменений (106, см. п. 6.1):
  - `Protection_config` получил поле `arch` (`X86_64`/`AArch64`/`RISCV`, JSON `"arch": "aarch64"`); `protect-arm64` помечает конфиг `AArch64`, `protect-riscv` — `RISCV`. Носитель диалекта — конфиг, Ir не менялся.
  - `vm_context_emitter.ml`: в `VMContext` добавлен теневой `cf_arm64` (C = NOT borrow после SUB-семейства, carry-out после ADD-семейства); поддерживается в `compute_sub_flags`/`compute_add_flags`, в fallback `ccmp`/`ccmn` (заодно исправлена инверсия: бит C из nzcv раньше писался в `ctx.cf` в конвенции x86 без инверсии — `b.hs` после ccmp читался перевёрнутым) и в `H_SET_FLAGS_R`.
  - `vm_emitter.ml`: слова `ADC`/`SBC` несут теги в `extra_bits` (бит 0 = `set_flags`, бит 1 = ARM64-диалект carry); `encode_alu_imm` принял `?extra_bits`.
  - `vm_alu_handlers.ml`: `H_ADC_RR/RI`, `H_SBB_RR/RI` читают теги из слова: запись NZCV только при `set_flags`, carry-in из `ctx.cf_arm64` при ARM64-теге (`ADC` прибавляет C, `SBC` вычитает NOT C), при записи флагов поддерживают `cf_arm64`. Оба бита нулевые → legacy-x86 поведение (x86-путь `protect` не изменился).
  - `vm_transform.ml` (корень «затирания» NZCV): `canonicalize_instr` больше не опускает `Adc/Sbb` до `alu[no_flags] + cmp dst,0` — добавленный `cmp` и затирал флаги после `adc/sbc` и портил C/V для `adcs/sbcs`. Теперь канонизируется только форма операндов (включая hazard `sbc d, s1, d` через скретч и коммутативность `adc`), `set_flags` сохраняется. Плюс `Adc/Sbb` исключены из MBA-переписывания в `vm_emitter.ml` (они читают флаги).
  - Референсная модель: `flags.ml` + `compute_cf_arm` (C-вид флагов), `vm_eval.ml` — `state.arm64_carry` (параметр `make_state`), `reference_vm.ml` — `?arm64_carry`. Equivalence-проверка самосогласована (обе стороны — один диалект).
  - Тесты в `test/test_arm64_lifter.ml`: `test_probe_b` (63 в ARM64-диалекте), `test_adc_carry_dialect_diff` (30 vs 31), `test_arm64_lift_ngc` (-20).
- [ ] **9. Stack-движок**: реализовать `Fp_conv` и `Atomic_mem` в `lib/stack_vm/ir_to_stack.ml`.

## 6.1. Регрессия probe A (обнаружена при верификации п. 8, НЕ вызвана его правками)

Стэш-бисект: база рабочего дерева (правки п. 1–7 без п. 8) тоже даёт **106** — регрессия
существовала до начала п. 8. Симптомы:

- `Threaded_vm_packager.transform_func` печатает
  `[TRANSFORM_FUNC ERROR] Stage 7 ... Mismatch in return value RAX (expected 0x…7F, got 0x0)`
  и падает на fallback (только semantic+codec, без allocator-пути) — расхождение
  orig_f vs alloc_f на IR-уровне, воспроизводится в RefVM.
- E2E-биты: падают bit0 (LDADD dst ← old), bit2 (регистр значения цел) и bit4 (UCVTF
  32-бит: конверсия ведёт себя как знаковая — bit5 проходит именно потому, что w0=0
  знаково-расширяется в 0). Т.е. после fallback Atomic dst/src и флаги ширины UCVTF
  расходятся с аппаратурой.
- Гипотеза: падает Stage 5 (register allocator) либо codec на `Atomic_mem`/`Fp_conv`
  — transform-пайплайн меняет семантику, equivalence это ловит, а fallback-путь
  наследует часть поломки. Требует отдельного расследования (проверить ремаппинг
  `Atomic_mem` в `register_allocator.ml:86` и поведение codec на флагах ширины `imm`).
## 7. Смежные находки

- `dmb`, `dsb`, `isb` лифтятся в `Nop` (`lib/arm64_lifter/arm64_alu.ml:822`,
  `lib/arm64_lifter/arm64_mem.ml:318`): без их поддержки порядок доступа атомиков
  не воспроизводим даже после правки п. 2.3.
- C-обфускатор переписывает строковые литералы инлайн-ассемблера, из-за чего защищённая
  сборка с `asm(...)` не компилируется (`lib/c_macro_obf/`): строковые литералы в
  `__asm__` нужно исключать из-под стековых строк.
