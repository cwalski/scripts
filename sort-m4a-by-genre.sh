#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: sort-m4a-by-genre.sh [SOURCE_DIR] [DEST_DIR]

Recursively finds .m4a files under SOURCE_DIR, reads each file's genre tag,
and moves the file into DEST_DIR/<genre>/.

Defaults:
  SOURCE_DIR = current directory
  DEST_DIR   = SOURCE_DIR

Requirements:
  ffprobe must be installed and available in PATH.

Options:
  Set COPY_ONLY=1 to copy files instead of moving them.
  Set UNKNOWN_GENRE_NAME to change the fallback folder name (default: Unknown).
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "Error: ffprobe is required but not installed." >&2
  exit 1
fi

SOURCE_DIR="${1:-.}"
DEST_DIR="${2:-$SOURCE_DIR}"
COPY_ONLY="${COPY_ONLY:-0}"
UNKNOWN_GENRE_NAME="${UNKNOWN_GENRE_NAME:-Unknown}"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Error: source directory not found: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

sanitize_name() {
  local value="$1"

  # Replace path separators and trim surrounding whitespace.
  value="${value//\//-}"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"

  # Collapse repeated spaces.
  value="$(printf '%s' "$value" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

  if [[ -z "$value" ]]; then
    value="$UNKNOWN_GENRE_NAME"
  fi

  printf '%s\n' "$value"
}

read_genre() {
  local file="$1"
  ffprobe \
    -v error \
    -show_entries format_tags=genre \
    -of default=noprint_wrappers=1:nokey=1 \
    "$file" 2>/dev/null | head -n 1
}

unique_target_path() {
  local dir="$1"
  local base_name="$2"
  local stem ext candidate counter

  if [[ "$base_name" == *.* ]]; then
    stem="${base_name%.*}"
    ext=".${base_name##*.}"
  else
    stem="$base_name"
    ext=""
  fi

  candidate="$dir/$base_name"
  counter=1

  while [[ -e "$candidate" ]]; do
    candidate="$dir/${stem}_${counter}${ext}"
    ((counter++))
  done

  printf '%s\n' "$candidate"
}

log_action() {
  local action="$1"
  local source_file="$2"
  local genre_dir="$3"
  local target_file="$4"

  printf '%s: %s -> %s/%s\n' \
    "$action" \
    "$(basename "$source_file")" \
    "$genre_dir" \
    "$(basename "$target_file")"
}

find "$SOURCE_DIR" -type f \( -iname '*.m4a' \) -print0 |
while IFS= read -r -d '' file; do
  genre="$(read_genre "$file" || true)"
  genre="$(sanitize_name "$genre")"

  target_dir="$DEST_DIR/$genre"
  mkdir -p "$target_dir"

  target_path="$(unique_target_path "$target_dir" "$(basename "$file")")"

  if [[ "$COPY_ONLY" == "1" ]]; then
    cp -n -- "$file" "$target_path"
    log_action "Copied" "$file" "$genre" "$target_path"
  else
    mv -- "$file" "$target_path"
    log_action "Moved" "$file" "$genre" "$target_path"
  fi
done
