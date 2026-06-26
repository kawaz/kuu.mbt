# kuu.mbt — MoonBit CLI Parser Library
#
# Canonical task runner. bump-semver canonical (kawaz/bump-semver/justfile) を
# 模倣した push / release flow を持つ。

set shell := ["bash", "-euo", "pipefail", "-c"]

set script-interpreter := ["bash", "-euo", "pipefail"]

set positional-arguments

# Default: lint + test
default: lint test

# show the recipe list
list:
    @just --list --unsorted

# === Lint ===

# Format + type check (warnings as errors)
lint: fmt-check check

# Format check only (no modification)
fmt-check:
    moon fmt --check

# Format code (auto-fix)
fmt:
    moon fmt

# Type check with warnings as errors (deprecation warnings are excluded
# pending docs/issue/2026-06-26-try-operator-migration.md +
# docs/issue/2026-06-26-assert-eq-debug-derive-migration.md)
check:
    moon check --deny-warn --warn-list -20

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

# === Push / Release flow (bump-semver canonical 模倣) ===

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

# 翻訳ペアの freshness check (= ja 正本が更新されたら en も追従しているか検証)
[private]
check-outdated-translations: ensure-clean
    bump-semver vcs outdated 'glob:**/*-ja.md' '$1/$2.md'

# src/ or moon.mod が変わったら VERSION 上げ忘れを止める
# test 専用追加 (*_wbtest.mbt) は bump 不要なので exclude
check-version-bumped: (_check-version-bumped "src/" "moon.mod" "moon.pkg")

[private]
[script]
_check-version-bumped *target_paths:
    if ! bump-semver vcs diff -q main@origin -- "$@" --excludes 'glob:src/**/*_wbtest.mbt'; then
        # 初回 release では origin/main に VERSION が無いので compare gt が exit 2 で返る (path not found)。
        # その場合は「VERSION 新規追加 = bump 済」とみなして OK 扱い。
        set +e
        bump-semver compare gt VERSION vcs:main@origin 2>/dev/null
        cmp_exit=$?
        set -e
        case "$cmp_exit" in
            0) ;;  # VERSION > origin の VERSION: OK
            2)
                echo "Initial release: origin/main has no VERSION yet, treating as bumped"
                ;;
            *)
                bump-semver compare gt VERSION vcs:main@origin  # 再度実行してエラーを表示
                exit "$cmp_exit"
                ;;
        esac
    fi

# VERSION を bump (= patch/minor/major) して release commit を作成
# VERSION + moon.mod の version フィールドを同期更新する
[script]
bump-version level="patch": ensure-clean
    bump-semver "$1" VERSION --write --quiet
    new=$(bump-semver get VERSION)
    # moon.mod の version 行を同期
    sed -i.bak -E "s/^version = \".*\"\$/version = \"${new}\"/" moon.mod && rm moon.mod.bak
    bump-semver vcs commit -m "Release v${new}" VERSION moon.mod

# push to origin/main with canonical gates
push: check-on-default-branch ci check-outdated-translations check-version-bumped
    bump-semver vcs push --branch main --jj-bookmark-auto-advance
    @echo "[hint] gh-monitor:watch-workflow --sha $(bump-semver vcs get commit-id --rev main) --on-success release.yml 'just on-success-release' kawaz/kuu.mbt"

# release.yml workflow が success になった時のフォローアクション
# (現状は version 反映確認のみ。配布物が増えたら拡張する)
on-success-release:
    @echo "Released v$(bump-semver get VERSION)"
