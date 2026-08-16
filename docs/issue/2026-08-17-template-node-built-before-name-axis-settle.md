---
title: definitions.templates の Node が name 軸 settle 前に構築され、inline seq と結果キーが割れる
status: open
category: bug
created: 2026-08-17T08:37:30+09:00
last_read:
open_entered: 2026-08-17T08:37:30+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー B4 (R5 M1) / 即修サイクルで着手・撤回
---

# definitions.templates の Node が name 軸 settle 前に構築され、inline seq と結果キーが割れる

## 概要

DR-078 §1 は「inline `seq` と `ref` テンプレは**同じ構造の別の書き口**」と定め、DR-136 §4 は
name 軸の供給を decode 境界で 1 度だけ行うと定める。しかし `definitions.templates` の宣言は
`settle_name_axes` を通らないため、**同じ内容を inline で書くか ref で書くかで結果キーが割れる**。

## 再現 (実測)

```json
{"definitions": {"templates": {"t": {"seq": [{"name": "file path", "type": "string"}]}}},
 "positionals": [
   {"name": "viaref", "ref": "t"},
   {"name": "inline", "seq": [{"name": "file path", "type": "string"}]}]}
```
```
args: ["a", "b"]
  got  {inline: {file_path: "b"}, viaref: {"file path": "a"}}
  want 両方 file_path (id 軸写像後)
```

## 根本原因

`dec_templates` → `dec_template_body` が **decode 時に JSON から Node を直接構築**する:

```
inline seq : JSON → ElementDef → settle_name_axes → lowering が Node 構築   (軸が乗る)
template   : JSON → Node を直接構築 (+ 宣言も別途保持)                        (軸が乗らない)
```

`front_door` の `settle_name_axes` は `Definition` を受け取るが、テンプレは `Definition` の
外の `template_declarations : Map[String, ElementDef]` に住んでいるため、そもそも届かない。

## 試して外した修正 (撤回済み)

`settle_template_name_axes` を新設し、`settle_name_axes` の直後に
`template_declarations` へ適用した。**効かない** — 宣言 map を後から settle しても、
既に構築済みの **Node の binding 名は変わらない**ため。実測でも `viaref` は `file path` の
ままだった。「settle を templates にも適用すれば直る」という統合報告 (R5 M1) の見立ては
この点で浅い。

## 正しい修正方向

**テンプレの Node 構築を lowering まで遅らせ、inline seq と同じ順序にする**:

1. `dec_templates` は宣言 (`ElementDef`) の収集だけを行い、Node は作らない
2. `settle_name_axes` と同じ境界でテンプレ宣言の軸も確定させる
3. lowering が settle 済み宣言から Node を構築する (inline seq と同一経路)

decode→Node の非対称を解消する構造変更なので、即修枠ではなく設計変更として扱う。

## 受け入れ条件

- [ ] 上記再現で `viaref` / `inline` の結果キーが一致する
- [ ] テンプレ宣言の name 軸供給が decode 境界 1 箇所に閉じている (DR-136 §1/§4)
- [ ] 既存の ref テンプレ fixture 群 (`repeat-parse/ref-*` / `seq-parse/ref-template-parity` /
      `multiple-parse/ref-*` ほか) がすべて green のまま
- [ ] inline seq と ref template の結果形パリティを pin する fixture がある (DR-078 §1)

## 関連

- 統合報告 B4 (R5 M1)。同報告の P1 (id/name 軸解決の一元化漏れ) の 1 件として数えられており、
  既知 issue `2026-08-14-ref-link-resolution-name-axis-to-id-axis.md` の追記にも記録済み
