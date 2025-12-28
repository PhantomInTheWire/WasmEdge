# WasmEdge Symbol Exposure Checking

Validates `libwasmedge` exports against a whitelist to prevent unintended symbol leaks.

## Background
Issue #3743: WasmEdge 0.14.0 exposed hundreds of internal symbols due to CMake changes.  
This check avoids such regressions.

## Components
- `check_symbols.sh`: Cross-platform validation script  
- `whitelist.symbols`: Approved exported symbols  

## Usage
```bash
bash .github/scripts/check_symbols.sh
```

Steps:

1. Extracts symbols (`nm`/`dumpbin`)
2. Compares with whitelist
3. Reports extra (CI fail) / missing (warn)

## Platform Support

* Linux: `nm -D --defined-only`
* macOS: `nm -g` (strip `_`)
* Windows: `dumpbin //EXPORTS` (objdump fallback)
* Static builds: auto-skipped

## Updating Whitelist

Make sure to add new API symbols alphabetically
