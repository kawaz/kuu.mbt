# PoC テスト要件分析レポート

## 1. サマリー

| 項目 | 値 |
|------|-----|
| PoC テスト総数 | 約 180 件（R-001 〜 R-414、欠番含む） |
| カテゴリ数 | 9 カテゴリ |
| 現在の実装テスト数 | 245 件（src/ 以下、15 ファイル） |

### カバレッジ概要

| 状態 | 件数 | 説明 |
|------|------|------|
| ✅ カバー済み | 約 95 件 | 現在のテストで同等の要件が検証されている |
| ⚠️ 部分カバー | 約 25 件 | 関連機能はあるが特定ケースが未テスト |
| ❌ 未実装 | 約 20 件 | 機能自体が未実装 |
| 🔮 将来実装 | 約 40 件 | DESIGN.md で将来ステップ（group 等） |

---

## 2. カテゴリ別要件一覧

### 2.1 トークン化 (tokenize_test.mbt: R-001〜R-012)

現在の実装では `decompose_wbtest.mbt` でロングオプションの分解、ショートオプションの分解をテストしている。トークン化は parse 内部で暗黙的に処理されており、独立した tokenize フェーズは存在しない。

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ✅ | R-001 | `--verbose` 形式のロングオプションをトークン化 | decompose_wbtest.mbt + parse_test.mbt で検証 |
| ✅ | R-002 | `--format=json` の `=` 付きロングオプションを分割 | decompose_wbtest.mbt `--port=8080` テスト |
| ✅ | R-003 | `--format json` の空白区切りは別トークン | parse_test.mbt `--port 8080` テスト |
| ✅ | R-004 | `-abc` 連結ショートオプション | decompose_wbtest.mbt `-abc` テスト |
| ✅ | R-005 | `-v` 単一ショートオプション | decompose_wbtest.mbt `-v` テスト |
| ✅ | R-006 | オプション記号なし引数は位置引数 | parse_test.mbt Positional テスト |
| ✅ | R-007 | `--` 以降は全て位置引数 | parse_test.mbt `--` セパレータテスト |
| ⚠️ | R-008 | 単独 `-` は位置引数トークン | 明示テストなし。parse 内部で処理される可能性あるが未検証 |
| ✅ | R-009 | 空引数でトークン列も空 | parse_test.mbt 引数なしテスト |
| ✅ | R-010 | 混在トークン化 | parse_test.mbt 複合テスト |
| ✅ | R-011 | `--format=` で空値分割 | decompose_wbtest.mbt `--port=` テスト |
| ✅ | R-012 | `--query=a=b` で最初の `=` のみ区切り | decompose_wbtest.mbt `--key=val=ue` テスト |

### 2.2 名前解決 (resolve_test.mbt: R-013〜R-025)

`name_resolve_wbtest.mbt` で `resolve_long` / `resolve_short` を直接テストしている。

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ✅ | R-013 | ロングオプション完全一致 | name_resolve_wbtest.mbt 完全一致テスト |
| ✅ | R-014 | エイリアス名で解決 | name_resolve_wbtest.mbt エイリアス一致テスト |
| ✅ | R-015 | 複数エイリアスで解決 | name_resolve_wbtest.mbt（複数エイリアスの meta で検証） |
| ✅ | R-016 | `--no-verbose` の PrefixNo 反転 | name_resolve_wbtest.mbt No 反転テスト |
| ✅ | R-017 | `--enable-cache` の正方向 | name_resolve_wbtest.mbt EnableDisable テスト |
| ✅ | R-018 | `--disable-cache` の反転方向 | name_resolve_wbtest.mbt EnableDisable テスト |
| ✅ | R-019 | `--with-ssl` の正方向 | name_resolve_wbtest.mbt Custom 反転テスト |
| ✅ | R-020 | `--without-ssl` の反転方向 | name_resolve_wbtest.mbt Custom 反転テスト |
| ✅ | R-021 | 未知ロングオプション → UnknownOption | parse_test.mbt 未知オプションテスト |
| ✅ | R-022 | 反転未定義での no- 付与 → UnknownOption | name_resolve_wbtest.mbt 不一致テスト |
| ✅ | R-023 | ショートオプション文字の解決 | name_resolve_wbtest.mbt resolve_short テスト |
| ✅ | R-024 | 複数ショートオプション解決 | name_resolve_wbtest.mbt（複数 shorts の meta） |
| ✅ | R-025 | 未知ショートオプション → UnknownOption | name_resolve_wbtest.mbt 不一致テスト |

### 2.3 パース (parse_test.mbt: R-026〜R-106)

`parse_test.mbt` と `combinators_ext_test.mbt` でカバー。

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ✅ | R-026 | 引数なしでデフォルト値反映 | parse_test.mbt 引数なしテスト |
| ✅ | R-027 | `--verbose` でフラグ true | parse_test.mbt 単一フラグテスト |
| ✅ | R-028 | `--format yaml` 空白区切りパース | parse_test.mbt string/int 値テスト |
| ✅ | R-029 | `--format=yaml` eq 形式パース | parse_test.mbt eq 形式テスト |
| ✅ | R-030 | `--eval expr` 複数回で Append | combinators_ext_test.mbt append テスト |
| ✅ | R-031 | 位置引数のみ → positional 格納 | parse_test.mbt Positional テスト |
| ✅ | R-032 | `--` 以降はオプション非解釈 | parse_test.mbt `--` セパレータテスト |
| ✅ | R-033 | `--no-verbose` で反転 false | parse_test.mbt 反転フラグテスト |
| ⚠️ | R-034 | `--disable-cache` で EnableDisable 反転 | name_resolve で解決は検証済み。parse 統合テストでの検証は不足 |
| ⚠️ | R-035 | `--enable-cache` で正方向 true | 同上 |
| ✅ | R-036 | `-v` ショートフラグ | parse_test.mbt ショートオプションテスト |
| ✅ | R-037 | `-abc` 連結ショートフラグ展開 | parse_test.mbt ショートオプション結合テスト |
| ✅ | R-038 | `-f output.txt` ショート値付き | parse_test.mbt ショートオプション+値テスト |
| ⚠️ | R-039 | `-abcVALUE` 連結で Flag+Single 混在 | parse_test.mbt `-vp` テストはあるがフラグ+値の連結は未検証 |
| ⚠️ | R-040 | デフォルト true のフラグ | combinators_wbtest.mbt で flag reducer テストあるが、デフォルト true の統合テストなし |
| ⚠️ | R-041 | `default=Some(...)` の Single デフォルト | string/int コンビネータのデフォルト値テストなし |
| ✅ | R-042 | `defaults=[...]` の Append デフォルトリスト | combinators_ext_test.mbt append 未指定テスト（空リスト） |
| ⚠️ | R-043 | `default=None` の Single で結果なし | combinators_wbtest.mbt で Value(None) returns None テストあるが、parse 統合なし |
| ✅ | R-044 | `defaults=[]` の Append で空リスト | combinators_ext_test.mbt append 未指定テスト |
| ✅ | R-045 | 未知オプション → UnknownOption | parse_test.mbt 未知オプションテスト |
| ✅ | R-046 | 値不足 → MissingValue | parse_test.mbt 値不足テスト |
| ✅ | R-047 | required 未指定 → MissingRequired | validate_test.mbt check_required テスト |
| ⚠️ | R-048 | choices 違反 → InvalidChoice | choices は meta に設定可能。parse 時のバリデーションテストなし |
| ⚠️ | R-049 | `--help` で HelpRequested | parse 内での自動 --help 処理の明示テストなし |
| ⚠️ | R-050 | ユーザ定義 `--help` で通常処理 | 未テスト |
| ✅ | R-051 | 混在引数の正しいパース | parse_test.mbt フックなしパーステスト |
| ⚠️ | R-052 | `--verbose=true`/`--verbose=false` の真偽値解釈 | combinators_wbtest.mbt で flag reducer Value(Some) テストあるが "true"/"false" の明示テストなし |
| ✅ | R-053 | `--verbose=banana` → エラー | combinators_wbtest.mbt flag reducer invalid value テスト |
| ✅ | R-054 | Append `--eval=value` 形式 | combinators_ext_test.mbt append テスト（空白区切りのみ） |
| ⚠️ | R-055 | Append ショート `-e expr1 -e expr2` | append のショートオプションテストなし |
| ✅ | R-056 | ショート値不足 → エラー | parse_test.mbt ショートオプション値不足テスト |
| ✅ | R-057 | required 満たされた場合の正常パース | validate_test.mbt check_required 正常テスト |
| ⚠️ | R-058 | choices に含まれる値の正常パース | meta に choices 設定はできるが、parse 時の検証テストなし |
| ✅ | R-059 | Single 後勝ち | parse_test.mbt 重複オプション後勝ちテスト |
| ⚠️ | R-060 | 空文字列引数の位置引数受付 | 未テスト |
| ⚠️ | R-061 | `--` のみで positional/rest 空 | 未テスト |
| ⚠️ | R-062 | `--no-format` クリア後の再設定 | 未テスト |
| ⚠️ | R-063 | `--no-format=ignored` で = 値無視 | 未テスト |
| ⚠️ | R-064 | `--no-eval=whatever` で Append リセット | 未テスト |
| ⚠️ | R-065 | `--no-verbose=true` で反転の true → false | 未テスト |
| ⚠️ | R-066 | `--no-verbose=false` で二重否定 → true | 未テスト |
| ⚠️ | R-067 | ショート MissingValue メッセージに `-f` 表示 | parse_test.mbt でエラー種別は検証するがメッセージ内容は未検証 |
| ✅ | R-068 | Count `--verbose` 1回で 1 | combinators_ext_test.mbt count テスト |
| ⚠️ | R-069 | Count ショート `-v` で 1 | count のショートテストなし |
| ✅ | R-070 | Count `-vvv` で 3 | combinators_ext_test.mbt count `-vvv` テスト |
| ⚠️ | R-071 | Count `-v -v --verbose` 混在合算 | 未テスト |
| ✅ | R-072 | Count `--no-verbose` でリセット | combinators_ext_test.mbt count Negate リセットテスト |
| ⚠️ | R-073 | Count `--no-verbose` 後に `-vv` 再加算 | 未テスト |
| ✅ | R-074 | Count デフォルト値 0 | combinators_ext_test.mbt count 未指定テスト |
| ⚠️ | R-075 | Count `-vxv` 別オプション混在 | 未テスト |
| ✅ | R-076 | Count `--verbose=3` で直接数値指定 | combinators_ext_test.mbt count `--verbose=5` テスト |
| ⚠️ | R-077 | Count 非ゼロデフォルト値 | 未テスト |
| ✅ | R-078 | OptionalValue 値なし → implicit 値 | combinators_ext_test.mbt optional_value テスト |
| ✅ | R-079 | OptionalValue `--color=always` → 指定値 | combinators_ext_test.mbt optional_value `=` 形式テスト |
| ⚠️ | R-080 | OptionalValue `--color xxx` で次トークン非消費 | 未テスト |
| ✅ | R-081 | OptionalValue `--no-color` → negated 値 | combinators_ext_test.mbt optional_value Negate テスト |
| ⚠️ | R-082 | OptionalValue `negated=None` でエントリ削除 | 未テスト |
| ⚠️ | R-083 | OptionalValue `--no-color=xxx` で = 値無視 | 未テスト |
| ⚠️ | R-084 | OptionalValue `default=Some(...)` | 未テスト |
| ✅ | R-085 | OptionalValue `default=None` で未指定時なし | combinators_ext_test.mbt optional_value 未指定テスト |
| ⚠️ | R-086 | OptionalValue choices 有効値通過 | 未テスト |
| ⚠️ | R-087 | OptionalValue choices 無効値エラー | 未テスト |
| ⚠️ | R-088 | OptionalValue ショート定義 → DefinitionError | 未テスト |
| ❌ | R-089 | Append `n=2` で 2 引数 1 エントリ | n パラメータ未実装 |
| ❌ | R-090 | Append `n=2` 複数エントリ | n パラメータ未実装 |
| ❌ | R-091 | Append `n=2` 引数不足エラー | n パラメータ未実装 |
| ❌ | R-092 | Append `n=2` に `=` 形式エラー | n パラメータ未実装 |
| ❌ | R-093 | Append `n=2` `--no-arg` リセット | n パラメータ未実装 |
| ❌ | R-094 | Append `n=2` ショート | n パラメータ未実装 |
| ❌ | R-095 | Append `n=2` ショート連結 | n パラメータ未実装 |
| ❌ | R-096 | Append `n=3` 3 引数エントリ | n パラメータ未実装 |
| ❌ | R-097 | Append `n=2` ショート引数不足 | n パラメータ未実装 |
| ❌ | R-098 | Append `n=2` デフォルト値 | n パラメータ未実装 |
| ⚠️ | R-099 | Single の値としての `--` | 未テスト |
| ⚠️ | R-100 | `--version` で VersionRequested | 未テスト |
| ⚠️ | R-101 | ユーザ定義 `--version` で通常処理 | 未テスト |
| ⚠️ | R-102 | Single の値としての `--version` | 未テスト |
| ⚠️ | R-103 | `--` 後の `--version` は rest に入る | 未テスト |
| ⚠️ | R-104 | `-V` は `--version` トリガーにならない | 未テスト |
| ⚠️ | R-105 | `--version=value` で VersionRequested | 未テスト |
| ⚠️ | R-106 | Append choices 無効値エラー | 未テスト |

### 2.4 Group 関連 (R-107〜R-131)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| 🔮 | R-107〜R-131 | Group 関連テスト全般 | DESIGN.md Step 11 で将来実装予定 |

### 2.5 型定義テスト (types_test.mbt: R-132〜R-186)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ✅ | R-132〜R-186 | 型定義・等価性・バリアント | core/types_wbtest.mbt + core/core_test.mbt でカバー |

### 2.6 コマンド・サブコマンド (command_test.mbt: R-200〜R-229)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ✅ | R-200 | サブコマンドなしのコマンド | parse_test.mbt 基本パーステスト |
| ✅ | R-201 | 1 階層サブコマンド解決 | parse_test.mbt サブコマンド基本パース |
| ⚠️ | R-202 | 多段サブコマンド再帰解決 | 未テスト |
| ✅ | R-203 | global_opt フラグ先行でサブコマンド探索 | parse_test.mbt global オプション引き継ぎテスト |
| ⚠️ | R-204 | global_opt 値付きオプション先行 | 未テスト |
| ⚠️ | R-205 | `--opt=value` 形式 global_opt 先行 | 未テスト |
| ✅ | R-206 | サブコマンドエイリアス解決 | parse_test.mbt Command エイリアステスト |
| ⚠️ | R-207 | `--` でサブコマンド探索停止 | 未テスト |
| ⚠️ | R-208 | 未知サブコマンド名 → エラー | 未テスト |
| ⚠️ | R-209 | サブコマンド探索中の未知オプション → エラー | 未テスト |
| ⚠️ | R-210 | サブコマンド定義ありで位置引数 → エラー | 未テスト |
| ⚠️ | R-211 | `--no-xxx` がサブコマンド探索を妨げない | 未テスト |
| ✅ | R-212 | サブコマンドなし単純パース | parse_test.mbt 基本テスト群 |
| ✅ | R-213 | サブコマンド後の子オプションパース | parse_test.mbt サブコマンド+子オプションテスト |
| ✅ | R-214 | global_opt の位置自由（前後同結果） | parse_test.mbt global オプション引き継ぎテスト |
| ⚠️ | R-215 | 多段ネスト global_opts 継承 | 未テスト |
| ⚠️ | R-216 | `help_on_empty=true` → HelpRequested | 未テスト |
| ⚠️ | R-217 | サブコマンドの `help_on_empty=true` | 未テスト |
| ⚠️ | R-218 | `help_on_empty=false` で正常終了 | 未テスト |
| ⚠️ | R-219 | `--help` → HelpRequested | R-049 と重複。未テスト |
| ⚠️ | R-220 | `--version` → VersionRequested | R-100 と重複。未テスト |
| ❌ | R-221〜R-229 | Append n=2 + サブコマンド、positional_spec | n パラメータ・positional_spec 未実装 |

### 2.7 コマンド定義バリデーション (validate_command_test.mbt: R-230〜R-244)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ⚠️ | R-230〜R-244 | コマンド定義時バリデーション（名前重複、循環参照等） | validate_test.mbt に exclusive/at_least_one/check_required があるが、コマンド定義自体のバリデーションは未テスト |

### 2.8 オプション定義バリデーション (validate_opts_test.mbt: R-245〜R-289)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ⚠️ | R-245〜R-289 | オプション定義時バリデーション（名前空、ショート重複等） | 未テスト。定義時の型安全性は MoonBit の型システムで一部保証されるが、ランタイムバリデーションは未実装 |

### 2.9 多段デフォルト適用 (apply_defaults_test.mbt: R-290〜R-333)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ✅ | R-290〜R-310 | 環境変数デフォルト適用 | finalize_test.mbt の apply_env テスト群でカバー |
| ⚠️ | R-311〜R-333 | 設定ファイル・多段デフォルト | 環境変数は実装済み。設定ファイル等の多段デフォルトは未実装 |

### 2.10 統合テスト (integration_test.mbt: R-334〜R-380)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ⚠️ | R-334〜R-380 | エンドツーエンド統合テスト | parse_test.mbt のフックパイプラインテストで部分的にカバー。包括的な統合テストは不足 |

### 2.11 ストア独立性 (poc3_test.mbt: R-400〜R-403)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ✅ | R-400〜R-403 | ストアの独立性（ResultMap 分離等） | core の設計で ResultMap + clone_fns による独立性を実現。combinators_wbtest.mbt の try_reduce/commit_reduce テストでカバー |

### 2.12 型消去・ストア (poc4_test.mbt: R-404〜R-414)

| 状態 | ID | 要件 | 備考 |
|------|-----|------|------|
| ✅ | R-404〜R-414 | 型消去パターン（ErasedNode による統一インターフェース） | combinators_wbtest.mbt の ErasedNode テスト群でカバー |

---

## 3. 不足テスト/機能の優先度リスト

### 優先度 A: 既存機能でテスト追加可能

現在の実装で機能は存在するが、テストが不足しているもの。

| ID | 要件 | 追加工数 |
|----|------|----------|
| R-008 | 単独 `-` の位置引数扱い | 小 |
| R-034, R-035 | EnableDisable の parse 統合テスト | 小 |
| R-039 | `-abcVALUE` 連結ショートのフラグ+値混在 | 小 |
| R-052 | `--verbose=true`/`--verbose=false` の真偽値解釈 | 小 |
| R-055 | Append のショートオプション `-e x -e y` | 小 |
| R-060 | 空文字列引数の位置引数受付 | 小 |
| R-061 | `--` のみで positional/rest 空 | 小 |
| R-067 | ショート MissingValue メッセージの `-f` 表示 | 小 |
| R-069 | Count ショート `-v` | 小 |
| R-071 | Count 混在合算 `-v -v --verbose` | 小 |
| R-073 | Count リセット後再加算 | 小 |
| R-075 | Count `-vxv` 別オプション混在カウント | 小 |
| R-077 | Count 非ゼロデフォルト値 | 小 |
| R-080 | OptionalValue 空白区切り次トークン非消費 | 小 |
| R-099 | Single 値としての `--` | 小 |
| R-202 | 多段サブコマンド再帰解決 | 中 |
| R-204, R-205 | global_opt 値付きオプション先行 | 小 |
| R-207 | `--` でサブコマンド探索停止 | 小 |
| R-211 | `--no-xxx` がサブコマンド探索を妨げない | 小 |
| R-214 | global_opt 前後位置テスト拡充 | 小 |
| R-215 | 多段ネスト global_opts 継承 | 中 |

### 優先度 B: 小規模機能追加が必要

機能の拡張や新規バリデーションの追加が必要なもの。

| ID | 要件 | 追加工数 |
|----|------|----------|
| R-048, R-058, R-106 | choices バリデーション（parse 時の自動検証） | 中 |
| R-049, R-050, R-219 | `--help` 自動処理 / ユーザ定義オーバーライド | 中 |
| R-062〜R-066 | Negate 後の再設定、`=` 値無視、二重否定 | 中 |
| R-082〜R-084 | OptionalValue の negated=None、default=Some | 小 |
| R-086〜R-088 | OptionalValue choices / ショート制限 | 小 |
| R-100〜R-105 | `--version` 自動処理 / VersionRequested | 中 |
| R-208〜R-210 | サブコマンド探索エラー（未知コマンド、未知オプション、位置引数制限） | 中 |
| R-216〜R-218 | `help_on_empty` 機能 | 小 |
| R-230〜R-244 | コマンド定義時バリデーション | 中 |
| R-245〜R-289 | オプション定義時バリデーション | 大 |
| R-311〜R-333 | 設定ファイル多段デフォルト | 大 |
| R-334〜R-380 | 包括的統合テスト | 大 |

### 優先度 C: 大規模機能追加が必要

| ID | 要件 | 追加工数 |
|----|------|----------|
| R-089〜R-098 | Append `n` パラメータ（複数引数グルーピング） | 大 |
| R-221〜R-229 | Append n=2 + サブコマンド、positional_spec | 大 |

### 将来実装 (DESIGN.md Step 11)

| ID | 要件 | 備考 |
|----|------|------|
| R-107〜R-131 | Group（繰り返しオプション群、雛形 clone + clone ID 管理） | DESIGN.md Step 11 |
