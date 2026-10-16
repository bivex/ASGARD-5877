# ASGARD-5877 Differential Fuzzing

Полное покрытие расхождений между нативным кодом и VM Асгарда через два
взаимодополняющих инструмента с общим ядром (`proj_src/`).

```
                    ┌──────────────────────────────────────────┐
                    │  proj_src/compute_core.cpp  (kernelи)    │
                    │  proj_src/main_driver.cpp   (--fuzz main)│
                    └───────────────┬──────────────────────────┘
              ┌─────────────────────┴──────────────────────┐
     native clang++ (golden)                    random_visa project
     markers = inert no-ops                     macro-obf + CFF + MBA + VM
              │                                              │
   ┌──────────┴──────────┐                       ┌───────────┴───────────┐
   │ Вариант 2: Python    │                       │ Вариант 1: libFuzzer  │
   │ run_diff_project.py  │                       │ run_libfuzzer.sh      │
   │ process-streaming    │                       │ in-process, coverage- │
   │ ~10⁴ векторов        │                       │ guided, ~10⁵-10⁶ exec │
   └──────────────────────┘                       └───────────────────────┘
```

## Что тестируется

`asgard_fuzz_compute` (ULTRA) — ветвления, switch, целочисленные
add/sub/mul, xor/and/or/not, переменные ротации, unsigned div/mod,
арифметические сдвиги, double mul/add/сравнения, `cvttsd2si`,
`cvtsd2ss` (double→float через битовое переосмысление), цикл с
data-dependent числом итераций и ветвлением внутри.

`asgard_fuzz_mix` (VIRTUALIZE) — потоковый хеш над буфером вызывающего:
load'ы из памяти вне маркированного фрейма, back-edge'ы цикла,
ветвление внутри цикла (стресс для CFF-флаттенинга).

Граничные значения, которые ловит связка: `INT32_MIN/INT32_MAX`,
сдвиги на 0/31/32/63/64, walking 1s, `±0.0`, subnormals (`5e-324`),
`1e300`/`DBL_MAX` (насыщение `cvttsd2si` → `0x8000000000000000`),
пустые и 64-байтные blob'ы.

## Вариант 1 — libFuzzer (глубокий, coverage-guided)

```bash
./examples/diff_fuzz/run_libfuzzer.sh          # 60-секундная кампания
ASG_FUZZ_SECONDS=600 ./examples/diff_fuzz/run_libfuzzer.sh
ASG_FUZZ_RUNS=5000000 ./examples/diff_fuzz/run_libfuzzer.sh
ASG_FUZZ_ALLOW_NAN=1 ./examples/diff_fuzz/run_libfuzzer.sh   # + NaN/Inf паритет
ASG_FUZZ_NO_CFF=1 ASG_FUZZ_NO_MBA=1 ...        # изоляция: только VM-лифт
```

Собирает один бинарь из трёх TU: golden-ядра (нативный компиляция с
переименованием через `-D`), virtualized-TU (из
`vm_out/.asgard_build/compute_core_virtualized.cpp`) и драйвера
`LLVMFuzzerTestOneInput`. При расхождении — полный дамп входа и
`__builtin_trap()`, libFuzzer сохраняет crash-файл в `artifacts/` и
минимизирует его:

```bash
./build/diff_fuzzer -minimize_crash=1 -runs=100000 ./artifacts/crash-*
```

## Вариант 2 — Python differential runner (весь пайплайн, наглядный)

```bash
python3 examples/diff_fuzz/run_diff_project.py -n 10000
python3 examples/diff_fuzz/run_diff_project.py -n 50000 --seed 5877 --keep-going
python3 examples/diff_fuzz/run_diff_project.py --skip-build     # повторно на готовых бинарях
```

Строит `vm_out/app_native` (golden) и `vm_out/protected_proj`
(`random_visa project -d proj_src --cff --mba`), гонит вектора через
оба процесса в `--fuzz`-режиме и при расхождении печатает таблицу с
XOR-маской различия (см. формат в конце `--help`).

## Makefile

```bash
make diff-fuzz-libfuzzer    # вариант 1
make diff-fuzz-project      # вариант 2 (N=10000)
```

## Ограничения / договорённости

* Golden и VM обязаны считать с идентичной FP-семантикой x86-бейзлайна:
  mul/add разнесены по операторам, golden собирается с
  `-ffp-contract=off` (на arm64-host иначе возможен FMA-контракт и
  ложное расхождение округления).
* `static_cast<int64_t>(double)` вне диапазона — UB в абстрактной
  машине C++, но детерминированный `cvttsd2si` в кодогенерации обоих
  сторон; это осознанный тест паритета. NaN/Inf отфильтровываются,
  если не выставлен `ASG_FUZZ_ALLOW_NAN=1`.
* `random_visa project` использует threaded-движок; для stack/jit-машин
  используйте `examples/cpp_types_demo/diff_fuzz.py` (protect-режим).
* Ядра обязаны находиться текстуально в компилируемом файле
  (trampoline-адаптер сканирует исходник), поэтому `compute_core.cpp` —
  единственный носитель функций, а оба инструмента строятся из него.

## Раскладка

```
fuzz_types.h           общий layout TestPayload (40 байт, POD)
proj_src/compute_core.cpp   2 маркированных ядра (канонический текст)
proj_src/main_driver.cpp    streaming-main (--fuzz протокол)
fuzz_driver.cpp        LLVMFuzzerTestOneInput + дамп расхождений
run_libfuzzer.sh       вариант 1: сборка + кампания libFuzzer
run_diff_project.py    вариант 2: python-раннер полного пайплайна
corpus/                seed-корпус (генерируется скриптом)
vm_out/, build/, artifacts/   генерируемые артефакты
```
