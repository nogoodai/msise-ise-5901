#!/bin/bash

# Function to parse and clean up related files and directories
parse_and_cleanup_filename() {
    local filename="$1"
    
    # Determine base name by removing the .results extension
    local base_name="${filename%.results}"

    echo "Removing files and directory related to $base_name"
    # Remove the scan output directory if it exists
    if [ -d "$base_name.json" ]; then
      rm -rf "$base_name.json"
    fi
    # Remove the .results file, the base file, and the .json file
    rm -f "$filename" "$base_name"
}

# Search for pattern '0,0,0,0' in *.results files in the current directory
pattern='0,0,0,0'

echo "Searching in the current directory..."
for file in ./*.results; do
    if [ -f "$file" ]; then
        if grep -q "$pattern" "$file"; then
            match=$(grep "$pattern" "$file")
            echo "Match found in: $(basename "$file"):$match"
            parse_and_cleanup_filename "$(basename "$file")"
        fi
    fi
done

