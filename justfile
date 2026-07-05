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
test:
    cd poc && moon test

# slice bookmark を @- 先端へ forward して origin へ push (test gate 付き)
push: test
    jj bookmark set slice -r @-
    jj git push --remote origin --bookmark slice
