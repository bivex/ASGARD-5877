# Архитектурная спецификация: Stack-VM Execution Engine для ASGARD-5877

Настоящий документ определяет математическую модель, формальную спецификацию в **Z-нотации (ISO/IEC 13568:2002)**, алгоритмы трансформации, спецификацию промежуточного представления (IR), механизм потокового шифрования и пошаговый план реализации **стековой виртуальной машины (Stack-VM)** в составе фреймворка ASGARD-5877.

---

## 1. Концепция и цели Stack-VM в ASGARD-5877

В текущей архитектуре ASGARD-5877 используется высокопроизводительный **3-адресный регистровый IR** (`Ir.Alu`, `Ir.Mem`, `Ir.Control`), оптимизированный под компиляторные трансформации, MBA-обфускацию и RD-JIT.

Включение **Stack-VM** в качестве альтернативного или гибридного исполнительного бэкенда решает следующие задачи защиты:

1. **Разрушение графа потока данных (Dataflow Oblivion):**
   - В 3-адресном коде зависимости между регистрами явные (цепочки def-use).
   - В стековой машине операнды передаются неявно через вершину стека (`VSP`), уничтожая явные регистровые ассоциации в статических декомпиляторах (IDA Pro, Ghidra).
2. **Сведение булевой логики к универсальным базисам (Universal Logic Reduction):**
   - Устранение дискретных хендлеров `AND`, `OR`, `XOR`, `NOT` за счет канонической редукции к элементам Шеффера (`NAND`) или стрелке Пирса (`NOR`).
3. **Потоковое связывание ключей байткода (Rolling Cryptor Chaining):**
   - Каждый байт или слово байткода расшифровывается динамическим ключом, зависящим от предыстории выполнения (stateful rolling key), что препятствует линейному статическому дизассемблированию байткода.
4. **Диспетчеризация без фиксированной таблицы переходов (Relative-Delta Threading):**
   - Отсутствие открытого массива указателей на хендлеры; переход осуществляется накапливаемым смещением относительно предыдущего хендлера.

---

## 2. Формальная модель исполнения (Formal Machine State)

Состояние виртуальной машины описывается кортежем:
$$\mathcal{S}_{\mathrm{SVM}} = \langle \mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VDISP}, \mathcal{M}_{\mathrm{stack}}, \mathcal{C}_{\mathrm{ctx}}, \mathcal{F}_{\mathrm{flags}} \rangle$$

где:
- **$\mathrm{VIP}$ (Virtual Instruction Pointer):** Физический регистр, указывающий на текущую позицию в шифрованном потоке байткода.
- **$\mathrm{VSP}$ (Virtual Stack Pointer):** Физический регистр, указывающий на вершину стека вычислений в памяти.
- **$\mathrm{VKEY}$ (Dynamic Decryption Key):** Регистр состояния криптора, модифицируемый на каждом шаге выборки инструкции.
- **$\mathrm{VDISP}$ (Handler Base / Dispatch Cursor):** Базовый указатель для косвенного перехода на следующий хендлер.
- **$\mathcal{M}_{\mathrm{stack}}$:** Память стека выполнения (локальный фрейм).
- **$\mathcal{C}_{\mathrm{ctx}}$:** Контекстный массив слотов (Context Frame), сохраняющий состояние нативных регистров целевой архитектуры (x86_64 / AArch64 / RV64).
- **$\mathcal{F}_{\mathrm{flags}}$:** Регистр флагов (или отложенное состояние флагов на вершине стека).

### Инвариант баланса стека
Для любого базового блока $B$:
$$\Delta \mathrm{VSP}(B) = \sum_{i \in B} \mathrm{push\_weight}(i) - \sum_{i \in B} \mathrm{pop\_weight}(i)$$
На границах базовых блоков глубина стека $\mathrm{depth}(\mathrm{VSP})$ должна быть детерминирована для обеспечения корректности слияния потоков управления (join points).

---

## 3. Формальная спецификация в Z-нотации (Z Notation Specification)

Спецификация представлена в канонической нотации стандарта **ISO/IEC 13568:2002 Z** с использованием схемного исчисления (Schema Calculus).

### 3.1 Базовые типы, множества и операторы

```z
[ADDR, WORD, BYTE, REG_ID]

VAL == WORD
FLAGS == WORD
OFFSET == ℤ

WORD_SIZE == 8
MAX_STACK_DEPTH : ℕ
ACTIVE_REGS : ℙ REG_ID

nor : VAL × VAL → VAL
nand : VAL × VAL → VAL
add_with_flags : VAL × VAL → VAL × FLAGS
sub_with_flags : VAL × VAL → VAL × FLAGS
decrypt_byte : BYTE × WORD → BYTE
derive_key : WORD × BYTE → WORD
read_word_mem : (ADDR ⇸ BYTE) × ADDR → VAL
write_word_mem : (ADDR ⇸ BYTE) × ADDR × VAL → (ADDR ⇸ BYTE)
```

---

### 3.2 Схема состояния виртуальной машины: $StackVMState$

```z
┌─ StackVMState ──────────────────────────────────────────
│  vip : ADDR
│  vsp : ADDR
│  vkey : WORD
│  vdisp : ADDR
│  vstack : seq VAL
│  vctx : REG_ID ⇸ VAL
│  vmem : ADDR ⇸ BYTE
│  flags : FLAGS
├─────────────────────────────────────────────────────────
│  #vstack ≤ MAX_STACK_DEPTH
│  vsp mod WORD_SIZE = 0
│  dom vctx = ACTIVE_REGS
└─────────────────────────────────────────────────────────
```

**Предикаты инварианта:**
1. $|\mathrm{vstack}| \le \mathrm{MAX\_STACK\_DEPTH}$ — виртуальный стек строго ограничен для предотвращения переполнения памяти.
2. $\mathrm{vsp} \bmod \mathrm{WORD\_SIZE} = 0$ — аппаратный указатель стека строго выровнен по 8-байтовой границе.
3. $\operatorname{dom} \mathrm{vctx} = \mathrm{ACTIVE\_REGS}$ — все активные регистры архитектуры замаплены во фрейме контекста.

---

### 3.3 Начальное состояние: $InitStackVMState$

```z
┌─ InitStackVMState ──────────────────────────────────────
│  StackVMState'
│  entry? : ADDR
│  init_sp? : ADDR
│  seed_key? : WORD
│  base_disp? : ADDR
│  init_ctx? : REG_ID → VAL
│  init_mem? : ADDR ⇸ BYTE
├─────────────────────────────────────────────────────────
│  vip' = entry?
│  vsp' = init_sp?
│  vkey' = seed_key?
│  vdisp' = base_disp?
│  vstack' = ⟨⟩
│  vctx' = init_ctx?
│  vmem' = init_mem?
│  flags' = 0
└─────────────────────────────────────────────────────────
```

---

### 3.4 Выборка инструкции и потоковая расшифровка: $FetchByte$

```z
┌─ FetchByte ─────────────────────────────────────────────
│  ΔStackVMState
│  plain! : BYTE
├─────────────────────────────────────────────────────────
│  vip ∈ dom vmem
│  plain! = decrypt_byte(vmem(vip), vkey)
│  vip' = vip + 1
│  vkey' = derive_key(vkey, plain!)
│  vsp' = vsp
│  vdisp' = vdisp
│  vstack' = vstack
│  vctx' = vctx
│  vmem' = vmem
│  flags' = flags
└─────────────────────────────────────────────────────────
```

---

### 3.5 Операционные схемы инструкций ($\Delta StackVMState$)

#### Операция $PushImm$ (Помещение константы):
```z
┌─ PushImm ───────────────────────────────────────────────
│  ΔStackVMState
│  imm? : VAL
├─────────────────────────────────────────────────────────
│  #vstack < MAX_STACK_DEPTH
│  vstack' = ⟨imm?⟩ ⌢ vstack
│  vsp' = vsp - WORD_SIZE
│  vctx' = vctx
│  vmem' = vmem
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
│  flags' = flags
└─────────────────────────────────────────────────────────
```

#### Операция $PushReg$ (Чтение регистра контекста):
```z
┌─ PushReg ───────────────────────────────────────────────
│  ΔStackVMState
│  r? : REG_ID
├─────────────────────────────────────────────────────────
│  r? ∈ dom vctx
│  #vstack < MAX_STACK_DEPTH
│  vstack' = ⟨vctx(r?)⟩ ⌢ vstack
│  vsp' = vsp - WORD_SIZE
│  vctx' = vctx
│  vmem' = vmem
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
│  flags' = flags
└─────────────────────────────────────────────────────────
```

#### Операция $PopReg$ (Запись в контекстный слот):
```z
┌─ PopReg ────────────────────────────────────────────────
│  ΔStackVMState
│  r? : REG_ID
├─────────────────────────────────────────────────────────
│  r? ∈ dom vctx
│  vstack ≠ ⟨⟩
│  vctx' = vctx ⊕ { r? ↦ head(vstack) }
│  vstack' = tail(vstack)
│  vsp' = vsp + WORD_SIZE
│  vmem' = vmem
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
│  flags' = flags
└─────────────────────────────────────────────────────────
```

#### Операция $ExecNor$ (Логический элемент Пирса):
```z
┌─ ExecNor ───────────────────────────────────────────────
│  ΔStackVMState
├─────────────────────────────────────────────────────────
│  #vstack ≥ 2
│  let a == vstack(1) ∧ b == vstack(2) •
│    vstack' = ⟨nor(a, b)⟩ ⌢ tail(tail(vstack))
│  vsp' = vsp + WORD_SIZE
│  vctx' = vctx
│  vmem' = vmem
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
│  flags' = flags
└─────────────────────────────────────────────────────────
```

#### Операция $ExecAdd$ (Сложение с генерацией флагов):
```z
┌─ ExecAdd ───────────────────────────────────────────────
│  ΔStackVMState
├─────────────────────────────────────────────────────────
│  #vstack ≥ 2
│  let a == vstack(1) ∧ b == vstack(2) •
│    let (res, new_flags) == add_with_flags(a, b) •
│      vstack' = ⟨res⟩ ⌢ tail(tail(vstack)) ∧
│      flags' = new_flags
│  vsp' = vsp + WORD_SIZE
│  vctx' = vctx
│  vmem' = vmem
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
└─────────────────────────────────────────────────────────
```

#### Операция $ExecDup$ (Дублирование вершины):
```z
┌─ ExecDup ───────────────────────────────────────────────
│  ΔStackVMState
├─────────────────────────────────────────────────────────
│  vstack ≠ ⟨⟩
│  #vstack < MAX_STACK_DEPTH
│  vstack' = ⟨head(vstack)⟩ ⌢ vstack
│  vsp' = vsp - WORD_SIZE
│  vctx' = vctx
│  vmem' = vmem
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
│  flags' = flags
└─────────────────────────────────────────────────────────
```

#### Операция $ExecSwap$ (Перестановка двух верхних элементов):
```z
┌─ ExecSwap ──────────────────────────────────────────────
│  ΔStackVMState
├─────────────────────────────────────────────────────────
│  #vstack ≥ 2
│  vstack' = ⟨vstack(2), vstack(1)⟩ ⌢ tail(tail(vstack))
│  vsp' = vsp
│  vctx' = vctx
│  vmem' = vmem
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
│  flags' = flags
└─────────────────────────────────────────────────────────
```

#### Операция $ExecReadMem$ (Косвенное чтение из памяти):
```z
┌─ ExecReadMem ───────────────────────────────────────────
│  ΔStackVMState
├─────────────────────────────────────────────────────────
│  vstack ≠ ⟨⟩
│  let addr == head(vstack) •
│    vstack' = ⟨read_word_mem(vmem, addr)⟩ ⌢ tail(vstack)
│  vsp' = vsp
│  vctx' = vctx
│  vmem' = vmem
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
│  flags' = flags
└─────────────────────────────────────────────────────────
```

#### Операция $ExecWriteMem$ (Запись слова в память):
```z
┌─ ExecWriteMem ──────────────────────────────────────────
│  ΔStackVMState
├─────────────────────────────────────────────────────────
│  #vstack ≥ 2
│  let addr == vstack(1) ∧ val == vstack(2) •
│    vmem' = write_word_mem(vmem, addr, val)
│  vstack' = tail(tail(vstack))
│  vsp' = vsp + (2 * WORD_SIZE)
│  vctx' = vctx
│  vkey' = vkey
│  vip' = vip
│  vdisp' = vdisp
│  flags' = flags
└─────────────────────────────────────────────────────────
```

#### Операция $ExecDispatchRel$ (Относительное смещение диспетчера):
```z
┌─ ExecDispatchRel ───────────────────────────────────────
│  ΔStackVMState
│  δ? : OFFSET
├─────────────────────────────────────────────────────────
│  vdisp' = vdisp + δ?
│  vip' = vip
│  vsp' = vsp
│  vkey' = vkey
│  vstack' = vstack
│  vctx' = vctx
│  vmem' = vmem
│  flags' = flags
└─────────────────────────────────────────────────────────
```

---

### 3.6 Теорема сохранения инварианта стека базового блока

Пусть базовый блок $B$ задан последовательной композицией операций:
$$\mathcal{T}_B = \mathcal{O}_1 \mathbin{\mathbf{;}} \mathcal{O}_2 \mathbin{\mathbf{;}} \dots \mathbin{\mathbf{;}} \mathcal{O}_n$$

$$\mathbf{Theorem} ~ (\text{Stack Conservation}) \bullet \\
\forall s : StackVMState \bullet \\
\quad (\Delta \mathrm{VSP}(B) = 0 \land s \in \operatorname{dom} \mathcal{T}_B) \implies |\mathcal{T}_B(s).\mathrm{vstack}| = |s.\mathrm{vstack}| \land \mathcal{T}_B(s).\mathrm{vsp} = s.\mathrm{vsp}$$

*Следствие:* При нулевом балансе блока $\Delta \mathrm{VSP}(B) = 0$ переходы по ветвлениям и циклам гарантированно не приводят к утечке или деградации виртуального стека.

---

## 4. Набор инструкций Stack-ISA

| Опкод | Мнемоника | Действие над стеком | Описание |
| :--- | :--- | :--- | :--- |
| `0x01` | `PUSH_IMM` | $(\epsilon \to v)$ | Расшифровка $imm$ из байткода и push на VSP |
| `0x02` | `PUSH_REG` | $(\epsilon \to \mathcal{C}[idx])$ | Чтение регистра из контекстного фрейма на VSP |
| `0x03` | `POP_REG` | $(v \to \epsilon)$ | Снятие значения с VSP и запись в слот $\mathcal{C}[idx]$ |
| `0x04` | `READ_MEM` | $(addr \to value)$ | Чтение значения из физической памяти по адресу со стека |
| `0x05` | `WRITE_MEM` | $(addr, value \to \epsilon)$ | Запись значения в физическую память |
| `0x06` | `ADD` | $(a, b \to a + b, flags)$ | Сложение двух элементов с выталкиванием флагов |
| `0x07` | `SUB` | $(a, b \to a - b, flags)$ | Вычитание |
| `0x08` | `NOR` | $(a, b \to \neg(a \lor b), flags)$ | Базовый логический элемент (Стрелка Пирса) |
| `0x09` | `NAND` | $(a, b \to \neg(a \land b), flags)$ | Альтернативный базис (Штрих Шеффера) |
| `0x0A` | `SHL` / `SHR` | $(val, count \to res, flags)$ | Логические сдвиги |
| `0x0B` | `DUP` | $(a \to a, a)$ | Дублирование вершины стека |
| `0x0C` | `SWAP` | $(a, b \to b, a)$ | Перестановка двух верхних элементов |
| `0x0D` | `POP_FLAGS` | $(flags \to \epsilon)$ | Восстановление регистра флагов процессора со стека |
| `0x0E` | `PUSH_FLAGS`| $(\epsilon \to flags)$ | Сохранение текущего нативного флагового регистра на стек |
| `0x0F` | `JMP_REL` | $(\epsilon \to \epsilon)$ | Коррекция VIP на относительное смещение |
| `0x10` | `JCC_REL` | $(cond \to \epsilon)$ | Условный переход по состоянию вершины стека |
| `0x11` | `VM_EXIT` | $(\epsilon \to \epsilon)$ | Восстановление контекста и выход в нативный код |

---

## 5. Алгоритмы компиляции и трансформации

### Алгоритм 1. Понижение (Lowering) 3-адресного IR в Stack-VM

Трансляция трехадресной инструкции вида `dst = op(src1, src2)` в последовательность стековых команд:

```
Функция LowerToStack(Instr):
  1. Вход: Instr(dst, op, src1, src2)
  2. Если src2 — Константа(c):
       Emit(PUSH_IMM, c)
     Иначе:
       Emit(PUSH_REG, ContextSlot(src2))

  3. Если src1 — Константа(c):
       Emit(PUSH_IMM, c)
     Иначе:
       Emit(PUSH_REG, ContextSlot(src1))

  4. Если op ∈ {Add, Sub, Mul}:
       Emit(TranslateAluOp(op))
     Иначе если op ∈ {And, Or, Xor, Not}:
       EmitUniversalLogic(op)

  5. Если Instr производит результат:
       Emit(POP_REG, ContextSlot(dst))
     Если Instr обновляет флаги:
       Emit(POP_FLAGS)
```

---

### Алгоритм 2. Декомпозиция логики в универсальный базис NOR / NAND

Любая булева функция представляется исключительно через операции `NOR` ($\downarrow$):

1. **Инверсия $\mathrm{NOT}(x)$:**
   $$\neg x \equiv x \downarrow x$$
   *Стековый шаблон:*
   ```
   DUP
   NOR
   ```

2. **Дизъюнкция $\mathrm{OR}(x, y)$:**
   $$x \lor y \equiv (x \downarrow y) \downarrow (x \downarrow y)$$
   *Стековый шаблон:*
   ```
   NOR
   DUP
   NOR
   ```

3. **Конъюнкция $\mathrm{AND}(x, y)$:**
   $$x \land y \equiv (\neg x) \downarrow (\neg y) \equiv (x \downarrow x) \downarrow (y \downarrow y)$$
   *Стековый шаблон:*
   ```
   SWAP
   DUP
   NOR        ; вычислен NOT(y)
   SWAP
   DUP
   NOR        ; вычислен NOT(x)
   NOR        ; NOT(x) NOR NOT(y) == x AND y
   ```

4. **Исключающее ИЛИ $\mathrm{XOR}(x, y)$:**
   $$x \oplus y \equiv (x \land \neg y) \lor (\neg x \land y)$$
   Через базис Пирса:
   $$x \oplus y = ((x \downarrow y) \downarrow (x \downarrow x)) \downarrow ((x \downarrow y) \downarrow (y \downarrow y))$$

*Эффект защиты:* Автоматический декомпилятор больше не видит опкодов `and/or/xor`. Все операции выглядят одинаково: вызовы одного и того же хендлера `NOR` с разным порядком перестановки стека.

---

### Алгоритм 3. Потоковое шифрование байткода (Rolling-Key Decryption)

Байткод защищается адаптивным потоковым шифром. Каждая операция чтения байта/слова выполняет параллельную модификацию ключа.

```
Структура шага выборки (Fetch-Decode Step):
  1. raw_byte = Memory[VIP]
  2. VIP = VIP + 1
  3. plain_byte = raw_byte ⊕ VKEY
  4. VKEY = RotL(VKEY, 3) + plain_byte ⊕ 0x5A
  5. Возврат plain_byte
```

#### Межблочная синхронизация ключей (Key Reconciliation)
Если в точку слияния потока управления $B_{\mathrm{join}}$ сходятся два ребра $B_1 \to B_{\mathrm{join}}$ и $B_2 \to B_{\mathrm{join}}$, финальные ключи $\mathrm{VKEY}(B_1)$ и $\mathrm{VKEY}(B_2)$ могут различаться.
- **Решение:** На исходящем ребре $B_2 \to B_{\mathrm{join}}$ вставляется компенсационный переходной хендлер (`KEY_ADJUST`), корректирующий ключ:
  $$\mathrm{VKEY}_{\mathrm{target}} = \mathrm{VKEY}_{\mathrm{current}} \oplus \Delta_{\mathrm{block}}$$

---

### Алгоритм 4. Относительная бестабличная диспетчеризация (Relative-Delta Dispatching)

Вместо фиксированной таблицы хендлеров каждый хендлер завершается эпилогом, использующим относительные смещения:

```x86asm
; Хендлер N (эпилог)
; VIP указывает на следующий зашифрованный байт смещения delta
movzx eax, byte ptr [VIP]
add   VIP, 1
xor   eax, VKEY               ; расшифровка delta
add   VKEY, eax               ; обновление ключа
add   VDISP, eax              ; VDISP = VDISP + delta
jmp   VDISP                   ; прыжок на следующий полиморфный хендлер
```

- В скомпилированном бинарнике полностью отсутствует массив указателей на хендлеры VM.
- Хендлеры расположены в случайных позициях исполняемой секции со случайным паддингом (junk code).
- Восстановление графа переходов VM статическими сигнатурными методами невозможно.

---

## 6. Генерация полиморфного рантайма (Runtime Synthesizer)

При каждой компиляции защищаемого модуля:

1. **Случайное распределение ролей регистров:**
   Для каждой архитектуры случайно выбираются непересекающиеся регистры:
   - x86-64: $\{\mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VDISP}\} \subset \{\mathrm{RAX}, \mathrm{RBX}, \mathrm{RCX}, \mathrm{RDX}, \mathrm{RSI}, \mathrm{RDI}, \mathrm{R8}..\mathrm{R15}\}$
   - AArch64: $\{\mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VDISP}\} \subset \{\mathrm{X19}..\mathrm{X28}\}$
   - RV64: $\{\mathrm{VIP}, \mathrm{VSP}, \mathrm{VKEY}, \mathrm{VDISP}\} \subset \{\mathrm{s1}..\mathrm{s11}\}$
2. **Перемешивание порядка контекстного фрейма:**
   Смещение нативного регистра $R_k$ в массиве $\mathcal{C}[R_k]$ задается случайной перестановкой $\pi \in S_N$.
3. **Генерация тела хендлеров:**
   Внутрь каждого хендлера подмешиваются эквивалентные мутации:
   - Замена `add a, b` на `sub a, -b` или серию инструкций LEA.
   - Вставка opaque predicates, устойчивых к мертвому коду.

---

## 7. Пошаговый план внедрения (TODO) в ASGARD-5877

### Фаза 1: Промежуточное представление и парсер (Stack-IR)
- [ ] **1.1 Определение типа Stack-IR в OCaml:**
  Создать модуль `lib/stack_ir.ml`:
  - Тип `stack_op = PushImm of int64 | PushReg of int | PopReg of int | ReadMem of int | WriteMem of int | Nor | Nand | Add | Sub | Dup | Swap | JmpRel of int | JccRel of int * condition | Exit`
  - Сериализатор / десериализатор для отладки.
- [ ] **1.2 Транслятор `lib/ir_to_stack.ml`:**
  - Реализовать трансляцию из 3-адресного `Ir.t` в `Stack_ir.t`.
  - Реализовать распределение слотов контекста `Context_allocator`.
  - Покрыть юнит-тестами эквивалентность вычислений.

### Фаза 2: Оптимизации и обфусцирующие пассы
- [ ] **2.1 Пасс редукции булевой логики (`lib/stack_logic_pass.ml`):**
  - Подстановка эквивалентов NOR/NAND для всех логических операций.
  - Рандомизация выбора базиса: для одних блоков выбирать NOR-базис, для других — NAND-базис.
- [ ] **2.2 Пасс выравнивания стека (Stack Balance Verification):**
  - Проверка инварианта $\Delta \mathrm{VSP} = 0$ на выходах блоков.
  - Автоматическая вставка `POP_DUMMY` / сброса мусора при несовпадении высоты стека.

### Фаза 3: Генерация байткода и криптор
- [ ] **3.1 Модуль `lib/stack_encoder.ml`:**
  - Реализация rolling-key генератора.
  - Двунаправленный расчет ключей: генерация прямого кода шифрования и расчет дельт для межблочных переходов (`KEY_ADJUST`).
- [ ] **3.2 Упаковщик байткода:**
  - Упаковка опкодов и констант переменной длины (LEB128 или префиксное сжатие).

### Фаза 4: Синтезатор рантайма под целевые платформы
- [ ] **4.1 Генератор хендлеров для x86-64 (`lib/stack_jit_x86.ml`):**
  - Синтез входного стаба `vm_enter` (push context, init VSP/VIP/VKEY/VDISP).
  - Синтез хендлеров `PUSH_REG`, `POP_REG`, `NOR`, `ADD`, `READ_MEM`, `WRITE_MEM`.
  - Синтез относительного эпилога диспетчеризации (`add VDISP, delta; jmp VDISP`).
  - Синтез стаба `vm_exit`.
- [ ] **4.2 Генератор хендлеров для AArch64 (`lib/stack_jit_arm64.ml`):**
  - Реализация аналогичных хендлеров с учетом архитектуры регистров ARM64 (SP alignment, STP/LDP).
- [ ] **4.3 Генератор хендлеров для RV64GCV (`lib/stack_jit_rv64.ml`):**
  - Реализация хендлеров под RISC-V.

### Фаза 5: Интеграция в общую экосистему ASGARD-5877
- [ ] **5.1 Многоуровневый выбор бэкенда (Multi-Tier VM Selector):**
  - Возможность для пользователя через аннотации / директивы компилятора помечать функции:
    - `@vm_tier("register")`: компиляция в существующую высокоскоростную 3-адресную VM (для нагруженных циклов, SIMD, криптографии).
    - `@vm_tier("stack")`: компиляция в Stack-VM с NOR-редукцией и rolling keys (для проверок лицензий, критических проверок целостности, защиты ключей).
- [ ] **5.2 Комплексное тестирование и бенчмаркинг:**
  - Тестирование стабильности на тестовом наборе `test/test_stack_vm.ml`.
  - Измерение оверхеда исполнения и стойкости против декомпиляторов (Ghidra, IDA).
