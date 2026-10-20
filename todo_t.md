# TODO: корректность виртуализации ARM64 LSE-атомиков, FP-конверсий и carry-арифметики

Дата: 2026-10-20. Обнаружено при проверке инструкций `LDADD`, `LDADDA`, `LDADDAL`,
`LDADDL`, `UCVTF`, `SCVTF`, `SBC` в ARM64-лифтере и виртуальных машинах.

Кратко: все семь мнемоник распознаются лифтером (lift проходит без ошибки
«Unsupported or invalid ARM64 instruction»), но семантика реализована не полностью.
Ниже по каждому пункту: где расходится с ARM64, как воспроизвести, какой файл править.

## 1. Сводка по движкам

| Инструкция | Лифтер | threaded (по умолчанию) | stack | jit | multi |
|---|---|---|---|---|---|
| `LDADD`, `LDADDA`, `LDADDAL`, `LDADDL` | `Ir.Atomic_mem AtAdd`, `lib/arm64_lifter/arm64_mem.ml:222` | неверно | неверно | не применимо, см. п. 4.3 | неверно |
| `UCVTF` | `Ir.Fp_conv Ucvtf`, `lib/arm64_lifter/arm64_branch.ml:182` | неверно для 32-битного источника | выбрасывается | выбрасывается | выбрасывается |
| `SCVTF` | `Ir.Fp_conv Scvtf`, `lib/arm64_lifter/arm64_branch.ml:180` | неверно | выбрасывается | выбрасывается | выбрасывается |
| `SBC` | `Ir.Alu Sbb`, `lib/arm64_lifter/arm64_alu.ml:188` | неверно: затирает NZCV | неверно: затирает NZCV | неверно | неверно: затирает NZCV |

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

| Проба | Что проверяет | native | threaded | stack | jit | multi |
|---|---|---|---|---|---|---|
| A | `LDADD` (память, регистры), `SCVTF`/`UCVTF` | 127 | 22 | 4 | 0 | 0 |
| B | `SBC`/`ADC`: флаги и арифметика | 63 | 26 | нет данных | 0 | 0 |
| C | `LDADD` на уровне регистров, 32-битный вариант | 15 | 0 | нет данных | нет данных | 0 |
| D | базовая арифметика `20 + 22` | 42 | 42 | нет данных | 0 | 42 |

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

Ожидается `127`, фактически `22`. Конфиг `scratch/isa_probe/probe_config.json` отключает
CFF, MBA и макро-обфускацию: макро-обфускация ломает строковые литералы инлайн-ассемблера,
из-за чего защищённая сборка не компилируется.

## 6. Что править

1. `lib/vm_ir/ir.ml`: расширить `Atomic_mem` отдельными полями `value_reg`, `result_reg`,
   `width`, `ordering` вместо переиспользования `src`/`dst` под две разные конвенции.
2. `lib/native_vm/vm_emitter.ml:806-817` и `lib/native_vm/vm_mem_handlers.ml:1490-1596`:
   кодировать и исполнять RMW с корректным приёмником, с шириной B8/B16/B32/B64 и
   с порядком доступа из IR.
3. `lib/arm64_lifter/arm64_branch.ml:180-183`: сохранять ширину источника (`Gpr (n, B32)`)
   и приёмника (`Fpr (d, B32)` для single-формы).
4. `lib/native_vm/vm_mem_handlers.ml:1372-1425`: sign-extension для 32-битного источника
   в `SCVTF`, truncation в `UCVTF`, округление до binary32 для single-приёмника.
5. `lib/native_vm/vm_alu_handlers.ml`: разделить `ADC`/`SBB` на варианты «с флагами» и
   «без флагов», инвертировать carry для ARM64-конвенции.
6. `lib/stack_vm/ir_to_stack.ml:244-248`: реализовать `Fp_conv` и `Atomic_mem` либо
   диагностировать их отказ, а не выбрасывать молча.
7. `lib/rd_jit_vm/rd_jit_emitter.ml:137-148`: реализовать carry и borrow в JIT-опкодах.

## 7. Смежные находки

- `dmb`, `dsb`, `isb` лифтятся в `Nop` (`lib/arm64_lifter/arm64_alu.ml:822`,
  `lib/arm64_lifter/arm64_mem.ml:318`): без их поддержки порядок доступа атомиков
  не воспроизводим даже после правки п. 2.3.
- C-обфускатор переписывает строковые литералы инлайн-ассемблера, из-за чего защищённая
  сборка с `asm(...)` не компилируется (`lib/c_macro_obf/`): строковые литералы в
  `__asm__` нужно исключать из-под стековых строк.
