# slice justfile — 垂直スライス PoC 枝の push 経路
#
# slice は conformance fixture の蒸留元 + 最小 fixture runner のホスト。
# push は slice bookmark のみ (main / kuu-v0 は触らない)。

set shell := ["bash", "-euo", "pipefail", "-c"]

# default behaviour: alias for `list`
default: list

# show the recipe list
list:
    @just --list --unsorted

# poc の全テスト
#
# JSON 直読み conformance runner (json_conformance_wbtest.mbt) が fixtures を実食する。
# fixtures root は $KUU_FIXTURES を優先、無ければ隣接 kuu リポの絶対パスを解決して渡す。
# それも見つからなければ未設定のまま moon test に渡し、runner 側の相対 fallback
# (moon-test cwd = poc からの ../../../kuu/main/fixtures) が効く。
test:
    fx="${KUU_FIXTURES:-{{justfile_directory()}}/../../kuu/main/fixtures}"; if [ -d "$fx" ]; then export KUU_FIXTURES="$(cd "$fx" && pwd)"; fi; cd "{{justfile_directory()}}/poc" && moon test

# slice bookmark を @- 先端へ forward して origin へ push (test gate 付き)
push: test
    jj bookmark set slice -r @-
    jj git push --remote origin --bookmark slice
