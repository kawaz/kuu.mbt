---
title: 衝突解釈の drop 判定が identity 露出の rival を落とせない (production だけ未修正、wbtest は helper 経由で green)
status: resolved
category: bug
created: 2026-07-25T17:15:58+09:00
last_read:
open_entered: 2026-07-25T17:15:58+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-08-02T22:51:37+09:00
discard_reason:
pending_reason:
close_reason: ["implemented:DR-120(spec) が露出キー衝突を parse 前の definition-error 化, runtime ambiguous/drop 経路が到達不能化", "done:v0.0.24 で露出キー focused tests 2 件 pass, 旧 promote_collision_ambiguous_from/find_export_collisions は実装から消滅"]
blocked_by:
origin: 自リポ TODO
---

# 衝突解釈の drop 判定が identity 露出の rival を落とせない (production だけ未修正、wbtest は helper 経由で green)

## 概要

露出キー衝突を `@engine.Ambiguous` へ昇格させるとき、各解釈は「自分の claimant 以外の
binding をその (path, 露出キー) から落とす」(DR-073 §2) 必要がある。この drop 判定が
**production 経路だけ export_key の 3 値解決を使っておらず、identity 露出 (export_key
未指定 → name 由来キー、DR-052 §1) の rival を構造的に落とせない**。

同じ判定を持つテストヘルパ側は既に修正済みで、その差分が wbtest を green のまま通して
いるため、**wbtest が production の bug に green を出している**状態になっている。

## 該当箇所

production (未修正) — `src/kuu/resolve.mbt:1063-1070` (`promote_collision_ambiguous_from` 内):

```
if path_eq(c.path, b.scope) &&
  c.key ==
  (match ek.get(b.key) {
    Some(@engine.Key(s)) => s
    _ => ""              // ← identity 露出 / 未 map は "" に落ちる
  }) &&
  b.key != combo[gi] {
  drop = true
}
```

test helper (修正済み) — `src/kuu/test_helpers_wbtest.mbt:307-313` (`build_interpretations` 内):

```
if path_eq(c.path, b.scope) &&
  exposed_key_of(b.key, ek) == Some(c.key) &&   // ← 3 値解決を通す
  b.key != combo[gi] {
  drop = true
}
```

`exposed_key_of` (`src/kuu/resolve.mbt:980-986`) は `@engine.Null` → `None` /
`@engine.Key(s)` → `Some(s)` / それ以外 (`@abi.Unset` / 未 map) → `Some(raw)` の 3 値解決で、
検出側 `find_export_collisions` (`resolve.mbt:997-1031`) は既にこれを使っている。
**検出は identity 露出を拾うのに、drop はそれを落とせない**という非対称が残っている。

## 再現手順と実出力 (2026-07-25 実測)

kuu-cli の compiled binary 経由。`deps/kuu.mbt` は本リポ working copy への symlink。

```
bin=<kuu-cli>/impl/mbt/_build/native/debug/build/kawaz/kuu-cli-mbt/main/main.exe
```

### 現象が出る定義 (mapped を先、identity を後に宣言する)

```json
{"options":[
  {"name":"b","type":"string","long":true,"export_key":"a"},
  {"name":"a","type":"string","long":true}
]}
```

```
$bin parse def.json --no-env --no-config -- --a v1 --b v2
```

実出力:

```json
{"outcome":"ambiguous","interpretations":[
  {"result":{"a":"v1"},"claimants":{"a":"b"}},
  {"result":{"a":"v1"},"claimants":{"a":"a"}}]}
```

**2 解釈のビューが同一 `{"a":"v1"}` に潰れており、`claimants {a: "b"}` の解釈が
option `b` の値 `v2` を示していない** (`v1` は option `a` の値)。DR-073 §1 は
「claimants を持つ解釈は `{result, claimants}` の組を 1 単位として区別する」と規定して
いるが、片方の組は事実として誤った view を持つ。

機構: combo = `"b"` の解釈で、option `a` の binding は `ek.get("a")` が `None` →
`""` に落ちて `c.key`(= `"a"`) と一致しないため drop されず、option `b` の binding も
`b.key == combo` なので drop されない。両方が生き残り、`apply_export_keys` で
どちらもキー `a` へ写った後 `build_result` の last-wins (DR-015) で後勝ちの値だけが残る。

### 既存 fixture が偶然マスクしている理由

`fixtures/export-key/collision-identity.json` (spec 側) の definition は
**identity 側 (`a`) を先、mapped 側 (`b`) を後**に宣言している。`resolve_scope_tree` の
出力は宣言順なので、combo = `"b"` のとき last-wins で後勝ちする binding が
たまたま `b` になり、期待値 `{"a":"v2"}` と一致してしまう。同 fixture を実際に食わせると
green になる (実測済み)。上の再現は**宣言順を入れ替えただけ**で、それ以外は同型。

```
$bin parse <collision-identity.json の definition> --no-env --no-config -- --a v1 --b v2
→ {"outcome":"ambiguous","interpretations":[
     {"result":{"a":"v1"},"claimants":{"a":"a"}},
     {"result":{"a":"v2"},"claimants":{"a":"b"}}]}   ← 偶然 正しい
```

### wbtest が green になる理由

`src/kuu/resolve_wbtest.mbt:573-587` の
`"DR-073 identity-exposure collision: @abi.Unset element vs @engine.Key-mapped element sharing a key"`
は `build_interpretations` (= test helper、修正済みの方) を呼んでいるため、
production の drop 判定を一度も通らない。同 test のコメントは
「issue 受け入れ条件『promote_collision_ambiguous のドロップ判定も同様に拡張』」と
明記しており、**拡張したつもりで helper だけ直っていた**ことが分かる。

## 修正方針 (案)

`resolve.mbt:1063-1070` の inline match を `exposed_key_of(b.key, ek) == Some(c.key)` に
置き換えて helper と一致させる。1 行の変更で足りる見込み。

ただし **helper と production に同じ判定ロジックが 2 本ある構造そのものが再発源**なので、
production 側の関数を wbtest から呼べる形にして helper の重複を消すか、helper を
production 関数の薄いラッパにするのが本筋。

## 受け入れ条件

- [ ] `promote_collision_ambiguous_from` の drop 判定が `exposed_key_of` を通る
- [ ] 上記「宣言順を入れ替えた定義」で 2 解釈のビューが `{"a":"v1"}` / `{"a":"v2"}` に分かれる
- [ ] drop 判定ロジックの production / test helper 二重化が解消される (または重複が意図的である旨の根拠が残る)
- [ ] 宣言順の対称性を固定する fixture / wbtest が追加される (identity 先・mapped 先の両方)

## 他 issue との独立性

**EXK-Q1 / EXK-Q2 (spec 側 QUESTIONS.md の露出キー衝突の裁定) とは独立に修正できる。**
裁定がどちらに転んでも「衝突が検出されたら rival を落とす」という DR-073 §2 の規定自体は
不変であり、test helper が既に意図する形を示している。裁定待ちにする理由はない。

## 関連

- `src/kuu/resolve.mbt:980-986` (`exposed_key_of`) / `:997-1031` (`find_export_collisions`) / `:1043-1092` (`promote_collision_ambiguous_from`)
- `src/kuu/test_helpers_wbtest.mbt:285-333` (`build_interpretations`)
- `src/kuu/resolve_wbtest.mbt:553-587` (helper 経由で green になっている wbtest)
- spec の DR-073 §1/§2 (claimants 面と drop 規定) / DR-052 §1 (export_key の 3 値軸) / DESIGN §15.5
- spec fixture `fixtures/export-key/collision-identity.json` (宣言順で偶然マスクしている pin)
- spec 側 issue `2026-07-25-expose-key-collision-option-command-silent-loss` (露出キー衝突の検出ギャップ本体、本 issue とは別軸)
