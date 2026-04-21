#!/usr/bin/env bash

# Stop the script if something fails, if a variable is missing, or if a pipeline fails.
set -euo pipefail

# Turn on extra pattern matching features used later for trimming spaces.
shopt -s extglob

# Define a small help message that explains how to run this script.
usage() {
  # Print the help text exactly as written until the EOF marker.
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

# If the first argument is -h or --help, show the help message.
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  # Print the usage instructions.
  usage

  # End the script successfully after showing help.
  exit 0
fi

# Check whether ffprobe is installed before trying to read music metadata.
if ! command -v ffprobe >/dev/null 2>&1; then
  # Show an error if ffprobe cannot be found.
  echo "Error: ffprobe is required but not installed." >&2

  # Stop the script with an error code.
  exit 1
fi

# Use the first argument as the folder to scan, or use the current folder if none is given.
SOURCE_DIR="${1:-.}"

# Use the second argument as the output folder, or sort inside the source folder if none is given.
DEST_DIR="${2:-$SOURCE_DIR}"

# Choose copy mode only if COPY_ONLY=1 was set before running the script.
COPY_ONLY="${COPY_ONLY:-0}"

# Use Unknown as the folder name when a file has no genre tag.
UNKNOWN_GENRE_NAME="${UNKNOWN_GENRE_NAME:-Unknown}"

# Make sure the source folder really exists.
if [[ ! -d "$SOURCE_DIR" ]]; then
  # Tell the user which source folder was missing.
  echo "Error: source directory not found: $SOURCE_DIR" >&2

  # Stop the script with an error code.
  exit 1
fi

# Create the destination folder if it does not already exist.
mkdir -p "$DEST_DIR"

# Remember which genre folders we have already created during this run.
declare -A CREATED_DIRS=()

# Clean up a genre name so it is safe to use as a folder name.
sanitize_name() {
  # Store the text passed into this function.
  local value="$1"

  # Replace slashes with dashes so the genre does not accidentally become a path.
  value="${value//\//-}"

  # Replace new lines with spaces.
  value="${value//$'\n'/ }"

  # Replace carriage returns with spaces.
  value="${value//$'\r'/ }"

  # Replace tab characters with spaces.
  value="${value//$'\t'/ }"

  # Keep shrinking double spaces into single spaces until none are left.
  while [[ "$value" == *"  "* ]]; do
    # Replace every pair of spaces with one space.
    value="${value//  / }"
  done

  # Remove spaces from the start of the genre name.
  value="${value##+([[:space:]])}"

  # Remove spaces from the end of the genre name.
  value="${value%%+([[:space:]])}"

  # If the genre name is empty after cleanup, use the fallback name.
  if [[ -z "$value" ]]; then
    # Set the genre name to the fallback folder name.
    value="$UNKNOWN_GENRE_NAME"
  fi

  # Print the cleaned-up genre name.
  printf '%s\n' "$value"
}

# Read the genre tag from one audio file.
read_genre() {
  # Store the file path passed into this function.
  local file="$1"

  # Ask ffprobe for only the genre tag, hide errors, and use the first result.
  # -v error means normal status text is hidden.
  # -show_entries asks for only the genre field.
  # -of makes ffprobe print just the genre value.
  ffprobe -v error -show_entries format_tags=genre -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | head -n 1 || true
}

# Pick a destination file path that will not overwrite an existing file.
unique_target_path() {
  # Store the folder where the file should go.
  local dir="$1"

  # Store the original filename.
  local base_name="$2"

  # Prepare local variables used to build a safe filename.
  local stem ext candidate counter

  # Check whether the filename has an extension.
  if [[ "$base_name" == *.* ]]; then
    # Keep the filename without the final extension.
    stem="${base_name%.*}"

    # Keep the final extension, including the dot.
    ext=".${base_name##*.}"
  else
    # Use the full filename as the stem when there is no extension.
    stem="$base_name"

    # Use no extension when the filename has none.
    ext=""
  fi

  # Try the original filename first.
  candidate="$dir/$base_name"

  # Start duplicate numbering at 1.
  counter=1

  # Keep trying new names while a file with that name already exists.
  while [[ -e "$candidate" ]]; do
    # Add _1, _2, and so on before the extension.
    candidate="$dir/${stem}_${counter}${ext}"

    # Increase the number for the next try.
    ((counter++))
  done

  # Save the available file path in a variable the caller can read.
  UNIQUE_PATH="$candidate"
}

# Print a simple message describing what happened to a file.
log_action() {
  # Store the action word, such as Copied, Moved, or Skipped.
  local action="$1"

  # Store the original file path.
  local source_file="$2"

  # Store the genre folder name.
  local genre_dir="$3"

  # Store the final file path.
  local target_file="$4"

  # Print a short one-line status message.
  # The source and target parts show only filenames, not full folder paths.
  printf '%s: %s -> %s/%s\n' "$action" "${source_file##*/}" "$genre_dir" "${target_file##*/}"
}

# Find all .m4a files first, before moving anything.
mapfile -d '' FILES < <(find "$SOURCE_DIR" -type f -iname '*.m4a' -print0)

# Go through each .m4a file that was found.
for file in "${FILES[@]}"; do
  # Read the raw genre text from the file.
  genre_raw="$(read_genre "$file")"

  # Clean the genre text so it can be used as a folder name.
  genre="$(sanitize_name "$genre_raw")"

  # Keep only the filename, without the folder path.
  base_name="${file##*/}"

  # Build the folder path for this genre.
  target_dir="$DEST_DIR/$genre"

  # Check whether this genre folder has already been created during this run.
  if [[ -z "${CREATED_DIRS["$target_dir"]:-}" ]]; then
    # Create the genre folder if needed.
    mkdir -p "$target_dir"

    # Remember that this folder has now been created.
    CREATED_DIRS["$target_dir"]=1
  fi

  # Build the path the file would have if it used its original filename.
  original_target="$target_dir/$base_name"

  # Check whether the file is already in the correct place.
  if [[ -e "$original_target" && "$file" -ef "$original_target" ]]; then
    # Tell the user the file was already sorted.
    log_action "Skipped" "$file" "$genre" "$original_target"

    # Move on to the next file.
    continue
  fi

  # Pick a final path that will not overwrite another file.
  unique_target_path "$target_dir" "$base_name"

  # Store the safe destination path chosen by unique_target_path.
  target_path="$UNIQUE_PATH"

  # If copy mode is turned on, copy the file instead of moving it.
  if [[ "$COPY_ONLY" == "1" ]]; then
    # Copy the file to the genre folder.
    cp -- "$file" "$target_path"

    # Tell the user the file was copied.
    log_action "Copied" "$file" "$genre" "$target_path"
  else
    # Move the file to the genre folder.
    mv -- "$file" "$target_path"

    # Tell the user the file was moved.
    log_action "Moved" "$file" "$genre" "$target_path"
  fi
done
