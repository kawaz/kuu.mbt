# MoonBit Project Commands

# Default: check + test
default: check test

# Format code
fmt:
    moon fmt

# Type check
check:
    moon check --deny-warn

# Run tests
test:
    moon test

# Update snapshot tests
test-update:
    moon test --update

# Generate type definition files (.mbti)
info:
    moon info

# Clean build artifacts
clean:
    moon clean

# Run tests on all targets
test-all:
    moon test --target all

# Build release for all targets (wasm-gc, wasm, js)
build-release:
    moon build --target wasm-gc --release
    moon build --target wasm --release
    moon build --target js --release

# Show binary sizes for _size_check package
size: build-release
    #!/usr/bin/env bash
    set -euo pipefail
    base=_build
    wasm_gc="$base/wasm-gc/release/build/src/_size_check/_size_check.wasm"
    wasm="$base/wasm/release/build/src/_size_check/_size_check.wasm"
    js="$base/js/release/build/src/_size_check/_size_check.js"
    minified="/tmp/kuu-minified.js"
    bun build --minify "$js" --outfile "$minified" 2>/dev/null
    printf "%-20s %8s %8s %8s %8s\n" "Target" "Raw" "gzip-9" "zstd-22" "brotli"
    printf "%-20s %8s %8s %8s %8s\n" "------" "---" "------" "-------" "------"
    for label_file in "WASM-GC:$wasm_gc" "WASM:$wasm" "JS:$js" "JS(minify):$minified"; do
        label="${label_file%%:*}"
        file="${label_file#*:}"
        raw=$(wc -c < "$file")
        gz=$(gzip -9 -c "$file" | wc -c)
        zst=$(zstd --ultra -22 -c "$file" 2>/dev/null | wc -c)
        br=$(brotli --best -c "$file" 2>/dev/null | wc -c)
        printf "%-20s %7.1fK %7.1fK %7.1fK %7.1fK\n" "$label" "$(echo "$raw/1024" | bc -l)" "$(echo "$gz/1024" | bc -l)" "$(echo "$zst/1024" | bc -l)" "$(echo "$br/1024" | bc -l)"
    done

# Pre-release check
release-check: fmt info check test
