#!/usr/bin/env bash
#
# backup.sh — Archive source tree into backup directory (.tar.gz / .zip)
#

set -euo pipefail

# Determine project directory (parent of scripts/ or current folder)
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

# Default format: tar (or from BACKUP_FORMAT environment variable)
FORMAT="${BACKUP_FORMAT:-tar}"
BACKUP_DIR=""

show_help() {
    cat <<EOF
Usage: $0 [OPTIONS] [DESTINATION_DIR]

Options:
  -z, --zip       Create ZIP archive (.zip, uncompressed: zip -0)
  -t, --tar       Create TAR.GZ archive (.tar.gz) [default]
  -b, --both      Create both archives (.tar.gz and .zip)
  -h, --help      Display this help message

Examples:
  $0                  # Creates .tar.gz in ./backup
  $0 --zip            # Creates .zip in ./backup
  $0 --both           # Creates both .tar.gz and .zip
  $0 --zip /tmp/pack  # Creates .zip in target directory
EOF
}

# Parse command-line arguments
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
                echo "Error: unrecognized argument '$arg'" >&2
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

    echo "==> Packaging TAR.GZ archive: $archive_name"
    if [[ "$IS_GIT" -eq 1 ]]; then
        git ls-files --cached --others --exclude-standard | tar -czf "$archive_path" -T -
    else
        tar -czf "$archive_path" "${TAR_EXCLUDES[@]}" .
    fi

    local size
    size="$(du -h "$archive_path" | cut -f1)"
    local count
    count="$(tar -tzf "$archive_path" | wc -l | tr -d ' ')"

    echo "    Created: $archive_path"
    echo "    Size:    $size"
    echo "    Files:   $count"
}

create_zip() {
    if ! command -v zip >/dev/null 2>&1; then
        echo "Error: zip utility not found" >&2
        return 1
    fi

    local archive_name="${PROJECT_NAME}_backup_${TIMESTAMP}.zip"
    local archive_path="${BACKUP_DIR}/${archive_name}"

    # Remove existing archive with the same name if present
    rm -f "$archive_path"

    echo "==> Packaging ZIP archive (uncompressed, -0): $archive_name"
    if [[ "$IS_GIT" -eq 1 ]]; then
        git ls-files --cached --others --exclude-standard | zip -0 -q "$archive_path" -@
    else
        zip -0 -r -q "$archive_path" . "${ZIP_EXCLUDES[@]}"
    fi

    local size
    size="$(du -h "$archive_path" | cut -f1)"
    local count
    count="$(unzip -l "$archive_path" | tail -n 1 | awk '{print $(NF-1)}')"

    echo "    Created: $archive_path"
    echo "    Size:    $size"
    echo "    Files:   $count"
}

echo "========================================"
echo " Source Code Backup"
echo " Project: $PROJECT_ROOT"
echo " Target:  $BACKUP_DIR"
if [[ "$IS_GIT" -eq 1 ]]; then
    echo " Mode:    Git (tracked + untracked files, respecting .gitignore)"
else
    echo " Mode:    Tar/Zip (excluding temporary and build directories)"
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
        echo "Error: unrecognized archive format '$FORMAT'" >&2
        exit 1
        ;;
esac

echo "========================================"
echo "Done!"
