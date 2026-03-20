---
type: review
---

# DR-060: 20260320 MoonBit Example レビュー知見 — core API の能力と限界

## 背景

20260320 に MoonBit core API 直接使用の example を3本作成:

- **git-moonbit**: 15+サブコマンド、ネスト、グローバルオプション、78テスト、1828行
- **docker-moonbit**: management command + shortcut 二重構造、49テスト、~1200行
- **curl-moonbit**: 74オプション大規模定義、27テスト、~1000行

DR-051（20260318、5言語 WASM bridge 中心）とは異なり、MoonBit core API の書き味を直接検証した。

## 課題

### A: custom() 昇格パターンの蔓延（深刻度: 高）

値プリミティブ（`string`/`int`/`float`）は DR-053 で `shorts`/`global`/`aliases` を除去済み。これらが必要な場合、`custom()` + identity filter への「昇格」が必須。

| example | 出現数 | パターン |
|---|---|---|
| git | 12箇所 | `custom(pre=Filter::map(fn(s) { s }), shorts="C", global=true, ...)` |
| docker | 全 shorts 付き | トップレベル定数 `str_pre` / `int_pre` で共有 |
| curl | custom_append 多数 | `append_string` と `custom_append` の混在 |

**問題の本質**: `string(name="host", shorts="H", global=true)` と書きたいだけなのに、`custom()` + `Filter::map(fn(s) { s })` という冗長なコードが必要。docker example では design rationale コメントで「なぜ custom なのか」を説明する必要があった。

**評価**: DR-053 の「値プリミティブ純化」は core 設計として正しい。DX 層でラッパーコンビネータを提供すべき課題。

### B: serial パターンの二重ラッピング（深刻度: 高）

serial 内で生成した `Opt[T]` をクロージャ外で参照するため、`Opt[T]?` + `mut` の二重ラッピングが必要。

```moonbit
let mut push_remote_opt : @core.Opt[String]? = None
let mut push_branch_opt : @core.Opt[String]? = None
push.serial(setup=fn(s) {
  push_remote_opt = Some(s.positional(name="remote", ...))
  push_branch_opt = Some(s.positional(name="branch", ...))
})
// 使用時: push_remote_opt.unwrap().get().unwrap()
```

| example | 出現数 |
|---|---|
| git | 6箇所（push, pull, remote add/rename 等） |
| docker | serial + rest + required + `sub.never()` の複合パターン |
| curl | rest で対処（serial 不使用） |

docker では `sub.never()` の意図説明コメントも必要になるなど、API の直感性が低い。

### C: 値取得・dispatch のボイラープレート（深刻度: 中）

パース後の値取得・出力処理が定義量とほぼ同量。

| example | 定義行数 | dispatch 行数 | 比率 |
|---|---|---|---|
| git | ~668行 | ~484行 | 72% |
| docker | ~400行 | ~300行（helper 関数含む） | 75% |
| curl | ~500行 | ~400行 | 80% |

典型パターン:
```moonbit
let msg = commit_message.get().unwrap()
if msg != "" { buf.write_string("  message: \"" + msg + "\"\n") }
```

**評価**: example の性質（パース結果の表示が目的）による面が大きいが、実運用 CLI でも `get().unwrap()` の繰り返しは避けられない。struct-first DX（DR-042）で `self.field` 直接アクセスに改善可能。

### D: setup 関数による定義共有の冗長性（深刻度: 中、docker 固有）

`docker run` = `docker container run` のショートカット実装に、同一オプション定義を setup 関数で共有する必要がある。MoonBit のスコープ制約（let が関数内に閉じる）により、setup 関数内で定義した Opt を外から参照する際に再び `Opt[T]?` + `mut` パターンが発生。

struct-first DX なら `RunOpts` struct を定義して使い回せる。

### E: variation_false の命名が非直感的（深刻度: 低）

```moonbit
let keepalive = p.flag(
  name="keepalive",
  default=true,
  variation_false=Some("no"),  // --no-keepalive を生成
)
```

docker（`--no-deps`）と curl（`--no-keepalive`）で使用。「`--no-*` パターンを追加する」という意図に対して `variation_false` は間接的。ただし variation 体系（variation_false / variation_reset）の一貫性として妥当な命名であり、変更の必要性は低い。

### F: env パラメータが metadata のみ（深刻度: 低）

docker（`DOCKER_HOST`）、curl（`HTTP_PROXY`）で `env="..."` を使用。ヘルプに `[env: X]` と表示されるが、実際の環境変数値取得は手動。DR-041 Phase 2 の実装待ち。core 純粋関数主義（DR-027）に準拠した設計であり、意図的な制限。

### G: implicit_value の型が冗長（深刻度: 低）

```moonbit
implicit_value=Some(@core.Val("always"))  // Some(Val(...)) が必須
```

git, curl で使用。記述は冗長だが型安全性のトレードオフとして妥当。

## 良かった点

### 1. サブコマンド体系の表現力

git（15+コマンド、2階層ネスト）、docker（management command + shortcut）を自然に構築できた。

```moonbit
let remote = p.sub(name="remote", ...)
remote.require_cmd()
let remote_add = remote.sub(name="add", ...)
```

### 2. 制約の宣言的表現

exclusive、requires、required、at_least_one、choices が全て宣言的に書ける。

```moonbit
push.exclusive([push_force.as_ref(), push_force_lease.as_ref()])
p.requires(proxy.as_ref(), source=proxy_user.as_ref())
```

curl では認証方式（basic/digest/ntlm/anyauth）と HTTP バージョン（1.0/1.1/2/3）の2つの排他グループを自然に表現。

### 3. short flag combining の透過的動作

docker の `-it`、`-itd`、curl の `-sSLo` が特別な実装なしに正しく解析される。

### 4. append 系の複数値蓄積

docker の `-p 8080:80 -p 3000:3000`、curl の `-H "..." -H "..."` が自然に `Array[String]` に蓄積。

### 5. global option の自動伝搬

`global=true` で全サブコマンドに自動伝搬。git の `--git-dir`、`-v` （count + global）、docker の `--debug`、`--host` で検証。count の `variation_reset` との組み合わせ（`-vvv` + `--no-verbose`）も秀逸。

### 6. テストの書きやすさ

3例合計 154 テスト。snapshot test（`inspect!()`）で出力結果を厳密検証。エラー系（exclusive 制約違反、choices 不正値等）も充実。

### 7. deprecated コンビネータ

curl の `--sslv3` → `--tlsv1.2` への警告付きリダイレクトが自然に動作。

### 8. aliases の簡潔さ

git（`co`, `br`）、docker（`ls`/`list`/`ps`）が `aliases=[...]` で1行定義。

## DR-051 との比較

| 観点 | DR-051（20260318、5言語 WASM） | DR-060（20260320、MoonBit core） |
|---|---|---|
| 主な課題 | WASM bridge 機能ギャップ | core API の冗長性（DX 層不在） |
| shorts/global | WASM bridge 側で未対応 | core では custom() 昇格が必要 |
| 制約（exclusive等） | WASM bridge 側で未対応 | 全て動作、宣言的に表現可能 |
| テスト容易性 | 言語ごとにテスト基盤が異なる | snapshot test で統一的に検証 |
| スケール | 各 20-40 オプション | 最大 74 オプション（curl） |
| 結論 | WASM bridge 拡張が最大ボトルネック | DX 層（struct-first）が最大の改善余地 |

## 総合評価

core API は **複雑な実世界 CLI を正確に再現する能力がある**ことを3本の example で実証した。制約表現（exclusive/requires/choices）、サブコマンドネスト、short combining、global option 伝搬は特に優秀。

一方、**ボイラープレートの量が大きい**ことも明確になった。定義量と同等の dispatch コード、serial の二重ラッピング、custom() 昇格パターンが主な原因。これらは core の設計上の帰結（純化・薄さ）であり、**DX 層（struct-first、DR-042）で解決すべき課題**として位置づけられる。

### H: adjust の 6 パラメータ設計が未実装（深刻度: 高）

DR-037 で設計された adjust の完全形:

```
adjust(opt,
  before_pre?, after_pre?,
  before_post?, after_post?,
  before_accum?, after_accum?)
```

pre / post / accum の 3 フェーズそれぞれに insert_before / insert_after を足す 6 パラメータ設計。しかし DR-044 で「v1 では after_post のみ。その他はユースケース出現時に追加」と縮小され、現在の実装は `after_post` しかない。

**`append` は accum フェーズの adjust そのもの**。蓄積戦略を replace → push に変えるだけ。adjust が完全実装されていれば `append_*` 系は全て不要だった:

```
append_string(...)    = adjust(string(...), after_accum=push)
append_int(...)       = adjust(int(...), after_accum=push)
append_float(...)     = adjust(float(...), after_accum=push)
custom_append[T](...) = adjust(custom[T](...), after_accum=push)
append_dashdash(...)  = adjust(dashdash(...), after_accum=push)
```

`dashdash` 自体もプリミティブの合成シュガーに過ぎない:

```
dashdash("--") = serial([
  exact("--", greedy=true),
  rest(string()),
])
```

serial でグループ化し、`exact("--")` が greedy でマッチしたらスコープ内の `rest()` が残りを全部収集する。

さらに accum フェーズの adjust は単純な push だけでなく、より複雑なパターンも表現できる:

```
push:                --tag v1 --tag v2           → ["v1", "v2"]
split + flat + push: --fields id,ts --fields dur → ["id", "ts", "dur"]
merge with modifiers: --fields "+dur,-ip,..."    → 環境変数ベースに昇格/除外/展開
```

example での影響: docker/curl で `custom_append` と `append_string` が混在。adjust の完全実装があれば `adjust(string(...), after_accum=push)` で統一的に表現できた。

**対応**: DR-037 の元設計に立ち返り、adjust の 6 パラメータを実装する。

## 課題の解決状況（2026-03-21 更新）

| 課題 | 状態 | 備考 |
|---|---|---|
| A: custom() 昇格パターン | 部分解決 | DR-061 で低レイヤ API の責務として明確化。実装は未 |
| B: serial の二重ラッピング | 部分解決 | 低レイヤ API での高級 serial API として設計検討中 |
| C: dispatch ボイラープレート | 部分解決 | struct-first DX（DR-042）で解決可能と評価 |
| D: setup 関数共有の冗長性 | 部分解決 | struct-first DX で解決可能と評価 |
| E: variation_false の命名 | 解決済み | 変更不要（variation 体系の一貫性） |
| F: env が metadata のみ | 未解決 | DR-041 Phase 2 待ち |
| G: implicit_value の型冗長性 | 解決済み | 変更不要（型安全性のトレードオフ） |
| H: adjust の未実装 | **実装完了** | custom_append→append リネーム + adjust 4パラメータ追加。accum はペンディング |

## 今後のアクション

1. ~~**adjust の 6 パラメータ完全実装**~~ → **完了**（pre/post 4パラメータ。accum はペンディング）
2. **低レイヤ API で shorts/global 対応ラッパー提供** — custom() 昇格パターンの解消
3. **低レイヤ API で serial の高級 API 検討** — クロージャ + mut パターンの隠蔽
4. **struct-first DX で同等 example の再実装** — サイズ比較で DX 層の価値を実証
5. **DR-041 Phase 2**（env 実値取得）— docker/curl example の完全動作に必要
