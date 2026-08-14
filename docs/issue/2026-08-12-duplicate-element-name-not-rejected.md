---
title: 同一スコープの同名要素が definition-error にならない (DR-006 / DR-003 の name 重複禁止が未実装)
status: open
category: bug
created: 2026-08-12T18:00:00+09:00
last_read: 2026-08-14T21:13:19+09:00
open_entered: 2026-08-12T18:00:00+09:00
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

# 同一スコープの同名要素が definition-error にならない (DR-006 / DR-003 の name 重複禁止が未実装)

## 概要

DR-006「`name` は **スコープ内 (options + positionals すべて) で重複禁止**」/ DR-003「重複ルール」
(どちらも現役規範。DR-006 の Superseded 節は「name 重複禁止ルールは引き続き有効」と明記) に
反する定義が、definition-error にならずに decode を通る。

現行の重複検査は DR-120 の **露出キー衝突** (`export-key-collision`) だけで、これは
DR-120 §4 の「露出キーを占有する要素」しか見ない。したがって **非占有要素**
(`config_file` / `none` / `dd` / `alias` / global の入口コピー) が絡む同名は素通しになる。

## 実測 (2026-08-12)

リポ外 `$PROBE_FIXTURES` に一時 fixture を置き、公開 API を通す conformance runner で観測:

```json
{"options": [
  {"name": "user", "type": "config_file", "default": "/u.toml"},
  {"name": "user", "type": "string", "long": true, "multiple": true}
]}
```

```console
$ KUU_FIXTURES="$PROBE_FIXTURES" moon test --target native \
    src/kuu/json_conformance_test.mbt -f 'conformance: fixtures*'
[json-conformance] decoded=1 ran_cases=1 skipped=0 mismatches=1
[json-conformance]   diverge samename.json::fired :: resolve error: config file "alice" could not be read
```

- decode / definition lint を通る (definition-error にならない)
- `--user alice` は **option `user` の入口** で入るのに、値が `config_file` セルの PATH として
  消費される。両要素が宣言名 `user` の 1 identity へ潰れているため、engine の binding 層
  (key = 宣言名) から下流全部で区別が付かない

## 位置づけ (別 issue との関係)

`2026-08-12-command-definition-error-parity-review-followup.md` の m3 (内部セル negative list の
同定不備) の調査中に分離した。m3 本体は「露出キーは一致するが宣言名は異なる」構成で、内部セルの
除外を宣言名軸へ移して修正済み (commit c1b53463)。本 issue はその**宣言名が同じ**方で、射影側では
原理的に直せない (宣言名軸でも同定が割れる)。

## 論点 (裁定・spec 側の確認が要る)

- **error kind**: DR-054 §4 の kind 列挙に「宣言名の重複」に当たるものが無い。既存 kind
  (`export-key-collision`) を流用するのは筋が悪い — 衝突しているのは結果キーではなく
  ref/link 解決の id 軸 (DR-003 の 3 軸のうち「AST 内部参照」)。新 kind を足すか、DR-120 §4 の
  非参加リストを id 軸では適用しない形にするかは spec 側の判断
- **検査面**: DR-120 §5 と同じ「全 installer の宣言層寄与を適用し終えた宣言層」で足りるか
  (alias copy / global 入口コピーは名前が canonical と重なる設計なので、素朴に数えると
  誤検出する。DR-120 §4 の非参加判定と同じ除外が id 軸でも要るはず)
- **spec fixture**: `definition-error/` に該当 case が無い

## 受け入れ条件

- [ ] 同一スコープの同名要素が definition-error になる (非占有要素が絡む組も含む)
- [ ] error kind と検査面が spec 側で確定している (上記論点)
- [ ] spec fixture (`definition-error/`) が輪郭を pin している
- [ ] alias copy / global 入口コピーで誤検出しないことを実測で確認

## TODO

<!-- wip 時のみ -->
