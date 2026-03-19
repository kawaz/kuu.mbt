---
type: implementation
---

# DR-050: Filter 充実 + Sugar コンビネータ追加

## 背景

kuu の FilterChain は 11 個の built-in パーツを持つが、CLI パーサとして頻出するパターンにはカバレッジ不足がある。特に:

- **正規表現**: match/replace/split が未提供。MoonBit 標準の `@string.Regex` でランタイム正規表現が利用可能
- **文字列バリデーション**: starts_with/ends_with/contains/長さチェックが未提供
- **文字列変換**: replace/trim_start/trim_end/to_upper が未提供
- **数値バリデーション**: Double の範囲チェック、正値/非負値チェックが未提供
- **Sugar コンビネータ**: float_opt/append_float が未提供（int_opt/append_int の対称性）

## 設計方針

### 原則

1. **FilterChain.run の契約を維持** — 全フィルタの `run` は `(A) -> B raise ParseError` の形。フィルタ**生成時**の panic（regex パターン不正等）はこの契約の対象外
2. **既存パーツの組み合わせで済むものは追加しない** — in_range + parse_float の組み合わせ等
3. **正規表現パターンはフィルタ生成時に検証** — `Regex::unsafe_from_string` で不正パターンは実行時 panic（プログラミングエラー）
4. **命名規則**: validate 系は `Filter::xxx()` (条件名)、変換系は `Filter::xxx()` (動詞)、パース系は `Filter::parse_xxx()`
5. **数値 Filter の命名**: Int 版は型プレフィックスなし（`in_range`, `positive` 等）、Double 版は `float_` プレフィックス（`float_in_range`）。MoonBit がオーバーロード非対応のため

### 依存追加

`src/core/moon.pkg` に `moonbitlang/core/string` を追加（`@string.Regex` 使用のため）。

## 追加 Filter 一覧

### A. 文字列バリデーション

| Filter | 型 | 機能 |
|---|---|---|
| `starts_with(prefix)` | `String → String` | prefix で始まることを検証 |
| `ends_with(suffix)` | `String → String` | suffix で終わることを検証 |
| `contains(substr)` | `String → String` | 部分文字列を含むことを検証 |
| `min_length(n)` | `String → String` | 文字列長 >= n を検証（UTF-16 コードユニット数） |
| `max_length(n)` | `String → String` | 文字列長 <= n を検証（UTF-16 コードユニット数） |
| `min_codepoints(n)` | `String → String` | コードポイント数 >= n を検証（サロゲートペア対応） |
| `max_codepoints(n)` | `String → String` | コードポイント数 <= n を検証（サロゲートペア対応） |
| `min_graphemes(n)` | `String → String` | grapheme cluster 数 >= n を検証（ZWJ/国旗/スキントーン対応） |
| `max_graphemes(n)` | `String → String` | grapheme cluster 数 <= n を検証（ZWJ/国旗/スキントーン対応） |

文字列長フィルタは3段階の粒度を提供:
- `length`: UTF-16 コードユニット（MoonBit の `String.length()`）
- `codepoints`: Unicode コードポイント（`String.char_length()`）
- `graphemes`: 書記素クラスタ（`@unicodegrapheme.graphemes()`、視覚的な「文字」数）

### B. 文字列変換

| Filter | 型 | 機能 |
|---|---|---|
| `to_upper()` | `String → String` | 大文字変換（to_lower の対） |
| `trim_start()` | `String → String` | 先頭空白除去 |
| `trim_end()` | `String → String` | 末尾空白除去 |
| `replace(old, new)` | `String → String` | 最初の一致を置換 |
| `replace_all(old, new)` | `String → String` | 全一致を置換 |

### C. 正規表現フィルタ

| Filter | 型 | 機能 |
|---|---|---|
| `regex_match(pattern)` | `String → String` | 正規表現に部分マッチすることを検証（全体一致は `^...$`） |
| `regex_replace(pattern, replacement)` | `String → String` | 正規表現で全置換 |
| `regex_split(pattern)` | `String → Array[String]` | 正規表現で分割 |

正規表現構文は MoonBit の `lexmatch` 準拠（POSIX 文字クラス `[[:digit:]]` 等を使用、`\d`/`\w`/`\s` は非対応）。

### D. 型パース

| Filter | 型 | 機能 |
|---|---|---|
| `parse_bool()` | `String → Bool` | true/false/1/0 を Bool にパース |

### E. 数値バリデーション

| Filter | 型 | 機能 |
|---|---|---|
| `float_in_range(min, max)` | `Double → Double` | [min, max] 範囲検証（NaN は拒否） |
| `positive()` | `Int → Int` | > 0 検証 |
| `non_negative()` | `Int → Int` | >= 0 検証 |
| `clamp(min, max)` | `Int → Int` | 範囲外の値をクランプ（変換） |

## 追加 Sugar コンビネータ

| コンビネータ | 戻り型 | 実装 |
|---|---|---|
| `float_opt` | `Opt[Double]` | `custom(pre=Filter::parse_float())` |
| `append_float` | `Opt[Array[Double]]` | `custom_append(pre=Filter::parse_float())` |

パラメータは int_opt/append_int と対称（name, default, default_fn, global, aliases, shorts, description, env, value_name, hidden, post, choices, implicit_value, variations）。

## 実装計画

TDD で進行。各フェーズでテスト先行。

### Phase 1: 文字列バリデーション + 変換フィルタ（A + B）
- 新しい import 不要（String の組み込みメソッドで実装可能）
- テスト: 各フィルタの正常系 + エラー系

### Phase 2: 正規表現フィルタ（C）
- `moonbitlang/core/string` を moon.pkg に追加
- `@string.Regex` を使用
- テスト: パターンマッチ/置換/分割の正常系 + エラー系

### Phase 3: 数値フィルタ + parse_bool（D + E）
- テスト: 境界値テスト重点

### Phase 4: Sugar コンビネータ（float_opt, append_float）
- options.mbt に追加
- テスト: パース統合テスト

## レビューで発見した問題と修正

- **float_in_range の NaN 素通り**: IEEE 754 では NaN との比較が全て false を返すため、`v < min || v > max` だけでは NaN がバリデーションを素通りする。`v.is_nan()` ガードを先頭に追加して修正。
- **min_length/max_length の文字数カウント**: `String.length()` は UTF-16 コードユニット数を返す。DR-049 の grapheme cluster 対応方針との不整合を docstring で明記。

## テスト

- filter_wbtest.mbt: 48件追加（フィルタ単体テスト + NaN テスト）
- parse_wbtest.mbt: 10件追加（float_opt 7件 + append_float 3件）
- 全テスト: 1106 → 1158件（+52件）

## 不採用事項

- **path_opt / url_opt**: ドメイン特化すぎる。custom + regex_match/validate で実現可能
- **enum_opt**: MoonBit のジェネリック制約上、汎用的な enum マッピングは難しい。custom + parse で代替
- **float_clamp**: clamp は Int のみ。Double 版は需要が出てから
