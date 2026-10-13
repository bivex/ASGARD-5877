#!/usr/bin/env bash
#
# backup.sh — Создание архива исходного кода в папку backup
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
BACKUP_DIR="${1:-$PROJECT_ROOT/backup}"
TIMESTAMP="$(date +"%Y%m%d_%H%M%S")"
ARCHIVE_NAME="${PROJECT_NAME}_backup_${TIMESTAMP}.tar.gz"
ARCHIVE_PATH="${BACKUP_DIR}/${ARCHIVE_NAME}"

# Создание целевой директории
mkdir -p "$BACKUP_DIR"

echo "==> Создание архива исходников..."
echo "    Проект:  $PROJECT_ROOT"
echo "    Папка:   $BACKUP_DIR"
echo "    Архив:   $ARCHIVE_NAME"

cd "$PROJECT_ROOT"

# Если проект находится в Git-репозитории, используем git ls-files:
# это включает все отслеживаемые и неотслеживаемые исходники, но гарантированно игнорирует всё из .gitignore
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "    Режим:   Git (исходники + неотслеживаемые файлы, исключая .gitignore)"
    git ls-files --cached --others --exclude-standard | tar -czf "$ARCHIVE_PATH" -T -
else
    echo "    Режим:   Стандартный tar (с фильтрацией бинарников и временных файлов)"
    tar -czf "$ARCHIVE_PATH" \
        --exclude="./backup" \
        --exclude="backup" \
        --exclude="./_build" \
        --exclude="_build" \
        --exclude="./build" \
        --exclude="build" \
        --exclude="./.git" \
        --exclude=".git" \
        --exclude="./.DS_Store" \
        --exclude=".DS_Store" \
        --exclude="*.tar.gz" \
        --exclude="*.zip" \
        --exclude="./scratch" \
        --exclude="scratch" \
        --exclude="./output" \
        --exclude="output" \
        --exclude="__pycache__" \
        .
fi

# Информация о созданном архиве
ARCHIVE_SIZE="$(du -h "$ARCHIVE_PATH" | cut -f1)"
FILES_COUNT="$(tar -tzf "$ARCHIVE_PATH" | wc -l | tr -d ' ')"

echo "==> Успешно создано!"
echo "    Путь:    $ARCHIVE_PATH"
echo "    Размер:  $ARCHIVE_SIZE"
echo "    Файлов:  $FILES_COUNT"
