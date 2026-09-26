# Руководство по аудиту виртуализированных бинарников ASGARD-5877 через idasql

Настоящий документ описывает методику применения утилиты `idasql` для автоматизированного анализа, аудита безопасности и проверки стойкости бинарных файлов, защищенных виртуальной машиной ASGARD-5877 (включая Stack-VM и Register-VM).

---

## 1. Назначение и цели аудита

При защите бинарных файлов виртуализацией кода (Stack-VM / Register-VM) и макро-обфускацией (`asgard_obf.h`) необходимо объективно верифицировать результат защиты против профессиональных инструментов реверс-инжиниринга (IDA Pro, Hex-Rays Decompiler).

Утилита `idasql` предоставляет SQL-интерфейс (на базе SQLite) к внутренней базе данных IDA Pro (`.i64`/`.idb`). Это позволяет формировать декларативные запросы к структуре бинарника, таблице строк, символам, графу вызовов и псевдокоду декомпилятора без необходимости ручной работы в GUI.

### Проверяемые свойства защиты

1. **Сокрытие строковых литералов (Data Hiding):** Отсутствие в открытом виде служебных строк, сообщений валидации, ключей и маркеров в таблице `strings`.
2. **Разрушение сигнатур функций (Symbol Elimination):** Полное удаление имен и тел целевых функций из таблиц `funcs` и `names`.
3. **Ослепление декомпилятора (Decompiler Resilience):** Невозможность восстановления бизнес-логики и графа потока данных декомпилятором Hex-Rays (таблица `pseudocode`).
4. **Безопасность байткода:** Наличие шифрования байткода с динамическим rolling-ключом и отсутствие статических цепочек операндов.

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

## 3. Конвейер аудита бинарника

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

## 4. Схема таблиц базы данных `idasql`

Инструмент `idasql` открывает доступ к более чем 40 виртуальным таблицам. Для аудита виртуализированных бинарников ключевыми являются следующие:

| Таблица | Назначение | Ключевые колонки |
| :--- | :--- | :--- |
| `strings` | Строковые литералы, обнаруженные IDA | `address`, `length`, `type_name`, `content` |
| `funcs` | Таблица распознанных функций | `address`, `name`, `size`, `prototype`, `flags` |
| `names` | Символы, метки и имена в сегментах | `address`, `name` |
| `pseudocode` | Декомпилированный C-код (Hex-Rays) | `func_addr`, `line_num`, `line` |
| `xrefs` | Перекрестные ссылки кода и данных | `from_ea`, `to_ea`, `type`, `type_name` |
| `segments` | Карта секций бинарника | `name`, `start_ea`, `end_ea`, `bitness` |

---

## 5. Набор тестовых запросов для валидации защиты

Ниже приведены готовые SQL-запросы для автоматической верификации защищенного приложения.

### 5.1 Проверка сокрытия строковых литералов

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

### 5.2 Проверка элиминации защищенных функций

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

### 5.3 Инвентаризация оставшихся функций

**Цель:** Проверить общее количество функций, видимых статическому анализатору.

```sql
SELECT printf('0x%X', address) AS addr, name, size
FROM funcs
ORDER BY size DESC;
```

В виртуализированном приложении должны присутствовать только:
1. Системные стабы динамического связывания (`_printf`, `_dlsym` и др.).
2. Точка входа / функция `main` (`start`).
3. Диспетчер виртуальной машины (`sub_...` или `asgard_vm_call`).

### 5.4 Проверка отсутствия служебных меток в таблице имен

```sql
SELECT printf('0x%X', address) AS addr, name
FROM names
WHERE name LIKE '%ASGARD%'
   OR name LIKE '%Vanguard%'
   OR name LIKE '%Ultra%';
```

- **Ожидаемый результат:** `0 row(s)`. Маркерные разделители (`ASGARD_BEGIN_ULTRA`, `ASGARD_END`) не должны оставлять следов в бинарнике.

### 5.5 Аудит декомпилятора Hex-Rays (`pseudocode`)

**Внимание:** Обращение к таблице `pseudocode` требует обязательной фильтрации `WHERE func_addr = <addr>` во избежание полной декомпиляции всех функций бинарника.

#### Анализ точки вызова виртуализированной функции:
```sql
SELECT line_num, line
FROM pseudocode
WHERE func_addr = (SELECT address FROM funcs WHERE name = 'start')
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
  AND line LIKE '%RotL%' OR line LIKE '%ROR8%' OR line LIKE '%switch%'
ORDER BY line_num;
```

- **Критерий успешности:** Декомпилятор восстанавливает только алгоритм пошаговой расшифровки байткода (`__ROR8__`, мутация rolling-ключа и диспетчеризация опкодов). Сами инструкции защищаемой логики остаются в зашифрованном массиве и не декомпилируются.

---

## 6. Скрипт автоматизированного регрессионного аудита

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

# 1. Проверка строк
STR_COUNT=$("${IDASQL_PATH}" -s "${DB_PATH}" -q "SELECT count(*) FROM strings WHERE content LIKE '%license%' OR content LIKE '%serial%' OR content LIKE '%valid%';" | tail -n 1 | tr -d ' ')
if [[ "${STR_COUNT}" != "0" ]]; then
    echo "[-] FAILED: Sensitive strings leaked in binary (${STR_COUNT} found)!"
    exit 1
fi
echo "[+] PASSED: No sensitive strings leaked."

# 2. Проверка символов
FN_COUNT=$("${IDASQL_PATH}" -s "${DB_PATH}" -q "SELECT count(*) FROM funcs WHERE name LIKE '%verify_serial%' OR name LIKE '%license%';" | tail -n 1 | tr -d ' ')
if [[ "${FN_COUNT}" != "0" ]]; then
    echo "[-] FAILED: Protected function names exposed in symbol table (${FN_COUNT} found)!"
    exit 1
fi
echo "[+] PASSED: Protected symbols successfully eliminated."

echo "[+] All idasql security assertions verified successfully."
```

---

## 7. Ограничения

1. Для работы `idasql` требуется предварительно созданная база `.i64` или `.idb`. Напрямую анализировать бинарник без базы инструмент не предназначен.
2. Декомпиляционные запросы к `pseudocode` и `ctree` выполняются через Hex-Rays API и требуют наличия соответствующей декомпиляторной лицензии в окружении IDA Pro.

---

## 8. Связанные документы

- [`Stack-VM.md`](file:///Volumes/External/Code/ASGARD-5877/Stack-VM.md) — Спецификация виртуальной машины исполнения ASGARD-5877.
- [`docs/VM_PROTECTOR.md`](file:///Volumes/External/Code/ASGARD-5877/docs/VM_PROTECTOR.md) — Описание архитектуры виртуализации и рандомизации опкодов.
- [`docs/C_MACRO_OBF.md`](file:///Volumes/External/Code/ASGARD-5877/docs/C_MACRO_OBF.md) — Документация по макро-обфускации строк и констант.
