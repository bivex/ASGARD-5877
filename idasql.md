# Руководство по аудиту виртуализированных бинарников ASGARD-5877 через idasql

Настоящий документ описывает методику применения утилиты `idasql` для автоматизированного анализа, аудита безопасности, проверки стойкости и отладки бинарных файлов, защищенных виртуальной машиной ASGARD-5877 (включая Stack-VM и Register-VM).

---

## 1. Назначение и цели аудита

При защите бинарных файлов виртуализацией кода (Stack-VM / Register-VM) и макро-обфускацией (`asgard_obf.h`) необходимо объективно верифицировать результат защиты против профессиональных инструментов реверс-инжиниринга (IDA Pro, Hex-Rays Decompiler).

Утилита `idasql` предоставляет декларативный SQL-интерфейс (на базе SQLite) к внутренней базе данных IDA Pro (`.i64`/`.idb`). Это позволяет автоматизировать:
- Проверку сокрытия строк и удаления символов;
- Аудит декомпилированного псевдокода Hex-Rays;
- Инспекцию низкоуровневых структур данных виртуальной машины и их выравнивания в памяти;
- Поиск скрытых багов и краевых условий в сгенерированном рантайме ВМ.

### Проверяемые свойства защиты

1. **Сокрытие строковых литералов (Data Hiding):** Отсутствие в открытом виде служебных строк, сообщений валидации, ключей и маркеров в таблице `strings`.
2. **Разрушение сигнатур функций (Symbol Elimination):** Полное удаление имен и тел целевых функций из таблиц `funcs` и `names`.
3. **Ослепление декомпилятора (Decompiler Resilience):** Невозможность восстановления бизнес-логики и графа потока данных декомпилятором Hex-Rays (таблица `pseudocode`).
4. **Безопасность байткода:** Наличие шифрования байткода с динамическим rolling-ключом и отсутствие статических цепочек операндов.
5. **Fail-Closed безопасность рантайма:** Защита от выхода за границы стека операндов (`vsp`), контроль контекстных слотов и отсутствие паразитных системных вызовов.

---

## 2. Предварительные требования

Для выполнения аудита требуются:

1. **IDA Pro 9.x / 8.x** с поддержкой пакетного консольного режима:
   - macOS: `/Applications/IDA Professional 9.2.app/Contents/MacOS/idat`
   - Linux: `/opt/idapro/idat64`
2. **Утилита `idasql`**:
   - Расположение в SDK: `/Users/password9090/Desktop/test/ida-sdk/src/bin/idasql`
3. **Защищенный бинарник**, собранный через ASGARD-5877:
   - Например: `_build/clean_test_stack/protected_app`

---

## 3. Режимы сборки бинарника

### 3.1 Продакшн-режим (Black-box аудит)
По умолчанию сборка выполняется с максимальной оптимизацией и агрессивным стриппингом всех таблиц символов и секций отладки (`strip -x`, `-Wl,-dead_strip`, `-Wl,-x`):
```bash
./_build/default/bin/main.exe protect-arm64 -i app.c -o _build/out --engine=stack
```

### 3.2 Отладочный режим с сохранением DWARF-символов (White-box аудит)
Для детального аудита структуры самой виртуальной машины, проверки типов данных и поиска ошибок в рантайме компилятор поддерживает флаг переменной окружения `ASGARD_DEBUG_SYMBOLS=1`.

При его установке:
- Включается генерация DWARF-информации (`-g -O1 -Wno-format-security`);
- Отключается удаление символов (`strip -x`);
- В базу IDA попадают определения структур C++ (`local_types`, `types_members`), имена аргументов и манглированные имена функций.

```bash
ASGARD_DEBUG_SYMBOLS=1 ./_build/default/bin/main.exe protect-arm64 -i app.c -o _build/out --engine=stack
```

---

## 4. Конвейер аудита бинарника

### Шаг 1. Генерация базы данных IDA в пакетном режиме

IDA Pro запускается в автономном пакетном режиме без графического интерфейса:

```bash
# macOS
"/Applications/IDA Professional 9.2.app/Contents/MacOS/idat" -A -B path/to/protected_app

# Linux
idat64 -A -B path/to/protected_app
```

Флаги:
- `-A`: Автономный режим (Autonomous mode), подавляет модальные диалоги.
- `-B`: Пакетный режим (Batch mode), автоматически создает файл базы данных `.i64` и листинг `.asm`.

В каталоге с бинарником будет создан файл `protected_app.i64`.

### Шаг 2. Запуск `idasql`

#### Выполнение одиночного запроса:
```bash
idasql -s protected_app.i64 -q "SELECT name, size FROM funcs;"
```

#### Интерактивный режим (REPL):
```bash
idasql -s protected_app.i64 -i
```

#### Выполнение SQL-скрипта из файла:
```bash
idasql -s protected_app.i64 -f audit_queries.sql
```

---

## 5. Схема таблиц базы данных `idasql`

Инструмент `idasql` открывает доступ к более чем 40 виртуальным таблицам. Для аудита виртуализированных бинарников ключевыми являются следующие:

| Таблица | Назначение | Ключевые колонки |
| :--- | :--- | :--- |
| `strings` | Строковые литералы, обнаруженные IDA | `address`, `length`, `type_name`, `content` |
| `funcs` | Таблица распознанных функций | `address`, `name`, `size`, `prototype`, `flags` |
| `names` | Символы, метки и имена в сегментах | `address`, `name` |
| `pseudocode` | Декомпилированный C-код (Hex-Rays) | `func_addr`, `line_num`, `line` |
| `local_types` | Зарегистрированные типы и структуры данных | `ordinal`, `name`, `is_struct`, `is_enum` |
| `types_members` | Поля структур, оффсеты и типы полей | `type_name`, `member_name`, `offset`, `size`, `member_type` |
| `xrefs` | Перекрестные ссылки кода и данных | `from_ea`, `to_ea`, `type`, `type_name` |
| `segments` | Карта секций бинарника | `name`, `start_ea`, `end_ea`, `bitness` |

---

## 6. Набор тестовых запросов для валидации защиты

### 6.1 Проверка сокрытия строковых литералов

**Цель:** Убедиться, что чувствительные строки приложения зашифрованы и отсутствуют в открытом виде.

```sql
SELECT printf('0x%X', address) AS addr, length, content
FROM strings
WHERE content LIKE '%license%'
   OR content LIKE '%valid%'
   OR content LIKE '%serial%'
   OR content LIKE '%secret%'
   OR content LIKE '%Testing%';
```

- **Ожидаемый результат:** `0 row(s)`.
- **Если строки найдены:** Строки не были обернуты в `ASG_STR` или макро-обфускатор был отключен.

### 6.2 Проверка элиминации защищенных функций

**Цель:** Убедиться, что исходная функция полностью виртуализирована, а её нативное имя и тело удалены.

```sql
SELECT printf('0x%X', address) AS addr, name, size
FROM funcs
WHERE name LIKE '%verify%'
   OR name LIKE '%license%'
   OR name LIKE '%serial%';
```

- **Ожидаемый результат:** `0 row(s)`.
- **Интерпретация:** Символ и тело функции отсутствуют. Вместо них управление передается через трамплин в универсальный диспетчер ВМ.

### 6.3 Инвентаризация оставшихся функций

**Цель:** Проверить общее количество функций, видимых статическому анализатору.

```sql
SELECT printf('0x%X', address) AS addr, name, size
FROM funcs
ORDER BY size DESC;
```

В продакшн-сборке виртуализированного приложения должны присутствовать только:
1. Системные стабы динамического связывания (`_printf` и др.).
2. Точка входа / функция `main` (`start`).
3. Диспетчер виртуальной машины (`sub_...` или `asgard_vm_call`).

### 6.4 Проверка отсутствия служебных меток в таблице имен

```sql
SELECT printf('0x%X', address) AS addr, name
FROM names
WHERE name LIKE '%ASGARD%'
   OR name LIKE '%Vanguard%'
   OR name LIKE '%Ultra%';
```

- **Ожидаемый результат:** `0 row(s)`. Маркерные разделители (`ASGARD_BEGIN_ULTRA`, `ASGARD_END`) не должны оставлять следов в бинарнике.

### 6.5 Аудит низкоуровневых структур данных (`types_members`)

При сборке с `ASGARD_DEBUG_SYMBOLS=1` можно верифицировать правильность раскладки структуры состояния ВМ в памяти:

```sql
SELECT member_name, offset, size, member_type
FROM types_members
WHERE type_name LIKE '%stack_vm%'
ORDER BY member_index;
```

**Эталонный вывод для `asgard_stack_vm::stack_vm_t`:**
```
+-------------+--------+-------+----------------+
| member_name | offset | size  | member_type    | 
+-------------+--------+-------+----------------+
| vsp         | 0      | 32768 | uint64_t[4096] | 
| vsp_idx     | 32768  | 4     | int            | 
| ctx         | 32776  | 512   | uint64_t[64]   | 
| vkey        | 33288  | 8     | uint64_t       | 
| zf          | 33296  | 1     | uint8_t        | 
| sf          | 33297  | 1     | uint8_t        | 
| cf          | 33298  | 1     | uint8_t        | 
| of          | 33299  | 1     | uint8_t        | 
| halted      | 33300  | 4     | int            | 
+-------------+--------+-------+----------------+
```
Критерии корректности:
- Стек вычислений `vsp` занимает ровно 32 КБ (4096 слотов по 8 байт);
- Контекстный фрейм регистров `ctx` выровнен по 8-байтовой границе (оффсет 32776);
- Динамический rolling-ключ `vkey` расположен сразу за контекстным массивом;
- Флаги `zf`, `sf`, `cf`, `of` упакованы в байтовые слоты.

### 6.6 Аудит декомпилятора Hex-Rays (`pseudocode`)

**Внимание:** Обращение к таблице `pseudocode` требует обязательной фильтрации `WHERE func_addr = <addr>` во избежание полной декомпиляции всех функций бинарника.

#### Анализ точки вызова виртуализированной функции:
```sql
SELECT line_num, line
FROM pseudocode
WHERE func_addr = (SELECT address FROM funcs WHERE name = 'start' OR name = 'main')
ORDER BY line_num;
```

- **Критерий успешности:** В псевдокоде видны стековые циклы деобфускации строк (XOR-лупы) и непрозрачный вызов вида:
  ```c
  v2 = sub_100000580(arg1, arg2);
  ```
  Декомпилятор не может восстановить соответствие между аргументами и проверкой серийного номера.

#### Анализ внутренностей диспетчера ВМ:
```sql
SELECT line_num, line
FROM pseudocode
WHERE func_addr = (SELECT address FROM funcs WHERE size > 2000 LIMIT 1)
  AND (line LIKE '%RotL%' OR line LIKE '%ROR8%' OR line LIKE '%switch%')
ORDER BY line_num;
```

- **Критерий успешности:** Декомпилятор восстанавливает только алгоритм пошаговой расшифровки байткода (`__ROR8__`, мутация rolling-ключа и диспетчеризация опкодов). Сами инструкции защищаемой логики остаются в зашифрованном массиве и не декомпилируются.

---

## 7. Практический кейс: выявление и исправление багов через idasql

В ходе реального аудита Stack-VM с помощью `idasql` были обнаружены и устранены следующие проблемы в сгенерированном C++ рантайме:

### Кейс 1: Холостые вызовы `dlsym(RTLD_DEFAULT, "")` и паразитный импорт
- **Симптом в `pseudocode`:** Декомпилятор показал ветку:
  ```c
  v76 = dlsym((void *)0xFFFFFFFFFFFFFFFELL, "");
  if (!v76) {
      snprintf(alt, 256, "_%s", "");
      v76 = dlsym(..., alt);
  }
  ```
- **Причина:** Если защищаемая функция не использует внешних вызовов, массив `g_external_symbols` генерировался со значением `{ "" }`. При опкодах `CALL_EXTERN` / `RESOLVE_SYM` рантайм пытался выполнить `dlsym` для пустой строки, что загрязняло таблицу импортов библиотеками `_dlsym` и `_snprintf`.
- **Решение:** В [`stack_runtime.ml`](file:///Volumes/External/Code/ASGARD-5877/lib/stack_vm/stack_runtime.ml) добавлена проверка `if (sym_name && sym_name[0] != '\0')`. В результате ненужные импорты полностью исчезли из бинарника (`funcs` сократился с 7 до 5 функций).

### Кейс 2: Stack Underflow / Overflow и безопасность памяти (Fail-Closed)
- **Симптом в `pseudocode`:** Операции со стеком `vm->vsp[vm->vsp_idx++]` и `vm->vsp[--vm->vsp_idx]` выполнялись без контроля границ. При повреждении или мутации байткода возникал риск порчи контекста `ctx` и флагов.
- **Решение:** Внедрены строгие защитные гарды Fail-Closed:
  ```cpp
  /* PUSH: защита от переполнения */
  if (vm->vsp_idx < 4096) vm->vsp[vm->vsp_idx++] = val;

  /* POP: защита от опустошения */
  if (vm->vsp_idx > 0) vm->ctx[idx] = vm->vsp[--vm->vsp_idx];

  /* БИНАРНЫЕ ОПЕРАЦИИ (ADD, SUB, NOR, CMP, ...): проверка наличия 2 операндов */
  if (vm->vsp_idx >= 2) {
      uint64_t b = vm->vsp[--vm->vsp_idx];
      uint64_t a = vm->vsp[--vm->vsp_idx];
      ...
  }
  ```

### Кейс 3: Защита слотов контекстного массива
- **Симптом:** Индекс `idx` в `PUSH_REG` / `POP_REG` / `CMOV` считывался из байткода как `int16_t` без проверки верхней границы.
- **Решение:** Добавлен динамический лимит `idx >= 0 && idx < max_ctx`, где `max_ctx = sizeof(vm->ctx) / sizeof(vm->ctx[0])`.

### Кейс 4: Верификация VSP Whitening в декомпиляторе (`pseudocode`)
- **Проверка через idasql:**
  ```sql
  SELECT line_num, line FROM pseudocode 
  WHERE func_addr = (SELECT address FROM funcs WHERE size > 2000 LIMIT 1)
    AND (line LIKE '%9E3779B97F4A7C15%' OR line LIKE '%61C8864680B583EB%');
  ```
- **Результат из реальной базы IDA:**
  ```c
  v126[(unsigned int)v89] = (0x9E3779B97F4A7C15LL * v88 + v9) ^ v126[(unsigned int)v88] ^ v91;
  v128[v125] = v126[(unsigned int)v98] ^ (v97 - 0x61C8864680B583EBLL * v98);
  ```
- **Интерпретация:** Декомпилятор Hex-Rays зафиксировал формулу шифрования VSP:
  `vkey + slot * 0x9E3779B97F4A7C15ULL` (в дополнительном коде `vkey - slot * 0x61C8864680B583EBLL`). Стек операндов полностью зашифрован в памяти, сырые значения аргументов и результатов промежуточных операций недоступны для статического дампа памяти.

---

## 8. Скрипт автоматизированного регрессионного аудита

Для интеграции аудита в CI/CD пайплайн ASGARD-5877 используется bash-скрипт:

```bash
#!/usr/bin/env bash
set -euo pipefail

BINARY_PATH="${1:-_build/clean_test_stack/protected_app}"
IDAT_PATH="${IDAT_PATH:-/Applications/IDA Professional 9.2.app/Contents/MacOS/idat}"
IDASQL_PATH="${IDASQL_PATH:-/Users/password9090/Desktop/test/ida-sdk/src/bin/idasql}"

echo "[*] Generating IDA database for ${BINARY_PATH}..."
"${IDAT_PATH}" -A -B "${BINARY_PATH}"

DB_PATH="${BINARY_PATH}.i64"
if [[ ! -f "${DB_PATH}" ]]; then
    DB_PATH="${BINARY_PATH}.idb"
fi

echo "[*] Running idasql security audit on ${DB_PATH}..."

# 1. Проверка отсутствия открытых строк
STR_COUNT=$("${IDASQL_PATH}" -s "${DB_PATH}" -q "SELECT count(*) FROM strings WHERE content LIKE '%license%' OR content LIKE '%serial%' OR content LIKE '%valid%';" | tail -n 1 | tr -d ' ')
if [[ "${STR_COUNT}" != "0" ]]; then
    echo "[-] FAILED: Sensitive strings leaked in binary (${STR_COUNT} found)!"
    exit 1
fi
echo "[+] PASSED: No sensitive strings leaked."

# 2. Проверка элиминации защищенных функций
FN_COUNT=$("${IDASQL_PATH}" -s "${DB_PATH}" -q "SELECT count(*) FROM funcs WHERE name LIKE '%verify_serial%' OR name LIKE '%license%';" | tail -n 1 | tr -d ' ')
if [[ "${FN_COUNT}" != "0" ]]; then
    echo "[-] FAILED: Protected function names exposed in symbol table (${FN_COUNT} found)!"
    exit 1
fi
echo "[+] PASSED: Protected symbols successfully eliminated."

# 3. Проверка отсутствия паразитных импортов (dlsym не должен вызываться без нужды)
DLSYM_COUNT=$("${IDASQL_PATH}" -s "${DB_PATH}" -q "SELECT count(*) FROM funcs WHERE name = '_dlsym';" | tail -n 1 | tr -d ' ')
if [[ "${DLSYM_COUNT}" != "0" ]]; then
    echo "[-] WARNING: Unnecessary _dlsym import present in binary!"
fi

echo "[+] All idasql security assertions verified successfully."
```

---

## 9. Ограничения

1. Для работы `idasql` требуется предварительно созданная база `.i64` или `.idb`. Напрямую анализировать бинарник без базы инструмент не предназначен.
2. Декомпиляционные запросы к `pseudocode` и `ctree` выполняются через Hex-Rays API и требуют наличия соответствующей декомпиляторной лицензии в окружении IDA Pro.

---

## 10. Связанные документы

- [`Stack-VM.md`](file:///Volumes/External/Code/ASGARD-5877/Stack-VM.md) — Спецификация виртуальной машины исполнения ASGARD-5877.
- [`docs/VM_PROTECTOR.md`](file:///Volumes/External/Code/ASGARD-5877/docs/VM_PROTECTOR.md) — Описание архитектуры виртуализации и рандомизации опкодов.
- [`docs/C_MACRO_OBF.md`](file:///Volumes/External/Code/ASGARD-5877/docs/C_MACRO_OBF.md) — Документация по макро-обфускации строк и констант.
