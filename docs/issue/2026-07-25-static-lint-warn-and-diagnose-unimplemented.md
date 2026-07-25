---
title: DESIGN §15.6 の静的 warn と §13.7 diagnose が未実装 — 露出キー衝突の潜在構造を誰も警告しない
status: open
category: design
created: 2026-07-25T17:15:58+09:00
last_read:
open_entered: 2026-07-25T17:15:58+09:00
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

# DESIGN §15.6 の静的 warn と §13.7 diagnose が未実装 — 露出キー衝突の潜在構造を誰も警告しない

## 概要

spec は「静的バリデータは warn のみ、実行場所は開発時 lint」(DESIGN §15.6 / DR-021) として
3 種の warn を規定しているが、**kuu.mbt に該当する実装が無い**。`kuu.diagnose(ast)`
(DESIGN §13.7) も未実装。

結果として、露出キーが衝突しうる定義は **静的にも実行時にも誰にも警告されない**。
実行時検出 (DESIGN §15.5) には別途ギャップがあるため (spec 側 issue
`2026-07-25-expose-key-collision-option-command-silent-loss`)、
現状は **二段構えのどちらの段も機能していない**。

## 未実装の内容

DESIGN §15.6 が warn 対象として列挙するもの:

1. 露出キーが衝突しうる構造 → warn
2. 共露出キーに異なる宣言 default が並ぶ構造 → warn (両者未発火だと実行時 ambiguous になる、DR-031 EXP-Q1 追記 note)
3. 背骨なし内部で無制限の string repeat の後にトリガ付き構造が続く → 丸呑みの潜在を warn

DESIGN §13.7:

> `kuu.diagnose(ast)` で AST 走査時に未実装を全列挙する仕組み。

## 実測 (2026-07-25)

- `grep -rn "diagnose" src` → `src/extension/capability.mbt:6` と
  `src/internal/engine/declaration.mbt:3` の doc コメント内の言及 2 件のみ。
  実装・公開 API とも存在しない
- kuu-cli の `validate` (= `parse_definition` + lowering) は、露出キーが確実に衝突する
  以下の定義すべてに対して `{"ok": true, "completer_capabilities": []}` を返す:

```json
{"options":[{"name":"x","type":"flag","long":true}],
 "commands":[{"name":"x","type":"command","options":[{"name":"inner","type":"flag","long":true}]}]}
```

```json
{"options":[{"name":"x","type":"flag","long":true}],
 "positionals":[{"name":"x","type":"string"}]}
```

```json
{"options":[{"name":"x","type":"flag","long":true},
            {"name":"x","type":"string","long":true}]}
```

3 つ目は同一スコープ内の**トリガ重複**でもあり、DESIGN §15.8 の
「同一スコープ内の重複は**静的 warn** + 実行時 ambiguous」にも該当するが、これも warn されない。

## なぜ効いているか (本 issue を立てる動機)

dogfooding D4 の露出キー衝突調査で、option `x` + command `x` / option `x` + positional `x`
のような定義が「**書けてしまい、実行しても何も言われず、値が静かに消える**」ことが判明した。
DR-021 の設計は

> warn はする、reject はしない、の二段構え (利用者を信頼)

であり、**warn する側が実装されていること**が「reject しない」判断の前提になっている。
warn 層が無い状態では DR-021 は「何もしない」に縮退する。

## 設計上の論点

### 実行場所 (bundle 非同梱)

DESIGN §15.6 / DR-021 は「実行時 bundle には同梱しない」(DR-040 の tree-shake 原則と整合)
と明記している。したがって:

- `parse_definition` の返り値に warn を足す形は**採れない** (実行時経路に乗る)
- 別 API (`diagnose(ast)` / lint エントリ) として切り出し、kuu-cli 等の開発時ツールから
  呼ぶ形になる
- kuu-cli 側に `validate --diagnose` 相当の入口が要るかは kuu-cli の関心 (別リポ)

### warn の判定条件は EXK-Q1 / EXK-Q2 の裁定に従属する

warn 1 (「露出キーが衝突しうる構造」) の判定条件そのものが、spec 側 QUESTIONS.md の
EXK-Q1 (同名の別要素の扱い) / EXK-Q2 (scope 生成要素を検出対象に含めるか) の裁定で変わる:

- EXK-Q1 が definition-error 側に倒れれば、同名兄弟は warn ではなく error になる
- EXK-Q2 が (a) に倒れれば、command も「衝突しうる構造」の走査対象に入る

したがって **warn ルールの中身は裁定待ち**。ただし後述のとおり器の側は独立に着手できる。

### warn の構造化語彙

DR-058 §2 が実行時 `warnings` に `{element, kind}` の構造を与えている
(CONFORMANCE §2 success の `warnings`)。lint warn も同じ形にするか別語彙にするかは未決。
conformance fixture に lint warn の断面を持たせるなら `query` 種別の新設が要る
(現行は `parse` / `complete` / `help` / `definition_error`)。

## 受け入れ条件

- [ ] lint / diagnose の API 形と実行場所 (bundle 非同梱の担保方法) が決まる
- [ ] warn の構造化語彙 (`{element, kind}` 流用か新設か) が決まる
- [ ] DESIGN §15.6 の 3 warn と §15.8 のトリガ重複 warn が実装される
- [ ] 上記「実測」の 3 定義すべてで warn が出ることを固定する test が入る
- [ ] conformance fixture に lint warn の断面を持たせるか否かが決まる (持たせるなら query 種別の新設)

## 他 issue との独立性

**器 (diagnose / lint の API 形・実行場所・語彙) は EXK-Q1 / EXK-Q2 の裁定と独立に決められる。
ただし warn 1 の判定条件の中身は裁定に従属する。**

したがって着手順序としては「器を先に決めて warn 3 (丸呑み) と §15.8 のトリガ重複から実装し、
warn 1 / warn 2 は裁定後に足す」が取れる。全部を裁定待ちにする必要はない。

## 関連

- spec の DESIGN §15.6 (静的バリデータは warn のみ) / §13.7 (diagnose モード) / §15.8 (同一スコープ内トリガ重複の静的 warn) / §15.5 (実行時の露出キー一意性検査)
- spec の DR-021 (warn はする、reject はしない — 二段構えの前提) / DR-054 (warn 原則の適用層の限定) / DR-040 (tree-shake 原則)
- spec 側 issue `2026-07-25-expose-key-collision-option-command-silent-loss` (実行時検出のギャップ本体) と QUESTIONS.md の EXK-Q1 / EXK-Q2
- `src/kuu/front_door.mbt` (`parse_definition` — 実行時経路。ここに warn を足さないことが論点)
