# kuu.mbt — MoonBit reference implementation of the kuu spec.
#
# Canonical task runner. push / release flow は kawaz/bump-semver の justfile を
# 模倣する。conformance fixtures は kawaz/kuu の正本を KUU_FIXTURES で注入する。

set shell := ["bash", "-euo", "pipefail", "-c"]

set script-interpreter := ["bash", "-euo", "pipefail"]

set positional-arguments

# `moon info` の対象パッケージ / その生成物。CI の「Check public interface drift」job と
# 同一の集合を保つ (片方だけ増やすと drift 検査に穴が空く)。
mbti_packages := "src/abi src/extension src/internal/engine src/internal/fold src/kuu-node src/builtins src/kuu"
mbti_files := "src/abi/pkg.generated.mbti src/extension/pkg.generated.mbti src/internal/engine/pkg.generated.mbti src/internal/fold/pkg.generated.mbti src/kuu-node/pkg.generated.mbti src/builtins/pkg.generated.mbti src/kuu/pkg.generated.mbti"

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

# regenerate committed public API interfaces
mbti:
    moon info {{mbti_packages}}

# 公開 API interface (pkg.generated.mbti) が現在のソースと同期しているか
#
# CI の「Check public interface drift」job (.github/workflows/ci.yml) のローカル版で、
# `moon info` の対象パッケージと diff 対象の 6 ファイルは CI と同一 (mbti_packages /
# mbti_files を両者が共有すべき集合として持つ)。v0.1.0 push で「mbti 再生成を一部忘れた
# まま `just ci` が green」だった穴を push 前に塞ぐ。
#
# 比較の基準線だけ CI と異なる: CI は fresh checkout なので「コミット済み mbti vs 再生成
# 結果」を見るが、ローカルで同じことをすると **公開 API を触った作業途中 (src も mbti も
# 未コミット) が常に fail** になり、開発中ずっと `just ci` が赤くなる。そこで基準線は
# 「再生成前の作業コピー vs 再生成結果」= 「mbti が今のソースと同期しているか」にする。
# 報告された事故 (再生成し忘れ = 作業コピーの mbti が古い) はこれで捕まる。
#
# 検査自体が作業コピーを汚さないよう、不一致なら 6 ファイルとも復元してから落とす
# (`check-templates` と同じ作法 — gate は `just mbti` を自分で実行するまで赤のままにする)。

# public API interface (pkg.generated.mbti) の drift 検査
[script]
mbti-check:
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    for f in {{mbti_files}}; do
        mkdir -p "$tmp/$(dirname "$f")"
        cp "$f" "$tmp/$f"
    done
    moon info {{mbti_packages}}
    drift=0
    for f in {{mbti_files}}; do
        if ! diff -u "$tmp/$f" "$f" --label "$f (working copy)" --label "$f (regenerated)"; then
            drift=1
        fi
    done
    if [ "$drift" -ne 0 ]; then
        for f in {{mbti_files}}; do cp "$tmp/$f" "$f"; done
        printf >&2 "\n\033[31mpublic interface drift: pkg.generated.mbti が現在のソースと同期していません\033[0m\n"
        printf >&2 "  'just mbti' を実行して結果を commit してください。\n"
        exit 1
    fi
    echo "OK: pkg.generated.mbti は現在のソースと同期しています"

# ---------- completion templates (M2 — DR-117 §2.5 + findings §2 UXL-Q2=a) ----------

# transcribe spec templates/completion.{zsh,bash,fish} -> src/kuu/completion_templates.mbt
gen-templates:
    ./scripts/gen-completion-templates.sh

# check that src/kuu/completion_templates.mbt is in sync with spec templates/
# (regenerate into a tempfile, diff against committed file, restore on mismatch so
# the check itself does not leave the working copy dirty)
[script]
check-templates:
    target="src/kuu/completion_templates.mbt"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    cp "$target" "$tmp"
    ./scripts/gen-completion-templates.sh >/dev/null
    if ! diff -u "$tmp" "$target"; then
        cp "$tmp" "$target"
        printf >&2 "\n\033[31mcompletion_templates.mbt is out of sync with spec templates/\033[0m\n"
        printf >&2 "  run 'just gen-templates' and commit the result.\n"
        exit 1
    fi
    echo "OK: completion_templates.mbt is in sync with spec templates/"

# ---------- test ----------

# run native tests (conformance fixtures via $KUU_FIXTURES; fallback = 隣接 kawaz/kuu。runner は Phase B)
test:
    fx="${KUU_FIXTURES:-{{justfile_directory()}}/../../kuu/main/fixtures}"; if [ -d "$fx" ]; then export KUU_FIXTURES="$(cd "$fx" && pwd)"; fi; moon test --target native

# run tests on all targets
test-all:
    fx="${KUU_FIXTURES:-{{justfile_directory()}}/../../kuu/main/fixtures}"; if [ -d "$fx" ]; then export KUU_FIXTURES="$(cd "$fx" && pwd)"; fi; moon test --target all

# ---------- coverage ----------
#
# 目的は見逃しの可視化。CI の coverage job (.github/workflows/ci.yml) が同じ手順で
# 計測し、summary をジョブログへ、HTML を artifact (coverage-html) へ出す。
# **閾値 gate は置かない** — 数字で落とすのではなく、未到達の行を読むための材料。
# 下の recipe はそのローカル版で、`just ci` にも push の deps にも入れない。
# 計測対象は src/ 配下のみで、moonbitlang/core など .mooncakes の依存は moon 側が
# 自動で除外する。

# native テストを instrumentation 付きで実行し、ファイル別の行カバレッジを表示
[script]
coverage:
    fx="${KUU_FIXTURES:-{{justfile_directory()}}/../../kuu/main/fixtures}"
    if [ -d "$fx" ]; then export KUU_FIXTURES="$(cd "$fx" && pwd)"; fi
    # 前回の trace が残っていると集計に混ざるので必ず落とす
    moon coverage clean
    # conformance runner の decoded 一覧が数十 KB あるため成功時は最終行だけ出す
    # (失敗時は全文を stderr へ流してから中断)
    log="$(mktemp)"
    trap 'rm -f "$log"' EXIT
    if ! moon test --target native --enable-coverage >"$log" 2>&1; then
        cat >&2 "$log"
        exit 1
    fi
    tail -1 "$log"
    moon coverage report -f summary

# 行単位で未到達箇所を色分けした HTML レポートを _coverage/index.html に出力
coverage-html: coverage
    moon coverage report -f html
    @echo "open _coverage/index.html"

# ---------- CI ----------

# full local CI pipeline
ci: lint mbti-check test

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
