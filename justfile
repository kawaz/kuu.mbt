# kuu.mbt — MoonBit CLI Parser Library

# Default: lint + test
default: lint test

# === Lint ===

# Format + type check (warnings as errors)
lint: fmt-check check

# Format check only (no modification)
fmt-check:
    moon fmt --check

# Format code (auto-fix)
fmt:
    moon fmt

# Type check with warnings as errors
check:
    moon check --deny-warn

# === Test ===

# Run tests (native target)
test:
    moon test --target native

# Run tests on all targets
test-all:
    moon test --target all

# Update snapshot tests
test-update:
    moon test --update

# === Coverage ===

# Run tests with coverage (summary)
coverage:
    moon coverage analyze -- -f summary

# Run tests with coverage (HTML report)
coverage-html:
    moon coverage analyze -- -f html
    @echo "Open _coverage/index.html"

# Clean coverage artifacts
coverage-clean:
    moon coverage clean

# === Build ===

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
    wasm_gc="$base/wasm-gc/release/build/_size_check/_size_check.wasm"
    wasm="$base/wasm/release/build/_size_check/_size_check.wasm"
    js="$base/js/release/build/_size_check/_size_check.js"
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

# === Utilities ===

# Generate type definition files (.mbti)
info:
    moon info

# Generate and serve API docs
doc:
    moon doc --serve

# Clean build artifacts
clean:
    moon clean

# === WASM ===

# Build WASM bridge (release)
wasm-build:
    moon build --target wasm-gc --package kawaz/kuu/wasm --release

# Run WASM integration tests (requires Node.js)
wasm-test: wasm-build
    node src/wasm/test.mjs

# === Examples ===

# Run all MoonBit example tests
example-test:
    #!/usr/bin/env bash
    set -euo pipefail
    failed=0
    for dir in examples/*/; do
        if [ -f "$dir/moon.mod.json" ]; then
            echo "=== Testing $dir ==="
            (cd "$dir" && moon test) || failed=1
        fi
    done
    exit $failed

# === CI ===

# Full CI pipeline: lint → test → wasm → examples → coverage
ci: lint test wasm-test example-test coverage

# Pre-release check: lint → test-all → wasm → examples → info
release-check: lint test-all wasm-test example-test info

# === Push gates (= ast 議論を進めるための最低限。OSS リリース前に bump-semver canonical 模倣で拡充予定) ===

# working copy clean check (= 未コミット変更を巻き込ませない)
[private]
ensure-clean:
    bump-semver vcs is clean

# default branch (= main) bookmark に居るかを確認
[private]
[script]
check-on-default-branch:
    if ! bump-semver vcs is on-default-branch; then
        cur=$(bump-semver vcs get current-branch 2>/dev/null || echo "(ambiguous)")
        bn=$(bump-semver vcs get default-branch)
        printf >&2 "⚠ 現在 '%s' bookmark/branch にいます。%s に合流してから push してください\n  1. just sync         # %s@origin に rebase\n  2. just promote      # %s bookmark を current commit に forward\n" "$cur" "$bn" "$bn" "$bn"
        exit 1
    fi

# 現在の worktree を default branch (= origin/<default>) に rebase
sync:
    bump-semver vcs sync --onto $(bump-semver vcs get default-branch)@origin

# default branch bookmark を現在の commit に forward (push しない)
promote:
    bump-semver vcs promote

# push to origin/main with minimal gates (= ensure-clean → ci → push)
# OSS リリースで release.yml + VERSION + check-outdated-translations + check-version-bumped を
# 連動する canonical 構成に拡充予定。
push: check-on-default-branch ensure-clean ci
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
