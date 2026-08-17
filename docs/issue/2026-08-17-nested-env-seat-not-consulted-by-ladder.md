---
title: 構造子配下の env 席が値源ラダーで参照されない
status: open
category: bug
created: 2026-08-17T09:26:44+09:00
last_read:
open_entered: 2026-08-17T09:26:44+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu.mbt 全コードレビュー即修サイクル 2026-08-17 (B5 修正中に発見した隣接 gap)
---

# 構造子配下の env 席が値源ラダーで参照されない

## 概要

named group / option seq / structural or の**配下の子要素**に立てた env 席が、resolve 相の値源ラダーから参照されない。席は decode 側で正しく宣言されているのに値が入らず、結果は `null` のままになる。

`env` を**明示宣言**した場合でも起きるため、auto_env 固有の問題ではなく **nested 席全般に効く値源ラダー側の穴**である。

## 実測 (RED)

いずれも `kuu.mbt` の wbtest から `parse` → `resolve` → `output` を通した実測値。

### 1. group が選択されていても子の env 席が埋まらない (最も明確な断面)

```json
{"positionals":[{"name":"g","positionals":[
  {"name":"a","type":"string"},
  {"name":"b","type":"string","env":["G_B"]}]}]}
```

| argv | env | 実測 result | 期待 |
|---|---|---|---|
| `["x"]` | `G_B=v` | `{g={a=s:x,b=null}}` | `{g={a=s:x,b=s:v}}` |

兄弟 `a` が CLI から充足しているので **group は選択済み**。その状態でも `b` の env 席が読まれていない。

### 2. トップレベル同型は正常 (対照)

```json
{"positionals":[{"name":"a","type":"string","env":["G_A"]}]}
```

| argv | env | 実測 result |
|---|---|---|
| `[]` | `G_A=v` | `{a=s:v}` ✅ |

同じ宣言をトップレベルに置くと正しく env から充足される。したがって「env 席の宣言」でも「env provider」でもなく、**ラダーが nested 席に到達していない**ことが原因側の見立て。

### 3. auto_env 由来でも同じ

`config: {"env_prefix":"MYAPP","env_auto":true}` 配下で、席の宣言自体は正しく行われることを decode 出力で確認済み:

```
--- {"config":{"env_prefix":"MYAPP","env_auto":true},"positionals":[{"name":"g","positionals":[{"name":"inner","type":"string"}]}]}
    /g env=
    /g/inner env=MYAPP_G_INNER      ← 席は立っている
--- {"config":{"env_prefix":"MYAPP","env_auto":true},"options":[{"name":"o","long":true,"seq":[{"name":"inner","type":"string"}]}]}
    /o env=
    /o/inner env=MYAPP_O_INNER      ← 席は立っている
```

にもかかわらず resolve 後の値は `null`。

## 根本原因の見立て (要裁ち直し)

値源ラダー (`src/kuu/resolve.mbt` の `resolve_scope_tree` 系) が env 席を集める対象を、スコープ直下の options / positionals に限っており、`ElementBody::Group` / `Or` の中へ降りていない、という見立て。**未確認**なので、着手時に実装を読んで裏取りすること (統括・報告者の見立てを鵜呑みにしない)。

## この issue の位置づけ — B5 との関係

即修サイクルの **B5** (commit `9a3929d3` = change `wwunqqor`) で、DESIGN §7.2「子要素は親の config を継承、上書き可能。子要素は command scope に限らない」に従い、scope config を構造子配下へ届かせる decode 側の修正を入れた。その結果 nested 子に env 席が**立つ**ようにはなったが、本 issue のラダー側の穴があるため **user-visible には依然として nested の env は動かない**。

つまり B5 は decode 面の是正であって、機能の開通は本 issue の解消を待つ。B5 の wbtest も「導出された env 名が正しいこと」を decode 出力に対して pin しており、値が入ることは pin していない (入らないため)。

## 関連する死角 (D7)

spec 側に **nested 要素の env 供給を pin した fixture が存在しない** (`fixtures/` 全体を grep 済み)。これが本件が長く検出されなかった直接原因で、統合レビューの D7「fixture/wbtest 網羅補強」と同じ死角に属する。

- `fixtures/value-sources/env-ladder.json` / `env-auto-name-mapping.json` / `positional-env-presence.json` はいずれもトップレベル要素のみ
- `fixtures/export-key/sources-nested-scope-parity.json` は nested scope を扱うが **sources の path 軸**が主題で、env 供給は見ていない

修正時に spec 側 fixture を足す必要がある (lockstep 窓で `kawaz/kuu` 側と同時に動かす)。

## 受け入れ条件

- [ ] 上記「実測 (RED)」の 1 が `{g={a=s:x,b=s:v}}` になる
- [ ] 明示 `env` と auto_env 由来の両方で、named group / option seq / structural or の子が env から充足される
- [ ] 未選択スコープの子には env が漏れない (DR-130 の unselected scope 規定、`fixtures/export-key/unselected-scope-no-default-leak.json` の同型を nested でも保つ)
- [ ] spec 側に nested env 供給の pin fixture を追加 (lockstep 窓)
- [ ] 既存 conformance が無傷 (decoded=454 / ran_cases=1001 / skipped=0 / mismatches=0)

## 関連

- DR-049 (env lookup contract — §3 auto_env の名前導出、§4 明示 env 優先)
- DESIGN §7.2 (子要素の config 継承 — 子要素は command scope に限らない)
- B5: commit `9a3929d3` (decode 側の scope config 焼き込み)
- [decode-attribute-carry-allowlist-audit](./2026-08-16-decode-attribute-carry-allowlist-audit.md) (`dec_or_leaf` が `env` キー自体を拒否する件を追記済み — or/seq leaf は明示 env すら書けない)
- [union-tuple-fixture-coverage-gaps](./2026-08-16-union-tuple-fixture-coverage-gaps.md) (D7 の fixture 死角、同族)
