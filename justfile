# kuu.mbt — MoonBit reference implementation of the kuu spec.
#
# Canonical task runner. push / release flow は kawaz/bump-semver の justfile を
# 模倣する。conformance fixtures は kawaz/kuu の正本を KUU_FIXTURES で注入する。

set shell := ["bash", "-euo", "pipefail", "-c"]

set script-interpreter := ["bash", "-euo", "pipefail"]

set positional-arguments

# default: lint + test
default: lint test

# show the recipe list
list:
    @just --list --unsorted

# ---------- lint ----------

# format check + type check (warnings as errors)
lint: fmt-check check

# format check only (no modification)
fmt-check:
    moon fmt --check

# format code (auto-fix)
fmt:
    moon fmt

# type check with warnings as errors
check:
    moon check --deny-warn

# ---------- test ----------

# run native tests (conformance fixtures via $KUU_FIXTURES; fallback = 隣接 kawaz/kuu。runner は Phase B)
test:
    fx="${KUU_FIXTURES:-{{justfile_directory()}}/../../kuu/main/fixtures}"; if [ -d "$fx" ]; then export KUU_FIXTURES="$(cd "$fx" && pwd)"; fi; moon test --target native

# run tests on all targets
test-all:
    fx="${KUU_FIXTURES:-{{justfile_directory()}}/../../kuu/main/fixtures}"; if [ -d "$fx" ]; then export KUU_FIXTURES="$(cd "$fx" && pwd)"; fi; moon test --target all

# ---------- CI ----------

# full local CI pipeline
ci: lint test

# ---------- push / release flow (bump-semver canonical 模倣) ----------

# working copy is clean (= 未コミット変更を巻き込ませない)
[private]
ensure-clean:
    bump-semver vcs is clean

# fail if the current bookmark / branch is not the default
[private]
[script]
check-on-default-branch:
    if ! bump-semver vcs is on-default-branch; then
        cur=$(bump-semver vcs get current-branch 2>/dev/null || echo "(ambiguous)")
        bn=$(bump-semver vcs get default-branch)
        printf >&2 "⚠ 現在 '%s' にいます。%s に合流してから push してください (just sync / just promote)\n" "$cur" "$bn"
        exit 1
    fi

# 現在の worktree を default branch (= origin/main) に rebase
sync:
    bump-semver vcs sync --onto $(bump-semver vcs get default-branch)@origin

# default branch bookmark を現在の commit に forward (push はしない)
promote:
    bump-semver vcs promote

# src/ or moon.mod 変更時に VERSION 上げ忘れを止める (*_wbtest.mbt は exclude)
check-version-bumped: (_check-version-bumped "src/" "moon.mod")

[private]
[script]
_check-version-bumped *target_paths:
    # VERSION=0.0.0 はプレースホルダ (MDR-001: release 休眠)。placeholder の間は
    # src 変更でも bump を要求しない — release.yml 側も 0.0.0 を skip するので対称。
    # 初回 release は kawaz の手動 `just bump-version` で開始する。
    if [ "$(tr -d '[:space:]' < VERSION)" = "0.0.0" ]; then
        echo "Placeholder VERSION (0.0.0): release dormant, skipping bump gate"
        exit 0
    fi
    # --excludes は -- の前に置く (後だと positional 扱いで exclude が無効化される)
    if ! bump-semver vcs diff -q main@origin --excludes 'glob:src/**/*_wbtest.mbt' -- "$@"; then
        # 初回 release では origin/main に VERSION が無く compare gt が exit 2 (path not found)。
        # その場合は「VERSION 新規追加 = bump 済」とみなして OK。
        set +e
        bump-semver compare gt VERSION vcs:main@origin 2>/dev/null
        cmp_exit=$?
        set -e
        case "$cmp_exit" in
            0) ;;
            2) echo "Initial release: origin/main has no VERSION yet, treating as bumped" ;;
            *) bump-semver compare gt VERSION vcs:main@origin; exit "$cmp_exit" ;;
        esac
    fi

# VERSION を bump (patch/minor/major) して release commit を作成
# VERSION + moon.mod の version フィールドを同期更新する
[script]
bump-version level="patch": ensure-clean
    bump-semver "$1" VERSION --write --quiet
    new=$(bump-semver get VERSION)
    sed -i.bak -E "s/^version = \".*\"\$/version = \"${new}\"/" moon.mod && rm moon.mod.bak
    bump-semver vcs commit -m "Release v${new}" VERSION moon.mod

# push to origin/main with canonical gates
push: check-on-default-branch ci check-version-bumped
    bump-semver vcs push --branch "$(bump-semver vcs get default-branch)" --jj-bookmark-auto-advance
    cmux-msg notify --self --text "Monitor で 'just watch' を起動して" 2>/dev/null || true

# push 後の CI / Release を SHA-pin で監視 (gh-monitor plugin)
watch:
    watch-workflow.sh --sha $(bump-semver vcs get commit-id --rev "$(bump-semver vcs get default-branch)") --on-success release.yml 'just on-success-release' kawaz/kuu.mbt

# release.yml workflow が success になった時のフォローアクション
on-success-release:
    @echo "Released v$(bump-semver get VERSION)"
