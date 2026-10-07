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
Для любого линейного участка (базового блока) $B$:
$$\Delta \mathrm{VSP}(B) = \sum_{i \in B} \mathrm{pushWeight}(i) - \sum_{i \in B} \mathrm{popWeight}(i)$$
На границах базовых блоков глубина стека $\mathrm{depth}(\mathrm{VSP})$ должна быть детерминирована для обеспечения корректности слияния потоков управления (join points).

---

## 3. Формальная спецификация в Z-нотации (Z Notation Specification)

Спецификация представлена в математическом исчислении схем (Schema Calculus) в формате строгих математических формул, полностью совместимых с KaTeX / MathJax.

### 3.1 Базовые типы, множества и операторы

$$[\mathrm{Addr}, \mathrm{Word}, \mathrm{Byte}, \mathrm{RegId}]$$

Производные типы и глобальные константы:
$$\mathrm{Val} == \mathrm{Word}, \quad \mathrm{Flags} == \mathrm{Word}, \quad \mathrm{Offset} == \mathbb{Z}$$
$$\mathrm{WordSize} == 8, \quad \mathrm{MaxStackDepth} : \mathbb{N}, \quad \mathrm{ActiveRegs} : \mathbb{P} ~ \mathrm{RegId}$$

Сигнатуры аксиоматических функций булевой логики и декриптора:

$$\begin{array}{l}
\mathrm{nor} : \mathrm{Val} \times \mathrm{Val} \to \mathrm{Val} \\
\mathrm{nand} : \mathrm{Val} \times \mathrm{Val} \to \mathrm{Val} \\
\mathrm{addWithFlags} : \mathrm{Val} \times \mathrm{Val} \to \mathrm{Val} \times \mathrm{Flags} \\
\mathrm{subWithFlags} : \mathrm{Val} \times \mathrm{Val} \to \mathrm{Val} \times \mathrm{Flags} \\
\mathrm{decryptByte} : \mathrm{Byte} \times \mathrm{Word} \to \mathrm{Byte} \\
\mathrm{deriveKey} : \mathrm{Word} \times \mathrm{Byte} \to \mathrm{Word} \\
\mathrm{readWordMem} : (\mathrm{Addr} \rightharpoonup \mathrm{Byte}) \times \mathrm{Addr} \to \mathrm{Val} \\
\mathrm{writeWordMem} : (\mathrm{Addr} \rightharpoonup \mathrm{Byte}) \times \mathrm{Addr} \times \mathrm{Val} \to (\mathrm{Addr} \rightharpoonup \mathrm{Byte})
\end{array}$$

---

### 3.2 Схема состояния виртуальной машины: $\mathrm{StackVMState}$

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{StackVMState} \\
\hline
\mathrm{vip} : \mathrm{Addr} \\
\mathrm{vsp} : \mathrm{Addr} \\
\mathrm{vkey} : \mathrm{Word} \\
\mathrm{vdisp} : \mathrm{Addr} \\
\mathrm{vstack} : \mathrm{seq} ~ \mathrm{Val} \\
\mathrm{vctx} : \mathrm{RegId} \rightharpoonup \mathrm{Val} \\
\mathrm{vmem} : \mathrm{Addr} \rightharpoonup \mathrm{Byte} \\
\mathrm{flags} : \mathrm{Flags} \\
\hline
|\mathrm{vstack}| \le \mathrm{MaxStackDepth} \\
\mathrm{vsp} \bmod \mathrm{WordSize} = 0 \\
\mathrm{dom}(\mathrm{vctx}) = \mathrm{ActiveRegs} \\
\hline
\end{array}$$

*Предикаты инварианта:*
1. $|\mathrm{vstack}| \le \mathrm{MaxStackDepth}$ — виртуальный стек строго ограничен для исключения переполнения памяти.
2. $\mathrm{vsp} \bmod \mathrm{WordSize} = 0$ — аппаратный указатель стека строго выровнен по 8-байтовой границе.
3. $\mathrm{dom}(\mathrm{vctx}) = \mathrm{ActiveRegs}$ — все активные регистры архитектуры замаплены во фрейме контекста.

---

### 3.3 Начальное состояние: $\mathrm{InitStackVMState}$

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{InitStackVMState} \\
\hline
\mathrm{StackVMState}' \\
\mathrm{entry?} : \mathrm{Addr} \\
\mathrm{initSp?} : \mathrm{Addr} \\
\mathrm{seedKey?} : \mathrm{Word} \\
\mathrm{baseDisp?} : \mathrm{Addr} \\
\mathrm{initCtx?} : \mathrm{RegId} \to \mathrm{Val} \\
\mathrm{initMem?} : \mathrm{Addr} \rightharpoonup \mathrm{Byte} \\
\hline
\mathrm{vip}' = \mathrm{entry?} \\
\mathrm{vsp}' = \mathrm{initSp?} \\
\mathrm{vkey}' = \mathrm{seedKey?} \\
\mathrm{vdisp}' = \mathrm{baseDisp?} \\
\mathrm{vstack}' = \langle \rangle \\
\mathrm{vctx}' = \mathrm{initCtx?} \\
\mathrm{vmem}' = \mathrm{initMem?} \\
\mathrm{flags}' = 0 \\
\hline
\end{array}$$

---

### 3.4 Выборка инструкции и потоковая расшифровка: $\mathrm{FetchByte}$

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{FetchByte} \\
\hline
\Delta \mathrm{StackVMState} \\
\mathrm{plain!} : \mathrm{Byte} \\
\hline
\mathrm{vip} \in \mathrm{dom}(\mathrm{vmem}) \\
\mathrm{plain!} = \mathrm{decryptByte}(\mathrm{vmem}(\mathrm{vip}), \mathrm{vkey}) \\
\mathrm{vip}' = \mathrm{vip} + 1 \\
\mathrm{vkey}' = \mathrm{deriveKey}(\mathrm{vkey}, \mathrm{plain!}) \\
\mathrm{vsp}' = \mathrm{vsp} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{vstack}' = \mathrm{vstack} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

---

### 3.5 Операционные схемы инструкций ($\Delta \mathrm{StackVMState}$)

#### Операция $\mathrm{PushImm}$ (Помещение непосредственного операнда):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{PushImm} \\
\hline
\Delta \mathrm{StackVMState} \\
\mathrm{imm?} : \mathrm{Val} \\
\hline
|\mathrm{vstack}| < \mathrm{MaxStackDepth} \\
\mathrm{vstack}' = \langle \mathrm{imm?} \rangle \mathbin{\frown} \mathrm{vstack} \\
\mathrm{vsp}' = \mathrm{vsp} - \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Операция $\mathrm{PushReg}$ (Чтение регистра из контекстного фрейма):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{PushReg} \\
\hline
\Delta \mathrm{StackVMState} \\
r? : \mathrm{RegId} \\
\hline
r? \in \mathrm{dom}(\mathrm{vctx}) \\
|\mathrm{vstack}| < \mathrm{MaxStackDepth} \\
\mathrm{vstack}' = \langle \mathrm{vctx}(r?) \rangle \mathbin{\frown} \mathrm{vstack} \\
\mathrm{vsp}' = \mathrm{vsp} - \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Операция $\mathrm{PopReg}$ (Запись со стека в контекстный слот):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{PopReg} \\
\hline
\Delta \mathrm{StackVMState} \\
r? : \mathrm{RegId} \\
\hline
r? \in \mathrm{dom}(\mathrm{vctx}) \\
\mathrm{vstack} \ne \langle \rangle \\
\mathrm{vctx}' = \mathrm{vctx} \oplus \{ r? \mapsto \mathrm{head}(\mathrm{vstack}) \} \\
\mathrm{vstack}' = \mathrm{tail}(\mathrm{vstack}) \\
\mathrm{vsp}' = \mathrm{vsp} + \mathrm{WordSize} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Операция $\mathrm{ExecNor}$ (Стрелка Пирса):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecNor} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
|\mathrm{vstack}| \ge 2 \\
\mathbf{let} ~ a = \mathrm{vstack}(1) \land b = \mathrm{vstack}(2) \bullet \\
\quad \mathrm{vstack}' = \langle \mathrm{nor}(a, b) \rangle \mathbin{\frown} \mathrm{tail}(\mathrm{tail}(\mathrm{vstack})) \\
\mathrm{vsp}' = \mathrm{vsp} + \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Операция $\mathrm{ExecAdd}$ (Сложение с генерацией флагов):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecAdd} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
|\mathrm{vstack}| \ge 2 \\
\mathbf{let} ~ a = \mathrm{vstack}(1) \land b = \mathrm{vstack}(2) \bullet \\
\quad \mathbf{let} ~ (res, newFlags) = \mathrm{addWithFlags}(a, b) \bullet \\
\quad\quad \mathrm{vstack}' = \langle res \rangle \mathbin{\frown} \mathrm{tail}(\mathrm{tail}(\mathrm{vstack})) \land \\
\quad\quad \mathrm{flags}' = newFlags \\
\mathrm{vsp}' = \mathrm{vsp} + \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\hline
\end{array}$$

#### Операция $\mathrm{ExecDup}$ (Дублирование вершины стека):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecDup} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
\mathrm{vstack} \ne \langle \rangle \\
|\mathrm{vstack}| < \mathrm{MaxStackDepth} \\
\mathrm{vstack}' = \langle \mathrm{head}(\mathrm{vstack}) \rangle \mathbin{\frown} \mathrm{vstack} \\
\mathrm{vsp}' = \mathrm{vsp} - \mathrm{WordSize} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Операция $\mathrm{ExecSwap}$ (Перестановка двух верхних элементов):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecSwap} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
|\mathrm{vstack}| \ge 2 \\
\mathrm{vstack}' = \langle \mathrm{vstack}(2), \mathrm{vstack}(1) \rangle \mathbin{\frown} \mathrm{tail}(\mathrm{tail}(\mathrm{vstack})) \\
\mathrm{vsp}' = \mathrm{vsp} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Операция $\mathrm{ExecReadMem}$ (Косвенное чтение из физической памяти):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecReadMem} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
\mathrm{vstack} \ne \langle \rangle \\
\mathbf{let} ~ addr = \mathrm{head}(\mathrm{vstack}) \bullet \\
\quad addr \in \mathrm{dom}(\mathrm{vmem}) \land \\
\quad \mathrm{vstack}' = \langle \mathrm{readWordMem}(\mathrm{vmem}, addr) \rangle \mathbin{\frown} \mathrm{tail}(\mathrm{vstack}) \\
\mathrm{vsp}' = \mathrm{vsp} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Операция $\mathrm{ExecWriteMem}$ (Запись со стека в физическую память):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecWriteMem} \\
\hline
\Delta \mathrm{StackVMState} \\
\hline
|\mathrm{vstack}| \ge 2 \\
\mathbf{let} ~ addr = \mathrm{vstack}(1) \land val = \mathrm{vstack}(2) \bullet \\
\quad \mathrm{vmem}' = \mathrm{writeWordMem}(\mathrm{vmem}, addr, val) \\
\mathrm{vstack}' = \mathrm{tail}(\mathrm{tail}(\mathrm{vstack})) \\
\mathrm{vsp}' = \mathrm{vsp} + (2 \cdot \mathrm{WordSize}) \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vdisp}' = \mathrm{vdisp} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

#### Операция $\mathrm{ExecDispatchRel}$ (Относительное смещение диспетчера):

$$\begin{array}{|l}
\mathbf{schema} \quad \mathrm{ExecDispatchRel} \\
\hline
\Delta \mathrm{StackVMState} \\
\delta? : \mathrm{Offset} \\
\hline
\mathrm{vdisp}' = \mathrm{vdisp} + \delta? \\
\mathrm{vip}' = \mathrm{vip} \\
\mathrm{vsp}' = \mathrm{vsp} \\
\mathrm{vkey}' = \mathrm{vkey} \\
\mathrm{vstack}' = \mathrm{vstack} \\
\mathrm{vctx}' = \mathrm{vctx} \\
\mathrm{vmem}' = \mathrm{vmem} \\
\mathrm{flags}' = \mathrm{flags} \\
\hline
\end{array}$$

---

### 3.6 Теорема сохранения инварианта стека базового блока

Пусть базовый блок $B$ задан последовательной композицией операций:
$$\mathcal{T}_B = \mathcal{O}_1 \mathbin{\mathbf{;}} \mathcal{O}_2 \mathbin{\mathbf{;}} \dots \mathbin{\mathbf{;}} \mathcal{O}_n$$

$$\begin{array}{l}
\mathbf{Theorem} ~ (\mathrm{StackConservation}) \bullet \\
\forall s : \mathrm{StackVMState} \bullet \\
\quad (\Delta \mathrm{VSP}(B) = 0 \land s \in \mathrm{dom}(\mathcal{T}_B)) \implies \\
\quad\quad |\mathcal{T}_B(s).\mathrm{vstack}| = |s.\mathrm{vstack}| \land \mathcal{T}_B(s).\mathrm{vsp} = s.\mathrm{vsp}
\end{array}$$

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
   Теоретико-множественное представление:
   $$x \oplus y \equiv (x \lor y) \land \neg(x \land y)$$
   
   В базисе Пирса ($\downarrow$) канонически выражается через суперпозицию конъюнкции и анти-дизъюнкции:
   $$x \oplus y = ((x \downarrow x) \downarrow (y \downarrow y)) \downarrow (x \downarrow y)$$
   
   *Доказательство корректности:*
   - Первая часть: $(x \downarrow x) \downarrow (y \downarrow y) = (\neg x) \downarrow (\neg y) = \neg(\neg x \lor \neg y) = x \land y$.
   - Вторая часть: $x \downarrow y = \neg(x \lor y)$.
   - Их суперпозиция через $\mathrm{NOR}$:
     $$\neg \Big( (x \land y) \lor \neg(x \lor y) \Big) = \neg (x \odot y) = x \oplus y$$

   *Сетевая декомпозиция (5-гейтовая схема):*
   $$\begin{aligned}
   g_1 &= x \downarrow y \\
   g_2 &= x \downarrow g_1 \\
   g_3 &= y \downarrow g_1 \\
   g_4 &= g_2 \downarrow g_3 \\
   x \oplus y &= g_4 \downarrow g_4
   \end{aligned}$$

   *Стековый шаблон компилятора (`LowerToStack` из контекста):*
   ```
   ; 1. Вычисление (x AND y) на стеке
   PUSH_REG src2       ; y
   DUP
   NOR                 ; NOT(y)
   PUSH_REG src1       ; x
   DUP
   NOR                 ; NOT(x)
   NOR                 ; (x AND y)

   ; 2. Вычисление (x NOR y) на стеке
   PUSH_REG src2       ; y
   PUSH_REG src1       ; x
   NOR                 ; (x NOR y)

   ; 3. Финальная редукция
   NOR                 ; (x AND y) NOR (x NOR y) == x XOR y
   ```

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
- [x] **1.1 Определение типа Stack-IR в OCaml:**
  Создан модуль `lib/stack_vm/stack_ir.ml` / `stack_ir.mli`:
  - Тип `stack_op = PushImm of int64 | PushReg of int | PopReg of int | ReadMem of int | WriteMem of int | Nor | Nand | Add | Sub | Mul | Div | Shl | Shr | Dup | Swap | JmpRel of int | JccRel of int * condition | KeyAdjust of int64 | Exit`
  - Расчет весов стека `push_weight`, `pop_weight`, `delta_vsp`.
  - Сериализатор / десериализатор и pretty-printer для отладки (`to_string`, `print_program`).
- [x] **1.2 Транслятор `lib/stack_vm/ir_to_stack.ml` и аллокатор контекста:**
  - Реализован `lib/stack_vm/context_allocator.ml` / `context_allocator.mli` с псевдослучайной перестановкой слотов регистров (GPR + VREG).
  - Реализована трансляция из 3-адресного `Ir.t` в `Stack_ir.program` (`lower_block`, `lower_program`).
  - Покрыто юнит-тестами с проверкой эквивалентности вычислений.

### Фаза 2: Оптимизации и обфусцирующие пассы
- [x] **2.1 Пасс редукции булевой логики (`lib/stack_vm/stack_logic_pass.ml`):**
  - Подстановка эквивалентов NOR/NAND для всех логических операций (`NOT`, `AND`, `OR`, `XOR`).
  - Корректная 5/6-гейтовая схема XOR в базисе Пирса без деградации таблиц истинности.
  - Рандомизация выбора базиса: режим `NorBasis`, `NandBasis`, `MixedBasis`.
- [x] **2.2 Пасс выравнивания стека (Stack Balance Verification):**
  - Модуль `lib/stack_vm/stack_balance_pass.ml` / `stack_balance_pass.mli`:
  - Статический анализ глубины стека `analyze_stack_balance`.
  - Проверка инварианта $\Delta \mathrm{VSP} = 0$ на выходах блоков.
  - Автоматическая коррекция `repair_stack_balance` со вставкой сброса мусора или выравнивающего паддинга.

### Фаза 3: Генерация байткода и криптор
- [x] **3.1 Модуль `lib/stack_vm/stack_encoder.ml`:**
  - Реализация rolling-key генератора (`step_key`, 64-битный циклический сдвиг и XOR-константы).
  - Двунаправленный расчет ключей: кодирование и декодирование (`encode_program`, `decode_program`).
  - Межблочная синхронизация ключей (`reconcile_keys` с инъекцией `KeyAdjust`).
- [x] **3.2 Упаковщик байткода:**
  - Потоковая упаковка инструкций с опкодами переменной длины и 64-битными аргументами в байтовый массив `bytes`.
- [x] **3.3 Виртуальная машина исполнения / эмулятор (`lib/stack_vm/stack_eval.ml`):**
  - Исполнитель `eval_program` для прямого выполнения `Stack_ir.program`.
  - Исполнитель `eval_encrypted` с потоковой расшифровкой байткода по ходу исполнения.

### Фаза 4: Синтезатор рантайма под целевые платформы
- [x] **4.1 Мультиплатформенный генератор рантайма (`lib/stack_vm/stack_runtime.ml`):**
  - Синтез входных стабов `vm_enter` (сохранение контекста, инициализация VSP/VIP/VKEY/VDISP).
  - Синтез хендлеров `PUSH_IMM`, `PUSH_REG`, `POP_REG`, `READ_MEM`, `WRITE_MEM`, `NOR`, `NAND`, `ADD`, `SUB`, `DUP`, `SWAP`, `KEY_ADJUST`.
  - Синтез диспетчера с относительным переходом:
    - x86-64 (`emit_x86_64`)
    - AArch64 (`emit_aarch64`)
    - RV64 (`emit_rv64`)
  - Генерация автономного переносимого C-рантайма (`emit_c_runtime`).

### Фаза 5: Интеграция в общую экосистему ASGARD-5877
- [x] **5.1 Многоуровневый выбор бэкенда (Multi-Tier VM Selector):**
  - Поддержка переключения движка виртуализации через флаг `--engine=stack` / `--engine=threaded` в CLI (`cli_protect.ml`, `cli_protect_arm64.ml`).
  - Автоматическая маршрутизация в адаптер `Stack_vm_packager` с генерацией C++ рантайма `stack_vm_runtime.hpp` и трамплина вызова.
- [x] **5.2 Комплексное тестирование и верификация:**
  - Создан тестовый модуль `test/test_stack_vm.ml` с 8 тестовыми наборами:
    - Stack IR Primitives & Stack Delta Weight
    - Context Allocator & Permutations
    - Logic Pass (NOR/NAND expansions & XOR truth tables)
    - IR to Stack Lowering & Execution (Arithmetic, Branching, Memory)
    - Stack Balance Pass & Repair
    - Rolling Key Bytecode Encryption & Runtime Decryption Roundtrip
    - Multi-target Runtime Synthesizer (x86_64, aarch64, rv64, C runtime)
    - Stack VM Extensions & Branching (CallExtern, ResolveSym, Setcc, Cmov, Cmp, Test)
  - Полная интеграция в раннер `test/run_tests.ml` (все 255 тестов ASGARD-5877 успешно пройдены).
- [x] **5.3 Верификация стойкости против декомпиляторов (IDA Pro, Hex-Rays через `idasql`):**
  - Реализован конвейер аудита через SQL-интерфейс `idasql` к базе данных IDA Pro (см. [`idasql.md`](idasql.md)).
  - Подтверждена 100% невидимость строк (`strings`), уничтожение символов защищенных функций (`funcs`, `names`) и сокрытие потока данных от декомпилятора Hex-Rays (`pseudocode`).
  - В рантайм внедрены Fail-Closed гарды защиты от stack underflow/overflow и context out-of-bounds, а также санитизация внешних вызовов.

### Фаза 6: Anti-VMPredator address binding (Phase 6)
- [x] **6.1 Привязка ключей байткода к адресам хендлеров в памяти (Address-Bound Bytecode):**
  - Модель защиты против универсальных дамперов и автоматизированных девиртуализаторов (VMPredator, NoVmp).
  - В C++ рантайме (`stack_vm_runtime.hpp`) все 29 хендлеров вынесены в адресуемые функции `h_push_imm` … `h_test`, чьи адреса зафиксированы в массиве `g_stack_handler_table`.
  - Функция `derive_addr_key()` вычисляет 64-битный хэш дельт между адресами соседних хендлеров (`(addr[i] - addr[i-1])`), инвариантный к ASLR и PIE-рандомизации базы модуля, формируя адресный ключ $D$.
- [x] **6.2 Маскирование литералов ключей в кодировщике (`Stack_encoder`):**
  - Поле `addr_mask` в типе `encrypted_bytecode`. Хранимые литералы ключей (`seed_key` и `block_keys`) на этапе кодирования предварительно XOR-ятся с маской $D$ (`Stack_encoder.apply_addr_mask`).
  - При `addr_mask = 0L` гарантируется побайтовая идентичность легаси-выводу.
  - Шифробайты (`bytes`) неизменны при любой маске — смещаются исключительно литералы ключей в заголовке и точках схода.
  - Рантайм `stack_vm_call` сворачивает ключ обратно: `vm.addr_key = derive_addr_key(); vm.vkey ^= vm.addr_key;`, а обработчики переходов `h_jmp_rel` и `h_jcc_rel` подмешивают `vm.addr_key` при восстановлении ключа блока.
- [x] **6.3 Двухстадийная сборка (Probe-TU) и интеграция в пайплайн:**
  - Генератор микро-зонда `Stack_runtime.emit_probe_cpp` компилируется тем же набором компиляционных флагов (`-O3`, dead-strip, RTTI/EH disabled) в единице трансляции `addr_probe.cpp`.
  - Пайплайн запускает скомпилированный `addr_probe`, считывает `ADDR_KEY: <16 hex>`, вычисляет $D$ и через замыкание `rebind_address` перезаписывает `stack_vm_runtime.hpp` актуальными связанными литералами.
  - Fallback-режим с маской 0 при отсутствии тулчейна или сбое зондирования.
- [x] **6.4 Тестирование и верификация:**
  - `test_addr_mask_unit`: проверка побайтовой идентичности шифротекста, свойств маскирования и обратимости `apply_addr_mask`.
  - `test_addr_mask_wrong_key`: верификация расхождения и срыва девиртуализации при чужом/неверном ключе $D'$.
  - `test_address_bound_c_runtime_probe_and_run`: полный E2E-тест генерации зонда, вычисления $D$, ребиндинга C++ заголовка, компиляции раннера и верификации результата вычислений относительно эталонного интерпретатора OCaml.


### Фаза 7: Аутентификация образа и политика гостевой памяти (Phase 7)

Фазы 1–6 закрывают *читаемость* байткода и его привязку к адресам хендлеров. Ни одна из них не даёт
свойства **целостности**: rolling key — это шифр, а не аутентификатор, поэтому пропатченный образ
расшифровывается ровно так же успешно, как оригинальный. Фаза 7 добавляет три точки отказа,
каждая из которых по умолчанию fail-closed.

- [x] **7.1 Ключевой тег целостности образа (`Stack_encoder.payload_tag`):**
  - Поле `payload_tag` в типе `encrypted_bytecode` плюс `tag_keys` (две половины ключа MAC под
    идентификаторами 0 и 1, замаскированные той же схемой `mask64`, что и `block_keys`).
  - Тег — CBC-MAC над шифрообразом: `asg_siphash12` (зеркало `Stack_encoder.siphash_block`,
    SipHash-1-2) в режиме CBC, где преобразование $\mathit{domain} \oplus (8\lceil L/8\rceil)$
    абсорбируется первым, затем каждое 64-битное слово little-endian. Длина образа связана с
    содержимым, поэтому ни переворот бита, ни усечение, ни расширение образа не сохраняют тег.
  - Ключи MAC доменно-отделены и от поперечных ключей блоков, и **друг от друга**. Первая версия
    выводила половины как `seed ^ "pay_mac1"` и `seed ^ "pay_mac2"`, то есть константы различались в
    одном байте и $k_0 \oplus k_1 = 3$ для *любого* сида: восстановив одну половину, атакующий
    получал вторую точно, и пара не несла больше 64 бит, выглядя на 128. Теперь обе половины
    пропускаются через PRF под разными доменами (`Stack_encoder.payload_tag_keys`), так что они
    вычислительно независимы, а расстояние между ними зависит от сида. Тег считается от
    *эффективного* (не замаскированного) сида, поэтому инвариантен к `apply_addr_mask` — перебиндинг
    адреса не ломает аутентификацию.
  - Рантайм проверяет тег в `asg_payload_auth_ok` **до первого fetch** (`stack_vm_run`), при
    несовпадении машина останавливается, не декодировав ни одного байта. Сравнение тегов
    константно-времясное, чтобы утечка через ранний выход не выдавала, сколько бит угадано.
  - **Контракт отказа при непрохождении аутентификации — неотличимость от обычного отказа.** Контекст
    обнуляется, `vsp_idx` сбрасывается, выставляется `auth_failed`. Раньше контекст оставался как
    есть, а на AArch64 `ctx[0]` к моменту возврата держал `a0`, то есть первый аргумент вызова:
    вызывающий вычислял `ok ^ 1` над усечённым указателем и завершался с кодом, производным от
    адреса (наблюдалось 49 вместо 1). Теперь непрошедший образ даёт тот же результат, тот же код
    возврата и тот же вывод, что и отклонённый ключ. Флаг `auth_failed` читает вызывающий — это
    сознательно не то, что образ может увидеть или на что повлиять.
- [x] **7.2 Граница выборки операндов (`fetch_byte`):**
  - Поле `bc_size` в `stack_vm_t`; `stack_vm_run` выставляет его равным размеру образа, и каждый
    `fetch_byte` проверяет `vip < bc_size` до чтения.
  - Раньше обрезанная инструкция читала до 8 байт за концом образа и продолжала декодирование —
    то, что лежит в `.rodata` после образа, становилось инструкциями и подмешивалось в поток
    ключа. Теперь выход за границу останавливает машину.
  - Длина образа приходит на точку входа из `len_words * 8`, то есть всегда кратна 8; образ
    невыравненной или нулевой длины не аутентифицируется вовсе.
- [x] **7.3 Политика гостевой памяти (`asg_mem_access_ok`):**
  - `READ_MEM` / `WRITE_MEM` разыменовывают значение со стека как указатель. Политика допускает
    обращение только при ширине из множества $\{1, 2, 4, 8\}$, ненулевом адресе, естественном
    выравнивании по ширине, каноничности адреса (биты 63:48 — знаковое продолжение бита 47, так
    что вычисленное целое не может «обернуться» через середину адресного пространства и выдать
    себя за указатель) и отсутствии переполнения на верхней границе. Всё прочее — halt.
  - `Stack_eval.mem_access_ok` — построчная калька того же предиката, чтобы эталонный
    интерпретатор OCaml и рантайм не расходились.
  - Компилятор не эмитит эти два опкода, поэтому ужесточение не меняет поведение ни одного
    образа, собранного из этого дерева.

**Ограничение, которое стоит проговорить явно.** Ключ MAC выводится из сида, который лежит в том
же бинарнике, поэтому тег — это tamper-evidence и точка принудительного применения, а не
криптографическая защита от целенаправленного патчера. Это проверено на живом артефакте: имея
`stack_vm_runtime.hpp` из каталога сборки, `ADDR_KEY` из приложенного `addr_probe` и сам образ,
достаточно воспроизвести `ASG_PAYLOAD_TAG` побайтово — после этого подписать можно любой образ по
своему выбору. Чтобы получить настоящую стойкость, вывод `payload_tag_keys` должен питаться
секретом, которого нет в образе (железный секрет, удалённая выдача), — тогда меняется одна функция,
а точка проверки и весь флаг-связывающий код уже на месте. Вторая незакрытая часть класса — сама
формула проверки: пока она вычисляется локально, её можно вывести символическим исполнением
поднятой ISA, и никакая обфускация ВМ этого не меняет. Третья — сам интерпретатор: `h_push_imm` …
`h_test` лежат в дереве сборки открытым C, и это генератор того же заголовка, что компилируется в
бинарник. Обфускация ВМ имеет смысл только вместе с удалением её исходников из поставки.
