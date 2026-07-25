---
title: option 直下 seq の名前付き子要素が kv に畳まれず、子ごとに別オブジェクト + 余分な配列階層になる
status: open
category: bug
created: 2026-07-25T22:19:13+09:00
last_read:
open_entered: 2026-07-25T22:19:13+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec) リポ
---

# option 直下 seq の名前付き子要素が kv に畳まれず、子ごとに別オブジェクト + 余分な配列階層になる

## 概要

実測 (2026-07-25、commit b24d94e9 適用後)。definition
`{"options":[{"name":"pair","long":true,"multiple":"append","seq":[{"name":"path","type":"string"},{"name":"value","type":"string"}]}]}`
に args `["--pair","/a","1","--pair","/b","2"]` を与えると、result は
`{"pair": [[{"path":"/a"},{"value":"1"}], [{"path":"/b"},{"value":"2"}]]}` になる。

spec の規定からの期待形は `{"pair": [{"path":"/a","value":"1"}, {"path":"/b","value":"2"}]}`。

実測は以下 2 点で期待形と異なる:

1. 子ごとに別オブジェクトへ分かれている (`path` と `value` が同一オブジェクトの kv に畳まれない)
2. 発火 1 回あたり余分な配列階層が 1 段付く

## 背景

根拠: DESIGN §2.4 露出規則「根から降りていって最も浅い (祖先側の) name 層で止める。その層にある
name 持ちノードを全て結果キーにする」— `pair` が最も浅い name 層なので `pair` が結果キーになり、
その子 `path`/`value` は `pair` が作る子スコープに属する。DESIGN §2.5「object は独立構造でなく
露出の帰結 — name を持つ子が並べば結果が自然に kv になる」の例も `[{name:r},{name:g},{name:b}]`
→ `{r,g,b}` と 1 つのオブジェクトに畳む形を示している。

経緯: F9 (option 上の seq が 2 個目のトークンを消費しない) の修正で seq の消費は直ったが、結果形は
この状態のまま fixture で pin されていなかった。その後 DR-120 の export_key 解決変更
(commit 67859822) で子の name 軸が完全に落ちて `[["/a","1"]]` になる回帰が発生し、commit
b24d94e9 で名前は戻ったが kv への畳み込みまでは戻っていない。

kuu-cli は現状の形に合わせて `--config-file` の読み取りを実装しているため conformance は
green だが、spec 規定とは食い違う。

## 受け入れ条件

- [ ] どちらが正か (実装が spec 違反か、spec の読みが誤りか) を DESIGN §2.4/§2.5 と DR-052 の
      露出規則から確定させる
- [ ] 確定後 spec fixture でこの断面を pin する (現状この断面を pin した fixture が 1 件も無いため、
      回帰が kuu.mbt 単体で検出できない)
- [ ] pin した fixture に合わせて kuu.mbt の実装 (または spec 側) を修正し、conformance green を維持する
