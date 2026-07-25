---
title: config_file option を 2 つ持つ定義で前段の config が解決されない
status: open
category: bug
created: 2026-07-25T22:56:26+09:00
last_read:
open_entered: 2026-07-25T22:56:26+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 自リポ TODO
---

# config_file option を 2 つ持つ定義で前段の config が解決されない

## 概要

2026-07-25 に kuu-cli の seq 追従作業中に観測 (今回の変更とは独立)。
`config_file` 型 option を 2 つ持つ definition で `--config-file` を 2 発
撃つと、後段 option の default path に対応する値だけが解決され、前段の値が
結果に出なかった。両 entry は map に載っている状態だったので、config
source ladder 側の規定または実装の問題と思われる (要調査)。

## 背景

DR-050 (config ファイル値源) / DESIGN §14.3 の規定を確認し、複数
config_file option がある場合の解決規則が spec にあるかを先に調べること。
spec に規定が無ければそれ自体がギャップなので、実装を直す前に spec 側の
裁定が要る。

再現手順を最小形で固定してから着手すること。観測は kuu-cli 経由なので、
kuu.mbt 単体 (conformance runner か wbtest) でも再現するかの確認から
始める。

## 受け入れ条件

- [ ] DR-050 / DESIGN §14.3 に複数 config_file option の解決規則が
      規定されているか確認済み (無ければ spec 裁定を先行)
- [ ] kuu.mbt 単体での最小再現手順を固定
- [ ] 前段・後段両方の config 値が期待どおり解決される
