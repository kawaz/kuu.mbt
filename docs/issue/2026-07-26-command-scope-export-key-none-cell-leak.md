---
title: command scope の export_key rename があると type:none セルが result / sources に漏れる
status: open
category: bug
created: 2026-07-26T13:35:43+09:00
last_read:
open_entered: 2026-07-26T13:35:43+09:00
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

# command scope の export_key rename があると type:none セルが result / sources に漏れる

## 概要

`command` に `export_key` を指定して結果スコープを rename すると、その配下の `type: none` セルが
result に現れる。DR-089「none は値を運ばず result にキーが現れない」に違反。

**今回の sources 修正 (2026-07-26) とは独立な既存 bug** であることを実測で確認済み (下記「回帰ではない証拠」)。

## 背景

### 再現手順と実出力 (2026-07-26 実測)

kuu-cli の compiled binary 経由 (`deps/kuu.mbt` は本リポ working copy への symlink)。
測定前に `(cd <kuu-cli>/impl/mbt && direnv exec . just generate-self-definition && direnv exec . moon build --target native)` を通している。

#### 違反ケース: command scope に export_key がある

```json
{"commands":[{"type":"command","name":"serve","export_key":"sv","options":[
  {"name":"touch","type":"none","long":true},{"name":"keep","type":"flag","long":true,"export_key":"k"}]}]}
```

```
$bin parse def.json --no-env --no-config -- serve --touch --keep
```

```json
{"result":  {"sv": {"touch": true, "k": true}},
 "sources": {"sv.touch": "cli", "sv.k": "cli"}}
```

`touch` は `type: none` なので result にも sources にも現れてはいけない。

#### 対照: scope rename が無ければ正しく消える

```json
{"commands":[{"type":"command","name":"serve","options":[
  {"name":"touch","type":"none","long":true},{"name":"keep","type":"flag","long":true,"export_key":"k"}]}]}
```

```json
{"result": {"serve": {"k": true}}, "sources": {"serve.k": "cli"}}
```

`touch` が消えている。**command の export_key を足すか外すかだけで none の除外が効いたり効かなかったりする。**

### 回帰ではない証拠 (修正前の実測)

sources の export_key 修正 (2 commit) を入れる前の状態 (`main` = `0c0d44da`) に @ を置き、
kuu-cli を再ビルドして同じ定義を流した:

```
修正前:  result={"sv":{"touch":true,"k":true}}   sources={"serve.keep":"cli"}
修正後:  result={"sv":{"touch":true,"k":true}}   sources={"sv.touch":"cli","sv.k":"cli"}
```

**result 側の漏れは修正前から存在する。** sources に現れるようになったのは、修正が sources を result と
同じキー体系に揃えた結果であって、sources 側の振る舞いとしては正しい (result にあるものを報告している)。
根本原因は result 側にある。

### 原因 (レビュー指摘 + コード確認)

`src/kuu/resolve.mbt:926-938` が binds を export map に通す一方、`none_cells` は raw path / name のまま
`build_result` へ渡している。`:518-520` で mapped な result path と raw な none path を比較するため、
scope rename があると除外判定が一致しない。

`src/kuu/front_door.mbt:692-709` も mapped な SourceEntry を raw none path/name と照合しており、
sources 側にも同じ非対称がある。

## 受け入れ条件

- [ ] `NoneCell` の path / name も bindings / defaults / accum と同じ export map (`walk_export_path` +
      `exposed_cell`) を通る。あるいは内部セルの除外を射影**前**に完了させる
- [ ] 上記の違反ケースで `touch` が result / sources / effects のいずれにも現れない
- [ ] command scope rename × none の交差を pin する fixture が spec 側にある。
      identity / renamed (`export_key: "sv"`) / transparent (`export_key: null`) の 3 境界を covering する

## 関連

- spec `docs/decisions/DR-089-type-none-value-space.md` (:13, :23) — none は値を運ばず result にキーが現れない
- spec `fixtures/value-typing/none-value-space.json` — none の除外を pin する既存 fixture (command scope rename との交差なし)
- `src/kuu/resolve.mbt:926-938` (`build_result_export`) / `:518-520` (none 除外の比較)
- `src/kuu/front_door.mbt:692-709` (`project_sources`)
- 同時期の sources 修正: archive の `2026-07-25-sources-projection-skips-export-key-under-commands.md`
