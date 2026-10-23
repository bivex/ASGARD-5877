# Ghost Pass: Anti-Neural Metamorphic Padding — Work Log & Remaining Work

Дата: 2026-10-23. Файл: `lib/stack_vm/stack_ghost_pass.ml`.

## Цель

Преодолеть два сигнала, по которым нейросети (BiLSTM/Transformer/5-gram) с Recall 97-99%
вычисляют ghost-инструкции (DRS_ghost ≈ 0-1 / 100, TIER 1 VULNERABLE):

1. **Периодичность**: при ghost_rate=100 ядро разбивалось на изолированные прогоны
   длины 1 (98.6% core-прогонов = 1). Любая группа 2+ опкодов = ghost.
2. **Сигнатурные N-граммы**: 72.3% уникальных 5-грамм встречались ТОЛЬКО в ghost-коде,
   лишь 1.3% пересекались с ядром. Например `PushReg PushImm Nor PushReg Nor PopReg` —
   6609 раз в ghost, 0 в core.

Дополнительно измеренный провал распределения опкодов:
- ghost `PopReg` = 46.4% vs core 11.9% (+34pp)
- ghost `Mul` = 0.0% vs core 10.3%; `Add` 1.2% vs 9.8%; `Nor` 0.1% vs 7.7%

Причина: после супероператорного слияния в ядре почти нет коротких Push/Pop пар
(они сжаты в SetRegImm/AddRegImm), а амплифицированные ALU-цепочки (с Mul/Nor)
длинные и смешиваются с live-значениями стека.

## Что сделано (текущее состояние кода, НЕ закоммичено)

### 1. Clone-Window Synthesis (главный механизм)
- Собираются окна длины 2..24 из РЕАЛЬНЫХ опкодов того же блока (`phase_4` вход).
- Каждое окно проверяется символическим симулятором стека (`simstate`, `sim_step`,
  `sim_complete`): abstract-значения `Orig i` (живые), `Copy i` (копии), `Win` (созданные окном).
  Окно безопасно iff: не уничтожает ни один `Orig`, финальный стек == исходному.
- **Sandbox-обёртки**: амплифицированные цепочки потребляют live-значение (их финальный
  ALU-оп — MBA-блендинг). Обёртка `[Dup] @ interior @ [PopReg]` (или `Dup2` + 2×PopReg)
  даёт интерьеру копию live-top и дренаж остатка — интерьер дословно из ядра.
- Каждое окно несёт `required_live_depth` (число материализованных Orig) — на эмите
  фильтруется по текущей глубине `!depth` (иначе Dup/Swap на глубине 0 → underflow).
- Инкрементальный сбор: 3 параллельных состояния (raw/dup/dup2) на позицию, O(n·24).
- `instantiate_clone`: write-слоты (PopReg/SetRegImm/AddRegImm) → scratch ring;
  иммедиаты заменяются консистентно (равные старые → равные новые, сохраняя
  нейтральность AddImm c; SubImm c); чтения реальных слотов (PushReg r) остаются как есть.

### 2. Local-Echo выбор
`pick_clone tbl pos cur_depth` — приоритет окнам из окрестности ±15 опкодов точки
вставки (граничные 5-граммы сливаются с локальным ядром), tournament selection
(из двух кандидатов берётся более длинный). Фоллбэк — любое окно блока.

### 3. Burst-Gap вставка
Вместо вставки после каждой инструкции: gap-процесс (`gap := next_int rng 3`),
пропускающий 0-2 точки вставки + вероятность второго кластера (30%).
Результат: core-прогоны 1-3 (равномерно), ghost-прогоны 1-8.

### 4. Симулятор — найденные и исправленные семантические баги
- **`Rot` — 3-цикл, а не разворот**: реальный `h_rot` даёт `[a;b;c] → [c;a;b]`
  (top=deepest, middle=top, deepest=middle), порядок 3. Было смоделировано как
  разворот (порядок 2) → `[Rot;Rot]` проходил проверку, но в реальной VM cycle²≠identity
  → порча live-стека. ИСПРАВЛЕНО.
- **`sim_complete` ожидаемый список был перевёрнут** (`List.init k (fun i -> Orig (k-1-i))`
  вместо `Orig i`): материализация добавляет Orig внизу списка (tail=deep), поэтому
  восстановленный стек читается `[Orig 0; ...; Orig k-1]` head=top. Для k≥2 окна с
  Swap никогда не собирались. ИСПРАВЛЕНО.
- **«Воскрешение» мёртвых состояний (главный источник дисбаланса -1/-2 на кластер,
  314 блоков с дрейфом -5..-8)**: `sim_step` при нарушении возвращал false, НЕ мутируя
  стек (например PopReg на Orig) — следующий оп мог вернуть true, состояние «оживало»,
  окно собиралось, а в реальной VM PopReg молча съедал live-значение.
  ФИКС: флаг `dead` в simstate, tombstone при любом нарушении.
- **`AddImmImm`/`SubImmImm` — чистые пуши** (pop_weight=0, push_weight=1: слитый
  константный push a+b), а не consume-1-produce-1. ПЕРЕМЕЩЕНЫ в push-бакет.

### 5. Прогресс метрик (до tombstone-фикса, старый сборщик)
- Clone-echo (окна ≤6, без обёрток): Recall BiLSTM 97.5% → 96.1%, 5-gram overlap
  1.3% → 8.6-10.3%. Core-прогоны: 98.6% длины 1 → равномерно 1-3.
- Распределение опкодов всё ещё смещено (PopReg 42% vs 11.9%, Mul 0.6% vs 10.3%)
  — для этого и сделаны обёртки Dup-wrap, захватывающие Mul/Nor-цепочки.

## Текущее состояние (на момент сохранения)

- Сборка проходит. Тест-сьют: **38/39, FAIL только #30** `Full Obfuscation Pipeline
  Semantics` — «FAIL pipeline: no balance errors». Тест #17 (Ghost Pass balanced) УЖЕ
  ПРОХОДИТ после tombstone-фикса; #30 продолжает находить balance-ошибки —
  дисбаланс ещё не полностью устранён.
- Бинарник с full-конфигом ещё НЕ пересобирался/не тестировался после tombstone-фикса.
- Изменения НЕ закоммичены (рабочее дерево: lib/stack_vm/stack_ghost_pass.ml).

## Что доделать

1. **Диагностика #30**: сгенерить дамп (`ASGARD_DUMP_JSON_DIR=... --compile=false`),
   сравнить per-block delta (поле "delta" в phase_4 vs phase_5 JSON, как делали:
   314 блоков с дрейфом). Найти оставшиеся несбалансированные кластеры.
   Подозреваемые: Dup2-wrap дренаж (2×PopReg при остатке ≠ 2), либо simulстан
   "complete" для dup2 всё ещё зондировался без dead-guard (`if v2 && len >= 1`
   блок — добавить `not w2.dead`, как сделано для w1).
2. **Smoke-тест бинарника** с full-конфигом: верный ключ → ACCESS GRANTED exit 0,
   неверный → DENIED exit 1.
3. **Прогнать весь сьют** `Stack-VM Execution Engine` до 39/39.
4. **Прогнать ghost_padding_eval.py** на свежем дампе — измерить Recall/DRS
   после всех фиксов. Цель: Recall BiLSTM/5-gram заметно ниже 96%, DRS выше.
   Проверить распределение опкодов ghost vs core (Mul/Add/Nor должны подтянуться).
5. При необходимости: усилить local-echo (уменьшить ±15), поднять долю клонов
   с 85%, отбалансировать длины.
6. CHANGELOG.md + коммит (feat(stack_vm): clone-window ghost synthesis).

## Ключевые файлы/инструменты

- `lib/stack_vm/stack_ghost_pass.ml` — сам пасс (симулятор ~L129-197, сбор L199-263,
  instantiate_clone, pick_clone, insert_ghosts_into_ops).
- `lib/stack_vm/stack_ir.ml` — authoritative push_weight/pop_weight (L59-105):
  AddImmImm/SubImmImm/AddRegImm: pop=0 push=1; AddImm/SubImm: pop=1 push=1.
- `lib/stack_vm/stack_handlers_emitter.ml` — h_rot (L151: 3-цикл), h_dup2 (L126:
  дублирует top-2 с сохранением порядка).
- `test/test_stack_vm.ml` L610-656 — тест 17 (ghost pass balance + eval 300L).
- `examples/nn_obf_eval/ghost_padding_eval.py` — аудит (chunk_dataset на 256,
  Bayesian prior для 5-gram; DRS_ghost = 100·(1-(2·max(0,AUC95-0.5))²)).
- Дамп: `ASGARD_DUMP_JSON_DIR=/tmp/X ... --compile=false`; phase_4-spaghetti.json /
  phase_5-ghost.json; per-op поле "delta" — авторитетный баланс.
