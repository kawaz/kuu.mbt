---
title: command 木がある定義で sources が export_key を適用しない (command を 1 つ足すだけでキー体系が変わる)
status: resolved
category: bug
created: 2026-07-25T17:15:58+09:00
last_read:
open_entered: 2026-07-25T17:15:58+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered: 2026-07-26T13:20:50+09:00
discard_reason:
pending_reason:
close_reason: ["implemented","done: kuu.mbt 2 commits (collect_sources_tree に export_key 適用 + 0回発火accumセルのdefault報告), spec 2 commits (CONFORMANCE §2 に射影後キーと明記 + export-key×sources×command 交差fixture追加), wbtest 5本追加, conformance decoded 341→342 mismatches=0 (未push)"]
blocked_by:
origin: 自リポ TODO
---

# command 木がある定義で sources が export_key を適用しない (command を 1 つ足すだけでキー体系が変わる)

## 概要

`sources` 射影 (DR-109 §3「resolve 済み出力には常に sources を含める」) のキーが、
**定義に command が 1 つでもあると export_key を通らず生の entity 名 / 生 scope path に
なる**。同じ要素が `result` では rename 後のキーで出るのに `sources` では rename 前の名前で
出るため、両者を突き合わせる消費者 (script / 言語バインディング) が対応を取れない。

`result_sources` (`src/kuu/resolve.mbt:1258-1270`) が `has_commands(sc)` で実装を分岐し、
真の側 `collect_sources_tree` (`:1231-1240`) が export_key を適用しないことによる。

## 該当箇所

`src/kuu/resolve.mbt:1258-1270`:

```
fn result_sources(...) -> Array[SourceEntry] {
  if has_commands(sc) {
    collect_sources_tree(resolved)        // ← ek を受け取らない
  } else {
    collect_sources_flat(sc, resolved, ek) // ← ek を通す
  }
}
```

`collect_sources_tree` (`:1231-1240`) は doc コメントで挙動を明言している:

> `collect_sources_flat` が持つ「未発火セルの default フォールバック」と **export_key rename は
> 適用しない** — `resolve_scope_tree` の出力は既に「実際に着席した binding」だけを運ぶため、
> この経路では**素の entity 名・生 scope path をそのまま使う** (proj_sources_tree の元実装を踏襲、
> **意味論は無改変**)

つまり「旧 runner 実装を意図的にそのまま昇格させた」結果であり、export_key を落とすことの
是非は検討されていない (`issue 2026-07-16-result-projection-production-promotion` の
production 昇格時に、数字不変を条件としたため既存挙動が保存された)。

`collect_sources_flat` の方は `exposed_key_of(e.name, ek)` (`:1176`) を通しており、
**同じ `sources` フィールドがコード経路によって別のキー体系を持つ**。

## 再現手順と実出力 (2026-07-25 実測)

kuu-cli の compiled binary 経由 (`deps/kuu.mbt` は本リポ working copy への symlink)。

### ケース 1: option の export_key が sources に反映されない

```json
{"options":[{"name":"opt","type":"flag","long":true,"export_key":"renamed"}],
 "commands":[{"name":"cmd","type":"command","options":[{"name":"inner","type":"flag","long":true}]}]}
```

```
$bin parse def.json --no-env --no-config -- --opt cmd
```

```json
{"result":  {"renamed": true, "cmd": {"inner": false}},
 "sources": {"opt": "cli", "cmd.inner": "default"}}
```

`result` は `renamed`、`sources` は `opt`。**同じ要素を指す 2 つのキーが一致しない。**

### ケース 2: command の export_key が sources の path に反映されない

```json
{"commands":[{"type":"command","name":"cmd","export_key":"sv",
              "options":[{"name":"inner","type":"number","long":true,"export_key":"i"}]}]}
```

```
$bin parse def.json --no-env --no-config -- cmd --inner 3
```

```json
{"result":  {"sv": {"i": 3}},
 "sources": {"cmd.inner": "cli"}}
```

command の scope が `result` では `sv` へ rename され、配下セルも `i` へ rename
されているのに、`sources` の path は rename 前の `cmd.inner` のまま。

### 対照: command が無ければ正しく rename される

```json
{"options":[{"name":"opt","type":"flag","long":true,"export_key":"renamed"}]}
```

この定義では `collect_sources_flat` を通るため `sources` も `renamed` になる。
つまり **上の定義から command を 1 つ削るだけで sources のキー体系が変わる**。

## 仕様との整合

- `apply_export_keys` (`src/kuu/resolve.mbt:234-260`) は binding の `key` も `scope` セグメントも
  `ek` の 3 値 (`Null` 畳み込み / `Key(s)` rename / それ以外は素通し) で解決する。
  `apply_export_to_defaults` (`:268-296`) も同じ。**sources だけがこの解決を通らない**
- spec DR-052 (結果キー軸の一本化) は「export_key は結果キー軸の唯一の軸」と規定しており、
  射影ごとに別の名前空間を使う根拠がない
- spec DR-109 §3 は「消費者 (script) が値の出所を**機械判別**できる」ことを sources 常時出力の
  目的として挙げているが、`result` と突き合わせられないキーでは目的を満たさない
- spec CONFORMANCE §2 success は sources のキーについて「**キーは scope-path 修飾**
  (root 直下は `"ttl"`、入れ子 scope 内のセルは `"sub.ttl"`)」とだけ規定し、
  修飾に使う名前が export_key 適用後かどうかを明示していない。**spec 側にも曖昧さがある**
  ため、実装修正と同時に spec 側の明確化が要るかもしれない (下記「論点」)

## 論点 (裁定が要るかもしれない点)

1. `sources` のキーは export_key 適用**後**で確定してよいか (= `result` と 1:1 対応させる)。
   本 issue はこれを前提に「bug」として起票しているが、spec が明示していない以上
   spec 側に 1 行足す価値がある
2. 0 回発火の accum セルが command 木経路では `sources` に現れない。実測 (args 空、
   定義: `a`(flag) / `ttl`(number default 30) / `tags`(string multiple)):
   commands あり → `sources {"a":"default","ttl":"default"}`(`tags` 欠落)、
   commands なし → `sources {"a":"default","ttl":"default","tags":"default"}`。
   未発火 flag/scalar の `default` 表示自体は両経路とも一致する
   (値源ラダー Phase 3b が default 席を解決して binding を作るため、tree 経路でも
   `resolved` に載る) — 非対称なのは AccumCell 経由でレンダされる 0 回発火 accum
   セルのみ。`collect_sources_flat` にはこの経路用フォールバックがあるが
   `collect_sources_tree` には無い。これも同じ分岐由来の非対称で、本 issue に含めるか別立てにするか

## 受け入れ条件

- [ ] `collect_sources_tree` が `ek` を受け取り、キー・path とも `apply_export_keys` と同じ 3 値解決を通る
- [ ] 上記ケース 1 / 2 で `result` と `sources` のキーが一致する
- [ ] 「command の有無で sources のキー体系が変わらない」ことを固定する fixture / wbtest が入る
- [ ] 論点 2 (0 回発火 accum セルの非対称) の扱いが決まる (本 issue で直す / 別 issue へ切る)

## 他 issue との独立性

**EXK-Q1 / EXK-Q2 (spec 側 QUESTIONS.md の露出キー衝突の裁定) とは独立に修正できる。**
sources の名前空間は export_key 軸 (DR-052) と DR-109 §3 の話で、衝突検出とは別軸。
ただし裁定の結果として衝突ケースが ambiguous へ落ちるようになると、
**衝突がある定義で `sources` を観測する機会自体が減る** (ambiguous に sources は付かない)。
観測面は変わるが、修正の必要性と内容は変わらない。

## 関連

- `src/kuu/resolve.mbt:1167-1220` (`collect_sources_flat`) / `:1231-1240` (`collect_sources_tree`) / `:1258-1270` (`result_sources`)
- `src/kuu/resolve.mbt:234-260` (`apply_export_keys`) / `:268-296` (`apply_export_to_defaults`) — 通すべき解決の正本
- spec の DR-109 §3 (sources 常時出力) / DR-052 (結果キー軸の一本化) / CONFORMANCE §2 success の sources 規定
- 先行 issue `2026-07-16-result-projection-production-promotion` (旧 runner からの production 昇格。数字不変条件のため既存挙動を保存した経緯)
