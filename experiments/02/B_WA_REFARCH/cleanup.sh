#!/usr/bin/env bash

# A script that deletes any .tf files containing the words "omitted" or "brevity"
# in their contents, and then runs another command using the file name.

for file in *.tf; do
  # If no .tf files exist, skip
  [ -e "$file" ] || continue

  # Check if the file contains "omitted" or "brevity" (case-insensitive)
  if grep -Eqi 'omitted|brevity' "$file"; then
    echo "Found '$file' containing 'omitted' or 'brevity'. Deleting..."
    rm "$file"

    # Execute another command, referencing the deleted file name
    # Replace `echo` with the command you need
    MOD=$(echo $file | sed 's/_.*//')
    FMOD=$(grep $MOD ../model_list)
    TEMP=$(echo $file  | sed -n 's/^[^_]*_\([^_]*\)_.*$/\1/p')
    make one MODEL=$FMOD ITERATIONS=1 TEMPERATURE="$TEMP"
  fi
done
