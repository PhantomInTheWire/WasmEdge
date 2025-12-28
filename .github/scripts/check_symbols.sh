#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2024 Second State INC

# Script to check that libwasmedge doesn't expose unnecessary symbols

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMBOLS_PATH="${SYMBOLS_PATH:-"${SCRIPT_DIR%/.github/scripts}"}"
WHITELIST_FILE="$SCRIPT_DIR/whitelist.symbols"

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    LIB_PATH="$SYMBOLS_PATH/build/lib/api/libwasmedge.so"
elif [[ "$OSTYPE" == "darwin"* ]]; then
    LIB_PATH="$SYMBOLS_PATH/build/lib/api/libwasmedge.dylib"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    LIB_PATH="$SYMBOLS_PATH/build/lib/api/wasmedge.dll"
else
    echo "Unsupported OS: $OSTYPE" >&2
    exit 1
fi

if [ ! -f "$LIB_PATH" ]; then
    ALT_PATHS=()
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        ALT_PATHS+=("$SYMBOLS_PATH/build/lib/libwasmedge.so")
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        ALT_PATHS+=("$SYMBOLS_PATH/build/lib/libwasmedge.dylib")
    elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
        ALT_PATHS+=("$SYMBOLS_PATH/build/bin/wasmedge.dll")
        ALT_PATHS+=("$SYMBOLS_PATH/build/lib/wasmedge.dll")
    fi
    for alt_path in "${ALT_PATHS[@]}"; do
        if [ -f "$alt_path" ]; then
            LIB_PATH="$alt_path"
            break
        fi
    done
    if [ ! -f "$LIB_PATH" ]; then
        echo "Library not found" >&2
        exit 1
    fi
fi

if [ ! -f "$WHITELIST_FILE" ]; then
    echo "Whitelist file not found" >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    if command -v dumpbin >/dev/null 2>&1; then
        dumpbin //EXPORTS "$LIB_PATH" | awk '/^[[:space:]]*[0-9]+[[:space:]]+[0-9A-Fa-f]+[[:space:]]+[0-9A-Fa-f]+[[:space:]]+/ {print $4}' | grep -E "^WasmEdge" | sort > "$TEMP_DIR/extracted.symbols"
    elif command -v objdump >/dev/null 2>&1; then
        objdump -p "$LIB_PATH" | grep -E "^\s*\[[[:space:]]*[0-9]+\]" | grep "WasmEdge" | awk '{print $NF}' | sort > "$TEMP_DIR/extracted.symbols"
    else
        echo "No tool to extract symbols" >&2
        exit 1
    fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
    nm "$LIB_PATH" | grep "_WasmEdge" | awk '{print substr($NF,2)}' | sort > "$TEMP_DIR/extracted.symbols"
else
    nm -D --defined-only "$LIB_PATH" | awk '/^[0-9a-fA-F]+ [TBDW] / {print $3}' | grep -E "^WasmEdge" | sort > "$TEMP_DIR/extracted.symbols"
fi

if [ ! -s "$TEMP_DIR/extracted.symbols" ]; then
    echo "No symbols extracted" >&2
    exit 1
fi

sort "$WHITELIST_FILE" > "$TEMP_DIR/whitelist_sorted.symbols"

grep -Fxv -f "$TEMP_DIR/whitelist_sorted.symbols" "$TEMP_DIR/extracted.symbols" > "$TEMP_DIR/unexpected.symbols" || true
grep -Fxv -f "$TEMP_DIR/extracted.symbols" "$TEMP_DIR/whitelist_sorted.symbols" > "$TEMP_DIR/missing.symbols" || true

UNEXPECTED_COUNT=$(wc -l < "$TEMP_DIR/unexpected.symbols")
MISSING_COUNT=$(wc -l < "$TEMP_DIR/missing.symbols")

if [ "$UNEXPECTED_COUNT" -gt 0 ]; then
    echo "Unexpected symbols:" >&2
    cat "$TEMP_DIR/unexpected.symbols" >&2
    exit 1
fi

if [ "$MISSING_COUNT" -gt 0 ]; then
    echo "Missing symbols:" >&2
    cat "$TEMP_DIR/missing.symbols" >&2
fi

echo "Symbol check passed"
