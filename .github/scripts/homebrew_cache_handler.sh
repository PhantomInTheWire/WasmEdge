#!/bin/bash
# Homebrew Cache Handler Script

set -e

# Parse arguments
TOOLS="$1"
ARCHIVE_PATH="$2"
CACHE_HIT="$3"
VERBOSE="${4:-false}"

if [ "$VERBOSE" = "true" ] || [ "$VERBOSE" = "yes" ]; then
    set -x
fi

# Get brew prefix
BREW_PREFIX=$(brew --prefix)

# Handle cache hit - extract archive
if [ "$CACHE_HIT" = "true" ]; then
    echo "Cache hit - extracting archive..."
    if [ -s "$ARCHIVE_PATH" ]; then
        echo "Extracting $ARCHIVE_PATH to /"
        sudo gtar --recursive-unlink -C / -Pxzf "$ARCHIVE_PATH"
        echo "Extraction complete"
    else
        echo "Archive is empty or missing: $ARCHIVE_PATH"
        exit 1
    fi
    exit 0
fi

# Handle cache miss - install and create archive
echo "Cache miss - installing tools and creating archive..."

# Create epoch file to track what gets installed
EPOCH_FILE=$(mktemp)
touch "$EPOCH_FILE"
# Try to set older timestamp (macOS compatible)
touch -A -01 "$EPOCH_FILE" 2>/dev/null || sleep 0.1
ls -la "$EPOCH_FILE"

# Install the tools
echo "Installing: $TOOLS"
brew install $TOOLS

# Find all files newer than epoch in brew prefix
echo "Scanning for installed files..."
FILE_LIST=$(mktemp)

# Find files in brew prefix that are newer than epoch
find "$BREW_PREFIX" -not -type d \( -cnewer "$EPOCH_FILE" -o -newer "$EPOCH_FILE" \) -print > "$FILE_LIST" 2>/dev/null || true

# Count files
FILE_COUNT=$(wc -l < "$FILE_LIST" | tr -d ' ')
echo "Found $FILE_COUNT files to archive"

# Filter out non-existent files and separate symlinks
FILTERED_LIST=$(mktemp)
SYMLINK_LIST=$(mktemp)

while IFS= read -r file; do
    if [ -e "$file" ] || [ -L "$file" ]; then
        if [ -L "$file" ]; then
            echo "$file" >> "$SYMLINK_LIST"
        else
            echo "$file" >> "$FILTERED_LIST"
        fi
    else
        echo "Skipping missing file: $file" >&2
    fi
done < "$FILE_LIST"

# Combine lists with symlinks at the end
cat "$FILTERED_LIST" > "$FILE_LIST"
cat "$SYMLINK_LIST" >> "$FILE_LIST"

# Count final files
FINAL_COUNT=$(wc -l < "$FILE_LIST" | tr -d ' ')
echo "Archiving $FINAL_COUNT files (including symlinks)..."

if [ "$FINAL_COUNT" -gt 0 ]; then
    # Create archive
    # Remove leading slash for tar -C /
    sed 's|^/||' "$FILE_LIST" > "${FILE_LIST}.relative"
    echo "Creating archive at $ARCHIVE_PATH..."
    sudo tar -czf "$ARCHIVE_PATH" -C / -T "${FILE_LIST}.relative"
    ls -lh "$ARCHIVE_PATH"
    echo "Archive created successfully"
else
    echo "No files to archive - creating empty archive"
    touch "$ARCHIVE_PATH"
fi

# Cleanup
rm -f "$EPOCH_FILE" "$FILE_LIST" "$FILTERED_LIST" "$SYMLINK_LIST" "${FILE_LIST}.relative"

echo "Done"
