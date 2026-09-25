# Архитектурная спецификация: Stack-VM Execution Engine для ASGARD-5877

Настоящий документ определяет математическую модель, формальную спецификацию в **Z-нотации (Z Notation)**, алгоритмы трансформации, спецификацию промежуточного представления (IR), механизм потокового шифрования и пошаговый план реализации **стековой виртуальной машины (Stack-VM)** в составе фреймворка ASGARD-5877.

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
$$\mathcal{S}_{\text{SVM}} = \langle \text{VIP}, \text{VSP}, \text{VKEY}, \text{VDISP}, \mathcal{M}_{\text{stack}}, \mathcal{C}_{\text{ctx}}, \mathcal{F}_{\text{flags}} \rangle$$

где:
- **$\text{VIP}$ (Virtual Instruction Pointer):** Случайно назначенный физический регистр, указывающий на текущую позицию в шифрованном потоке байткода.
- **$\text{VSP}$ (Virtual Stack Pointer):** Физический регистр, указывающий на вершину стека вычислений в памяти.
- **$\text{VKEY}$ (Dynamic Decryption Key):** Регистр состояния криптора, модифицируемый на каждом шаге выборки инструкции.
- **$\text{VDISP}$ (Handler Base / Dispatch Cursor):** Базовый указатель для косвенного перехода на следующий хендлер.
- **$\mathcal{M}_{\text{stack}}$:** Память стека выполнения (локальный фрейм).
- **$\mathcal{C}_{\text{ctx}}$:** Контекстный массив слотов (Context Frame), сохраняющий состояние нативных регистров целевой архитектуры (x86_64 / AArch64 / RV64).
- **$\mathcal{F}_{\text{flags}}$:** Регистр флагов (или отложенное состояние флагов на вершине стека).

### Инвариант баланса стека
Для любого линейного участка (базового блока) $B$:
$$\Delta \text{VSP}(B) = \sum_{i \in B} \text{push\_weight}(i) - \sum_{i \in B} \text{pop\_weight}(i)$$
На границах базовых блоков глубина стека $\text{depth}(\text{VSP})$ должна быть детерминирована для обеспечения корректности слияния потоков управления (join points).

---

## 3. Формальная спецификация в Z-нотации (Z Notation Specification)

Для математически строгого доказательства корректности исполнения, отсутствия переполнения стека и детерминированности декриптора ниже приведена формальная модель Stack-VM на языке спецификаций **Z (ISO/IEC 13568:2002)**.

### 3.1 Базовые типы и множества (Given Sets & Basic Types)

$$[ADDR, WORD, BYTE, REG\_ID]$$

Определим производные числовые типы и константы:
$$VAL == WORD$$
$$FLAGS == WORD$$
$$OFFSET == \mathbb{Z}$$
$$\text{WORD\_SIZE} == 8$$
$$\text{MAX\_STACK\_DEPTH} : \mathbb{N}$$
$$\text{ACTIVE\_REGS} : \mathbb{P} ~ REG\_ID$$

Вспомогательные аксиоматические функции булевой логики и потокового шифрования:

$$\begin{array}{l}
nor : VAL \times VAL \to VAL \\
nand : VAL \times VAL \to VAL \\
add\_with\_flags : VAL \times VAL \to VAL \times FLAGS \\
sub\_with\_flags : VAL \times VAL \to VAL \times FLAGS \\
decrypt\_byte : BYTE \times WORD \to BYTE \\
derive\_key : WORD \times BYTE \to WORD \\
read\_word\_mem : (ADDR \pfun BYTE) \times ADDR \to VAL \\
write\_word\_mem : (ADDR \pfun BYTE) \times ADDR \times VAL \to (ADDR \pfun BYTE)
\end{array}$$

### 3.2 Схема состояния машины: $StackVMState$

Схема описывает полный инвариант архитектурного состояния Stack-VM:

$$\begin{array}{|l}
StackVMState \\
\hline
vip : ADDR \\
vsp : ADDR \\
vkey : WORD \\
vdisp : ADDR \\
vstack : \mathrm{seq} ~ VAL \\
vctx : REG\_ID \pfun VAL \\
vmem : ADDR \pfun BYTE \\
flags : FLAGS \\
\hline
\#vstack \le \text{MAX\_STACK\_DEPTH} \\
vsp \bmod \text{WORD\_SIZE} = 0 \\
\dom vctx = \text{ACTIVE\_REGS} \\
\end{array}$$

*Предикаты инварианта:*
1. Глубина виртуального стека $\#vstack$ строго ограничена сверху константой $\text{MAX\_STACK\_DEPTH}$.
2. Указатель аппаратного стека $vsp$ выровнен по 8-байтовой границе.
3. Домен отображения контекста $\dom vctx$ покрывает весь набор активных нативных регистров целевой платформы.

### 3.3 Начальное состояние: $InitStackVMState$

$$\begin{array}{|l}
InitStackVMState \\
\hline
StackVMState' \\
entry? : ADDR \\
init\_sp? : ADDR \\
seed\_key? : WORD \\
base\_disp? : ADDR \\
init\_ctx? : REG\_ID \fun VAL \\
init\_mem? : ADDR \pfun BYTE \\
\hline
vip' = entry? \\
vsp' = init\_sp? \\
vkey' = seed\_key? \\
vdisp' = base\_disp? \\
vstack' = \langle \rangle \\
vctx' = init\_ctx? \\
vmem' = init\_mem? \\
flags' = 0
\end{array}$$

---

### 3.4 Схема шага выборки и расшифровки: $FetchByte$

Операция выборки байта из памяти опкодов с параллельным обновлением ключа криптора:

$$\begin{array}{|l}
FetchByte \\
\hline
\Delta StackVMState \\
plain! : BYTE \\
\hline
vip \in \dom vmem \\
plain! = decrypt\_byte(vmem(vip), vkey) \\
vip' = vip + 1 \\
vkey' = derive\_key(vkey, plain!) \\
vsp' = vsp \\
vdisp' = vdisp \\
vstack' = vstack \\
vctx' = vctx \\
vmem' = vmem \\
flags' = flags
\end{array}$$

---

### 3.5 Операционные схемы инструкций ($\Delta StackVMState$)

#### Операция $PushImm$:
Помещение непосредственного операнда на вершину стека:

$$\begin{array}{|l}
PushImm \\
\hline
\Delta StackVMState \\
imm? : VAL \\
\hline
\#vstack < \text{MAX\_STACK\_DEPTH} \\
vstack' = \langle imm? \rangle \cat vstack \\
vsp' = vsp - \text{WORD\_SIZE} \\
vctx' = vctx \\
vmem' = vmem \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp \\
flags' = flags
\end{array}$$

#### Операция $PushReg$:
Чтение регистра из контекстного фрейма $\mathcal{C}$ и размещение на стеке:

$$\begin{array}{|l}
PushReg \\
\hline
\Delta StackVMState \\
r? : REG\_ID \\
\hline
r? \in \dom vctx \\
\#vstack < \text{MAX\_STACK\_DEPTH} \\
vstack' = \langle vctx(r?) \rangle \cat vstack \\
vsp' = vsp - \text{WORD\_SIZE} \\
vctx' = vctx \\
vmem' = vmem \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp \\
flags' = flags
\end{array}$$

#### Операция $PopReg$:
Извлечение значения с вершины стека и сохранение в контекстный слот:

$$\begin{array}{|l}
PopReg \\
\hline
\Delta StackVMState \\
r? : REG\_ID \\
\hline
r? \in \dom vctx \\
vstack \ne \langle \rangle \\
vctx' = vctx \oplus \{ r? \mapsto \head(vstack) \} \\
vstack' = \tail(vstack) \\
vsp' = vsp + \text{WORD\_SIZE} \\
vmem' = vmem \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp \\
flags' = flags
\end{array}$$

#### Операция $ExecNor$ (Стрелка Пирса):
Извлечение двух операндов, вычисление $\neg(a \lor b)$ и запись результата:

$$\begin{array}{|l}
ExecNor \\
\hline
\Delta StackVMState \\
\hline
\#vstack \ge 2 \\
\LET a == vstack(1) \semi b == vstack(2) \IN \\
\quad vstack' = \langle nor(a, b) \rangle \cat \tail(\tail(vstack)) \\
vsp' = vsp + \text{WORD\_SIZE} \\
vctx' = vctx \\
vmem' = vmem \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp \\
flags' = flags
\end{array}$$

#### Операция $ExecAdd$:
Сложение операндов с генерацией нативных флагов:

$$\begin{array}{|l}
ExecAdd \\
\hline
\Delta StackVMState \\
\hline
\#vstack \ge 2 \\
\LET a == vstack(1) \semi b == vstack(2) \IN \\
\quad (res, new\_flags) = add\_with\_flags(a, b) \\
\quad vstack' = \langle res \rangle \cat \tail(\tail(vstack)) \\
\quad flags' = new\_flags \\
vsp' = vsp + \text{WORD\_SIZE} \\
vctx' = vctx \\
vmem' = vmem \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp
\end{array}$$

#### Операция $ExecDup$:
Дублирование верхнего элемента стека:

$$\begin{array}{|l}
ExecDup \\
\hline
\Delta StackVMState \\
\hline
vstack \ne \langle \rangle \\
\#vstack < \text{MAX\_STACK\_DEPTH} \\
vstack' = \langle \head(vstack) \rangle \cat vstack \\
vsp' = vsp - \text{WORD\_SIZE} \\
vctx' = vctx \\
vmem' = vmem \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp \\
flags' = flags
\end{array}$$

#### Операция $ExecSwap$:
Перестановка двух верхних элементов:

$$\begin{array}{|l}
ExecSwap \\
\hline
\Delta StackVMState \\
\hline
\#vstack \ge 2 \\
vstack' = \langle vstack(2), vstack(1) \rangle \cat \tail(\tail(vstack)) \\
vsp' = vsp \\
vctx' = vctx \\
vmem' = vmem \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp \\
flags' = flags
\end{array}$$

#### Операция $ExecReadMem$:
Косвенное чтение из физической памяти по адресу со стека:

$$\begin{array}{|l}
ExecReadMem \\
\hline
\Delta StackVMState \\
\hline
vstack \ne \langle \rangle \\
\LET addr == \head(vstack) \IN \\
\quad vstack' = \langle read\_word\_mem(vmem, addr) \rangle \cat \tail(vstack) \\
vsp' = vsp \\
vctx' = vctx \\
vmem' = vmem \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp \\
flags' = flags
\end{array}$$

#### Операция $ExecWriteMem$:
Запись значения со стека в физическую память:

$$\begin{array}{|l}
ExecWriteMem \\
\hline
\Delta StackVMState \\
\hline
\#vstack \ge 2 \\
\LET addr == vstack(1) \semi val == vstack(2) \IN \\
\quad vmem' = write\_word\_mem(vmem, addr, val) \\
\quad vstack' = \tail(\tail(vstack)) \\
vsp' = vsp + (2 \cdot \text{WORD\_SIZE}) \\
vctx' = vctx \\
vkey' = vkey \\
vip' = vip \\
vdisp' = vdisp \\
flags' = flags
\end{array}$$

#### Операция относительной диспетчеризации $ExecDispatchRel$:

$$\begin{array}{|l}
ExecDispatchRel \\
\hline
\Delta StackVMState \\
\delta? : OFFSET \\
\hline
vdisp' = vdisp + \delta? \\
vip' = vip \\
vsp' = vsp \\
vkey' = vkey \\
vstack' = vstack \\
vctx' = vctx \\
vmem' = vmem \\
flags' = flags
\end{array}$$

---

### 3.6 Теорема о сохранении инварианта стека базового блока

Пусть базовый блок $B$ задан композицией операций $\mathcal{T}_B = \mathcal{O}_1 \comp \mathcal{O}_2 \comp \dots \comp \mathcal{O}_n$.

$$\mathbf{Theorem} ~ (\text{Stack Conservation}) \bullet \\
\forall s : StackVMState \bullet \\
\quad (\Delta \text{VSP}(B) = 0 \land s \in \dom \mathcal{T}_B) \implies \#(\mathcal{T}_B(s).vstack) = \#(s.vstack) \land \mathcal{T}_B(s).vsp = s.vsp$$

*Следствие:* При $\Delta \text{VSP}(B) = 0$ любой цикл или условное ветвление в графе потока управления не вызывает деградации или переполнения виртуального стека.

---

## 4. Набор инструкций Stack-ISA

Базовый набор инструкций виртуальной машины состоит из минималистичных примитивов фиксированной семантики:

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

1. **Инверсия $\text{NOT}(x)$:**
   $$\neg x \equiv x \downarrow x$$
   *Стековый шаблон:*
   ```
   DUP
   NOR
   ```

2. **Дизъюнкция $\text{OR}(x, y)$:**
   $$x \lor y \equiv (x \downarrow y) \downarrow (x \downarrow y)$$
   *Стековый шаблон:*
   ```
   NOR
   DUP
   NOR
   ```

3. **Конъюнкция $\text{AND}(x, y)$:**
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

4. **Исключающее ИЛИ $\text{XOR}(x, y)$:**
   $$x \oplus y \equiv (x \land \neg y) \lor (\neg x \land y) \equiv \dots$$
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
Если в точку слияния потока управления $B_{\text{join}}$ сходятся два ребра $B_1 \to B_{\text{join}}$ и $B_2 \to B_{\text{join}}$, финальные ключи $VKEY(B_1)$ и $VKEY(B_2)$ могут различаться.
- **Решение:** На исходящем ребре $B_2 \to B_{\text{join}}$ вставляется компенсационный переходной хендлер (`KEY_ADJUST`), корректирующий ключ:
  $$VKEY_{\text{target}} = VKEY_{\text{current}} \oplus \Delta_{\text{block}}$$

---

### Алгоритм 4. Относительная бестабличная диспетчеризация (Relative-Delta Dispatching)

Вместо фиксированной таблицы хендлеров `handlers_table[opcode]` каждый хендлер завершается эпилогом, использующим относительные смещения:

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
   - x86-64: `{VIP, VSP, VKEY, VDISP} \subset \{RAX, RBX, RCX, RDX, RSI, RDI, R8..R15\}`
   - AArch64: `{VIP, VSP, VKEY, VDISP} \subset \{X19..X28\}`
   - RV64: `{VIP, VSP, VKEY, VDISP} \subset \{s1..s11\}`
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
  - Проверка инварианта $\Delta \text{VSP} = 0$ на выходах блоков.
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
