# regex_match filter の調達判断と実装設計 (codex 提案)

2026-07-09、issue regex-match-filter の設計調査を codex (gpt-5.5, codex-cli 0.142.5) に
read-only 委譲した結果の全文。監査所見と採否は issue regex-match-filter を参照。

---

## 採用案

`regex_match` は当面、kuu.mbt 内蔵の最小 subset regex として実装するのが妥当です。理由は、DR-040 が要求している用途が「pre_filters で狭める」ための例示レベルで、実例も `^-?[0-9]+$` や DESIGN §8.4 の `"regex_match:^[a-z]+$"` に限られているためです。根拠: [DR-040](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu/main/docs/decisions/DR-040-type-registry-dialects-and-restriction.md:26>)、[DESIGN.md](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu/main/docs/DESIGN.md:615>)。

確認済みの既存実装制約:

- kuu.mbt の `FilterDescriptor` は `name`, `signature`, `run` を持ち、`run : (Value, Array[String]) -> Result[Value, String]` です。`Validate` は成功時に入力値をそのまま返し、失敗時に `Err` を返す設計です。根拠: [filters.mbt](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/filters.mbt:23>)。
- 現在の `filters_registry()` は `trim`, `non_empty`, `in_range`, `increment` の 4 件のみで、`regex_match` は未登録です。根拠: [filters.mbt](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/filters.mbt:117>)。
- `regex_match` は `signature: Validate`、`run: filter_regex_match` として登録するのが既存設計に合います。対象は `VStr` のみ、非 string は `Err("regex_match requires a string value")` とするのが `in_range` と一貫します。根拠: `in_range` は number 以外を Err にしている [filters.mbt](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/filters.mbt:69>)。

生態系調査結果:

- ローカル依存 `moonbitlang/x@0.4.46` には regex パッケージは見当たりません。実体ディレクトリは `codec`, `crypto`, `decimal`, `encoding`, `fs`, `json5`, `num`, `path`, `rational`, `stack`, `sys`, `time`, `uuid` 等で、`regex`/`regexp` はありません。根拠: `/Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/.mooncakes/moonbitlang/x` と issue 記述 [2026-07-09-regex-match-filter.md](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/docs/issue/2026-07-09-regex-match-filter.md:29>)。
- `moonbitlang/x` は GitHub 上でも experimental package 集で、フォルダ一覧に regex はありません。GitHub 表示では 56 stars、385 commits、latest release `v0.4.45`、README は「frequent changes / not yet mature」と説明しています。根拠: GitHub `moonbitlang/x` lines 152-157, 197, 294-311, 347。https://github.com/moonbitlang/x
- kuu.mbt は `moonbitlang/x@0.4.46` を import しています。根拠: [moon.mod](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/moon.mod:13>)。
- `moonbitlang/x@0.4.46` の license は `Apache-2.0` です。根拠: [moonbitlang/x moon.mod](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/.mooncakes/moonbitlang/x/moon.mod:1>)。
- mooncakes.io / GitHub / web 検索で MoonBit 向け regex package 候補は確認できませんでした。これは「公開検索とローカル依存で候補なし」という確認結果であり、registry 全件 API による完全証明ではありません。未確認推測: mooncakes.io の JS UI 側に検索 API が存在する可能性はありますが、今回の調査では package 名・version・API を確認できる候補はありませんでした。

最小 subset の推奨仕様:

- 対応: `^`, `$`, 文字クラス `[a-z]`, 複数 range `[a-zA-Z0-9]`, 量指定子 `+`, `*`, `?`, 通常 literal。
- escape: `\^`, `\$`, `\[`, `\]`, `\+`, `\*`, `\?`, `\\`, `\-`, `\:` を literal として扱う。
- 非対応 metachar: `.`, `|`, `(`, `)`, `{`, `}` は未 escape なら pattern compile error として `Err`。silent literal 扱いにしない。
- 照合意味論: unanchored は部分一致、`^...$` で全体一致。DESIGN §8.4 が `regex_match:^[a-z]+$` を例にしているため、full match は anchor で表現する前提に寄せるのが自然です。
- 実装規模見積もり: regex parser + matcher で約 220-320 LOC、filter 登録と error 文言で約 20-40 LOC、MoonBit unit / conformance 周辺で約 80-140 LOC。未確認推測ですが、subset に alternation/group が無いため 500 LOC 未満に収まる見込みです。

## 不採用案とその理由

外部 regex library 採用は現時点では不採用です。moonbitlang org の `core` / `x` と mooncakes.io 検索で、package 名・version・API・license を評価できる候補が見つかっていません。候補が無い以上、dependency weight や成熟度を評価できません。根拠: `moonbitlang/x@0.4.46` の package 一覧、GitHub `moonbitlang/x`、ローカル `.mooncakes` 実査。

POSIX ERE / RE2-like を spec 名として先に掲げる案も不採用です。DR-040 自身が「regex 方言の一致が cross-host 条件」と明記しており、RE2-like を名乗るなら `.`、alternation、group、Unicode、escape、greediness まで仕様面が一気に広がります。今回必要なのは DR-040 の例示レベルです。根拠: [DR-040](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu/main/docs/decisions/DR-040-type-registry-dialects-and-restriction.md:58>)。

colon を含む regex は object 詳細形だけで書かせる案は、将来の spec としては筋が良いものの、現 kuu.mbt は header comment 上「string-shorthand DSL only」で、object form はまだありません。根拠: [filters.mbt](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/filters.mbt:10>)、DESIGN の object 詳細形説明 [DESIGN.md](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu/main/docs/DESIGN.md:620>)。

colon を regex pattern で禁止する案も不採用です。URL scheme、time、key-value 風 token などで `:` は普通に現れるため、validator としての実用性を落とします。

## 実装ステップ (kuu.mbt 側)

1. `src/core/filters.mbt` に subset regex の compile/match helper を追加する。既存方針に合わせ、filter closure 内で args を parse します。根拠: args casting は filter registry 側の責務とコメントされている [filters.mbt](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/filters.mbt:34>)。
2. `filter_regex_match(v, args)` を追加する。`args.length() != 1` は `Err("regex_match requires exactly 1 arg (pattern)")`。`VStr(s)` なら pattern compile 後に照合し、失敗時は `Err("value does not match regex")`。非 `VStr` は Err。
3. `filters_registry()` に `("regex_match", { name: "regex_match", signature: Validate, run: filter_regex_match })` を追加する。既存の `non_empty` / `in_range` と同じ `Validate` です。
4. `split_filter_spelling` を `regex_match` だけ first-colon split に対応させる。詳細は後述の colon-splitting 参照。
5. 実装完了後は即テストを開始する。今回の依頼は read-only なので実装・テスト実行はしていません。

## spec 側の論点と提案

regex dialect は filter descriptor doc だけでなく、新しい DR として固定するべきです。

理由は、DR-040 が regex を「type 方言を pre_filter で狭める」ための標準的手段として扱っており、さらに cross-host では regex 方言一致が再現性条件だと明記しているためです。これは単なる descriptor の API 説明ではなく、conformance と host 間互換性に関わる決定です。根拠: [DR-040](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu/main/docs/decisions/DR-040-type-registry-dialects-and-restriction.md:26>)、[DR-040](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu/main/docs/decisions/DR-040-type-registry-dialects-and-restriction.md:58>)。

提案:

- 新 DR で `kuu_regex_min` のような canonical subset 名を定義する。
- DESIGN §8.4 / filter descriptor には概要と参照だけを書く。
- `regex_match` の canonical default は `kuu_regex_min` とし、将来 `regex_match_re2` や host-native regex は標準/拡張 layer に逃がす。

## conformance fixture 輪郭案

match accepted:

- pattern: `^[a-z]+$`, input: `abc`, expected success。
- pattern: `^[a-z][a-z0-9]*$`, input: `a123`, expected success。
- pattern: `^colou?r$`, input: `color` / `colour`, expected success。

non-match rejected:

- pattern: `^[a-z]+$`, input: `abc1`, expected failure `kind: "filter"`, `reason: "filter_rejected"`。
- pattern: `^[0-9]+$`, input: `12a`, expected failure。
- pattern: `^ab*c$`, input: `acx`, expected failure。

partial-match vs full-match semantics:

- pattern: `[a-z]+`, input: `123abc456`, expected success。
- pattern: `^[a-z]+$`, input: `123abc456`, expected failure。
- pattern: `^abc`, input: `abcdef`, expected success。
- pattern: `abc$`, input: `123abc`, expected success。

escaping of meta-characters:

- pattern: `^a\\+b$`, input: `a+b`, expected success。
- pattern: `^a\\*b$`, input: `a*b`, expected success。
- pattern: `^\\[ok\\]$`, input: `[ok]`, expected success。
- pattern: `^key\\:value$`, input: `key:value`, expected success。
- pattern: `^[a\\-z]+$`, input: `a-z`, expected success。
- pattern: `^a.b$`, input: `acb`, expected pattern-definition failure if `.` is reserved unsupported; pattern `^a\\.b$`, input `a.b`, expected success。

## colon-splitting の扱い

現状の `split_colon(s)` は全文字を走査し、すべての `:` で分割し、空 segment も保持します。例: `":set:true"` は `["", "set", "true"]`。根拠: [installer.mbt](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/installer.mbt:171>)。

`filters.mbt` の `split_filter_spelling` はこの `split_colon` をそのまま使い、`parts[0]` を filter 名、残り全部を `args` にします。したがって現在のままでは `regex_match:^https?:` のような pattern は `args = ["^https?", ""]` のように複数引数へ壊れます。根拠: [filters.mbt](</Users/kawaz/.local/share/repos/github.com/kawaz/kuu.mbt/main/src/core/filters.mbt:151>)。

推奨は `regex_match` に限って「最初の colon 以降を pattern 1 個として扱う」です。

- `"regex_match:^[a-z]+$"` → name `regex_match`, args `["^[a-z]+$"]`
- `"regex_match:^https?://"` → name `regex_match`, args `["^https?://"]`
- `"in_range:1:65535"` → 従来通り args `["1", "65535"]`

この扱いなら既存の `in_range` や variant DSL の意味を壊さず、regex の自然な `:` 使用も許容できます。将来 object 詳細形が kuu.mbt に入ったら、`{"name":"regex_match","args":["^https?://"]}` も同じ意味にするのが良いです。
