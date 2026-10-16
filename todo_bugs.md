# TODO: известные баги / падения тестов

Дата: 2026-10-16. Обнаружено при верификации differential fuzzing
(`dune runtest`, 467 тестов, 8 падений). Обе группы не связаны с
FP-taint фиксом рерайтера (`c_arith_rewriter.ml`) — задокументировано
для последующего разбора.

## 1. Native VM Sub-width Semantics — 7 падений (arm64 lifter)

```
ASSERT uint16_pipeline failed: Lifter failed (arm64): Unsupported or invalid ARM64 instruction: sturh
```

- Suite: `Native VM Sub-width Semantics`, тесты `e2e_uint16_pipeline` и соседние
  (кэш прогонов: `_build/default/test/_build/_tests/Random_vISA_Tests/Native VM Sub-width Semantics.00{4,5,8,9}.output`, `.01{0,1,2}.output`).
- Причина: arm64-лифтер не поддерживает инструкцию `sturh`
  (unscaled store halfword, `lib/arm64_lifter/`).
- Файл для правки: парсер/таблица инструкций arm64-лифтера — добавить
  декодирование `sturh` (и, вероятно, соседних unscaled load/store:
  `ldurh`, `ldurb`, `sturb`, `ldursb`, `ldursh` — стоит проверить сразу).
- Semantics: `sturh Wt, [Xn, #imm9]` — запись младших 16 бит регистра
  по невыровненному адресу; не должна модифицировать флаги.

## 2. Anti-Pushan Rolling Key — 1 падение

```
Кэш: `_build/default/test/_build/_tests/Random_vISA_Tests/Anti-Pushan Rolling Key.009.output`
```

- Тест `anti_vmpredator_ta...` (индекс 9 в suite).
- Требует воспроизведения: `_build/default/test/run_tests.exe test 'Anti-Pushan Rolling Key'`.
- Статус: не разбирался, причина неизвестна.

## 3. (исправлено в рабочем дереве) MBA-рерайтер ломал FP-код

`double q2 = q + p.d;` → `ASG_MBA_ADD(q, p.d)` → `double ^ double` —
невалидный C++, obf-TU не компилировался. Найдено differential-раннером
(`examples/diff_fuzz/`) на первом же прогоне project-пайплайна.

Фикс: FP-taint анализ в `lib/c_macro_obf/c_arith_rewriter.ml` +
`c_expr_parser.ml` (сбор FP-деклараций TU, авто-цепочки, FP-литералы/
касты/math-builtins; tainted выражения не переписываются). Регрессионный
тест: `arithmetic_rewriter_fp_taint` в `test/test_c_macro_obf.ml` (проходит).
