#!/usr/bin/env bash
#
# backup.sh — Создание архива исходного кода в папку backup (.tar.gz / .zip)
#

set -euo pipefail

# Определение директории проекта (директория на уровень выше scripts/ или текущая папка)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/dune-project" || -d "$SCRIPT_DIR/.git" ]]; then
    PROJECT_ROOT="$SCRIPT_DIR"
elif [[ -f "$SCRIPT_DIR/../dune-project" || -d "$SCRIPT_DIR/../.git" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    PROJECT_ROOT="$(pwd)"
fi

PROJECT_NAME="$(basename "$PROJECT_ROOT")"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"

# Формат по умолчанию: tar (или из переменной окружения BACKUP_FORMAT)
FORMAT="${BACKUP_FORMAT:-tar}"
BACKUP_DIR=""

show_help() {
    cat <<EOF
Использование: $0 [ОПЦИИ] [ПАПКА_НАЗНАЧЕНИЯ]

Опции:
  -z, --zip       Создать ZIP-архив (.zip, без сжатия: zip -0)
  -t, --tar       Создать TAR.GZ-архив (.tar.gz) [по умолчанию]
  -b, --both      Создать оба архива (.tar.gz и .zip)
  -h, --help      Показать эту справку

Примеры:
  $0                  # Создает .tar.gz в ./backup
  $0 --zip            # Создает .zip в ./backup
  $0 --both           # Создает и .tar.gz, и .zip
  $0 --zip /tmp/pack  # Создает .zip в указанной папке
EOF
}

# Разбор аргументов командной строки
for arg in "$@"; do
    case "$arg" in
        -z|--zip|zip)
            FORMAT="zip"
            ;;
        -t|--tar|tar)
            FORMAT="tar"
            ;;
        -b|--both|both)
            FORMAT="both"
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$BACKUP_DIR" ]]; then
                BACKUP_DIR="$arg"
            else
                echo "Ошибка: неизвестный аргумент '$arg'" >&2
                show_help
                exit 1
            fi
            ;;
    esac
done

BACKUP_DIR="${BACKUP_DIR:-$PROJECT_ROOT/backup}"
mkdir -p "$BACKUP_DIR"

cd "$PROJECT_ROOT"

IS_GIT=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    IS_GIT=1
fi

TAR_EXCLUDES=(
    --exclude="./backup"
    --exclude="backup"
    --exclude="./_build"
    --exclude="_build"
    --exclude="./build"
    --exclude="build"
    --exclude="./.git"
    --exclude=".git"
    --exclude="./.DS_Store"
    --exclude=".DS_Store"
    --exclude="*.tar.gz"
    --exclude="*.zip"
    --exclude="./scratch"
    --exclude="scratch"
    --exclude="./output"
    --exclude="output"
    --exclude="__pycache__"
)

ZIP_EXCLUDES=(
    -x
    "*.git*"
    "*_build*"
    "*backup*"
    "*.DS_Store*"
    "*.tar.gz*"
    "*.zip*"
    "*scratch*"
    "*output*"
    "*__pycache__*"
)

create_tar() {
    local archive_name="${PROJECT_NAME}_backup_${TIMESTAMP}.tar.gz"
    local archive_path="${BACKUP_DIR}/${archive_name}"

    echo "==> Упаковка TAR.GZ архива: $archive_name"
    if [[ "$IS_GIT" -eq 1 ]]; then
        git ls-files --cached --others --exclude-standard | tar -czf "$archive_path" -T -
    else
        tar -czf "$archive_path" "${TAR_EXCLUDES[@]}" .
    fi

    local size
    size="$(du -h "$archive_path" | cut -f1)"
    local count
    count="$(tar -tzf "$archive_path" | wc -l | tr -d ' ')"

    echo "    ✓ Создан: $archive_path"
    echo "    Размер:   $size"
    echo "    Файлов:   $count"
}

create_zip() {
    if ! command -v zip >/dev/null 2>&1; then
        echo "Ошибка: утилита zip не найдена в системе" >&2
        return 1
    fi

    local archive_name="${PROJECT_NAME}_backup_${TIMESTAMP}.zip"
    local archive_path="${BACKUP_DIR}/${archive_name}"

    # Удаляем существующий архив с тем же именем, если есть
    rm -f "$archive_path"

    echo "==> Упаковка ZIP архива (без сжатия, -0): $archive_name"
    if [[ "$IS_GIT" -eq 1 ]]; then
        git ls-files --cached --others --exclude-standard | zip -0 -q "$archive_path" -@
    else
        zip -0 -r -q "$archive_path" . "${ZIP_EXCLUDES[@]}"
    fi

    local size
    size="$(du -h "$archive_path" | cut -f1)"
    local count
    count="$(unzip -l "$archive_path" | tail -n 1 | awk '{print $(NF-1)}')"

    echo "    ✓ Создан: $archive_path"
    echo "    Размер:   $size"
    echo "    Файлов:   $count"
}

echo "========================================"
echo " Резервное копирование исходников"
echo " Проект: $PROJECT_ROOT"
echo " Папка:  $BACKUP_DIR"
if [[ "$IS_GIT" -eq 1 ]]; then
    echo " Режим:  Git (отслеживаемые + новые файлы, исключая .gitignore)"
else
    echo " Режим:  Tar/Zip (исключая временные каталоги и сборку)"
fi
echo "========================================"

case "$FORMAT" in
    tar)
        create_tar
        ;;
    zip)
        create_zip
        ;;
    both)
        create_tar
        echo ""
        create_zip
        ;;
    *)
        echo "Ошибка: неизвестный формат архива '$FORMAT'" >&2
        exit 1
        ;;
esac

echo "========================================"
echo "Готово!"
