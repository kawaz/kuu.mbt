# 実装レビューで発見された問題と解決策

Step 0〜11 の実装中にレビュー（codex / ペルソナレビュー）で発見された問題と、その解決策を記録する。

---

## Step 6: Finalize フェーズ

### C-01: Validate→Finalize 順序問題

- **問題**: `exclusive` / `at_least_one` が Validate Phase (Phase 3) で実行され、環境変数適用前の状態を見てしまう。環境変数で値が設定されているのに「未設定」と判定される。
- **発見経緯**: codex レビューで、env 適用と制約チェックの実行順序が保証されていない点を指摘。
- **解決策**: `exclusive` / `at_least_one` / `check_required` を `add_constraint` (Phase 3) から `add_finalizer` (Phase 4b) に移行。
- **選択理由**: 環境変数適用後に制約チェックすべき。Phase 3 (constraints) はユーザー定義の構文レベル制約（env 適用前の状態で判定すべきケース）用に残す。
- **コード参照**:
  - `src/validate/validate.mbt` L1-3: Design rationale コメント
  - `src/parse/parse.mbt` L362-366: Phase 3 / Phase 4b の分離コメント

### C-02: check_required/apply_env 登録順依存

- **問題**: ユーザーの呼び出し順で動作が壊れる。`check_required` を先に登録 → `apply_env` を後に登録すると、env 適用前に required チェックが走り `MissingRequired` が誤発火する。
- **発見経緯**: codex レビューで「登録順に依存する設計は脆弱」と指摘。
- **解決策**: `env_finalizers` 配列を Parser に追加。`parse.mbt` で `env_finalizers` → `finalizers` の順で実行する。`apply_env` は `add_env_finalizer` で登録し、制約チェックは `add_finalizer` で登録する。
- **選択理由**: 登録順に依存しない構造的保証。ユーザーがどの順番で API を呼んでも env 適用が制約チェックより先になる。代替案として「優先度付きフック」も検討したが、2段パイプラインの方が単純で十分。
- **コード参照**:
  - `src/finalize/finalize.mbt` L1-3: Design rationale コメント
  - `src/parse/parse.mbt` L373-379: Phase 4a (env) → Phase 4b (finalizers) の実行順

### C-03: apply_env が Positional/Command にも適用

- **問題**: `env_prefix` 設定時に Positional ノードにも環境変数が適用され、位置引数が暗黙に埋まってしまう。
- **発見経緯**: codex レビューで、env 適用の対象フィルタリングが不足していると指摘。
- **解決策**: `apply_env` 内に `if node.meta.kind != @core.Kind::Option { continue }` フィルタを追加。
- **選択理由**: 環境変数はオプション（フラグ含む）のみに適用すべき。Positional と Command は CLI 引数で明示指定するものであり、環境変数で暗黙に埋めるのは意味論的に誤り。
- **コード参照**:
  - `src/finalize/finalize.mbt` L29-32: Kind::Option フィルタ

### W-01: Flag 不正値サイレントスキップ

- **問題**: flag の reducer が不正値（`"banana"` 等）を `None` → `Reject` で無視していた。一方 int の reducer は `raise ParseError::Usage(InvalidValue)` でエラーにしており、一貫性がない。
- **発見経緯**: codex レビューで flag と int の不正値処理の非対称性を指摘。
- **解決策**: flag の reducer を `raise` に変更。不正値で `ParseError::Usage(InvalidValue)` を送出する。
- **選択理由**: int と flag の一貫性。不正入力はサイレントに無視すべきでなく、ユーザーに明確なエラーメッセージを返すべき。
- **コード参照**:
  - `src/core/combinators.mbt` L40-49: flag reducer の raise 実装

---

## Step 7: PreProcess フェーズ

### C-01: 行単位分割のみ（空白区切り未対応）

- **問題**: `@file` 展開で `--port 8080` のような行が1引数として扱われる。gcc / javac / rustc は空白区切り + クォート対応。
- **発見経緯**: codex レビューで、既存 CLI ツールの `@file` 仕様との乖離を指摘。
- **解決策**: `split_lines` を `split_args`（shell-like word splitting + quote / backslash 対応）に置換。
- **選択理由**: gcc / javac / rustc の `@file` 仕様に準拠。行単位分割では `--port 8080` を2引数にできず、実用的な CLI ツールとしては不十分。
- **コード参照**:
  - `src/preprocess/preprocess.mbt` L1-55: `split_args` 関数の実装

### C-02: 空文字引数 `""` 消失

- **問題**: `token.length() > 0` チェックにより、クォートで囲まれた空文字引数 `""` が消える。
- **発見経緯**: codex レビューでエッジケーステスト中に発見。
- **解決策**: `had_quote` フラグを追加。`token.length() > 0 || had_quote` で判定し、明示的な空文字引数を保持する。
- **選択理由**: `""` は明示的な空文字引数であり、有効な値。POSIX shell でも `""` はゼロ長の引数として渡される。
- **コード参照**:
  - `src/preprocess/preprocess.mbt` L12, L25, L30, L37: `had_quote` フラグの使用箇所

### C-03: 末尾 `\` 消失

- **問題**: `prev_was_backslash=true` のままループが終了すると、末尾のバックスラッシュが消える。
- **発見経緯**: codex レビューでバックスラッシュ処理のエッジケースを指摘。
- **解決策**: ループ後に `if prev_was_backslash { buf.write_char('\\') }` を追加。
- **選択理由**: 末尾のバックスラッシュはリテラルとして保持すべき（POSIX sh 準拠）。エスケープ対象の文字が続かない `\` はリテラル。
- **コード参照**:
  - `src/preprocess/preprocess.mbt` L46-49: 末尾バックスラッシュ処理

---

## Step 8: Output フェーズ（エラーメッセージ）

### C-01: AmbiguousMatch に did-you-mean 不適切

- **問題**: プレフィックス複数一致問題（`--verb` → `--verbose`, `--verbatim`）に対して単一のサジェストを出すのは意味的に誤り。
- **発見経緯**: codex レビューで、AmbiguousMatch と UnknownOption のエラー種別に応じた対応の違いを指摘。
- **解決策**: `did-you-mean` サジェストを `UnknownOption` のみに限定。
- **選択理由**: AmbiguousMatch は「入力が複数候補にプレフィックス一致する」エラー。正しい対応は候補の絞り込み（より長い名前の入力）であり、単一候補のサジェストではない。代替案として「候補一覧の表示」も検討したが、それは Step 9（ヘルプ生成）で対応予定。
- **コード参照**:
  - `src/output/error_format.mbt` L12-15: Design rationale コメント

---

## Step 9: Output フェーズ（ヘルプ生成）

### C-01: Usage 行で required positional が `[FILE]` 表示

- **問題**: `required=true` の positional も optional と同じ `[FILE]` で表示され、必須/任意の区別がつかない。
- **発見経緯**: codex レビューで clap 等の標準的 CLI ツールとの慣習の乖離を指摘。
- **解決策**: `required=true` → `<FILE>`（山括弧）、`required=false` → `[FILE]`（角括弧）で表示。
- **選択理由**: clap / argparse / cobra 等の標準的 CLI ツールの慣習に準拠。`<>` は必須、`[]` はオプショナルという表記は広く認知されている。
- **コード参照**:
  - `src/output/help.mbt` L59-72: Usage 行の positional 表示分岐

### C-02: aliases がヘルプに未反映

- **問題**: `format_option_display` が shorts と name / inversion / value_name しか表示せず、aliases が欠落していた。
- **発見経緯**: codex レビューで aliases の表示漏れを指摘。
- **解決策**: `format_option_display` に aliases の表示を追加。`, --{alias_name}` 形式で列挙。
- **選択理由**: エイリアスはユーザーの発見性に直結する。ヘルプに表示しなければ、エイリアスの存在自体が知られない。
- **コード参照**:
  - `src/output/help.mbt` L263-267: aliases 表示ループ

### C-03: global + Advanced の分類バグ

- **問題**: `global=true` のチェックが `visibility=Advanced` より先にあり、`Advanced` かつ `global` なオプションが Global Options セクションに入ってしまう。
- **発見経緯**: codex レビューで分類ロジックの条件順序を指摘。
- **解決策**: `visibility` チェックを `global` チェックより先に配置。`Advanced` → `Global` → 通常の順で判定。
- **選択理由**: `Advanced` は「上級者向け」という意味論であり、`global` 属性（スコープの性質）より表示分類が優先されるべき。Advanced + global なオプションは Advanced Options セクションに表示されるのが自然。
- **コード参照**:
  - `src/output/help.mbt` L25-31: 分類ロジック（visibility → global → 通常の順）

### C-04: Command/Positional の Deprecated 未注記

- **問題**: `[deprecated]` 付与が Options セクションのみで、Commands / Arguments セクションには適用されていなかった。
- **発見経緯**: codex レビューで一貫性の欠如を指摘。
- **解決策**: Commands / Arguments セクションでも `visibility == Deprecated` の場合に `[deprecated]` を表示。
- **選択理由**: 一貫性。deprecated はオプション・コマンド・位置引数のいずれにも適用可能な属性であり、ヘルプ表示でも統一的に扱うべき。
- **コード参照**:
  - `src/output/help.mbt` L99-103: Commands セクションの deprecated 表示
  - `src/output/help.mbt` L130-134: Arguments セクションの deprecated 表示

---

## Step 10: Output フェーズ（補完生成）

### C-01: Zsh の `:` 未エスケープ

- **問題**: description に `:` が含まれると zsh の `_describe` で補完が破損する。zsh は `:` を区切り文字として解釈するため。
- **発見経緯**: codex レビューで zsh 補完の仕様を踏まえたエスケープ不足を指摘。
- **解決策**: `escape_zsh_description` 関数を追加。`:` → `\:` にエスケープする。
- **選択理由**: zsh の補完仕様で `:` は `value:description` 形式の区切り文字。エスケープしなければ description 中のコロン以降が別フィールドとして解釈される。
- **コード参照**:
  - `src/output/completion.mbt` L120-122: `escape_zsh_description` 関数
  - `src/output/completion.mbt` L142: 呼び出し箇所

### C-02: Fish のタブ/改行未エスケープ

- **問題**: description にタブが含まれると fish のタブ区切りが壊れる。
- **発見経緯**: codex レビューで fish 補完の仕様を踏まえたエスケープ不足を指摘。
- **解決策**: `escape_fish_description` 関数を追加。タブ → スペース、改行 → 除去。
- **選択理由**: fish の補完は `value\tdescription` 形式でタブを区切り文字として使用する。タブや改行が description に含まれると補完出力が壊れる。
- **コード参照**:
  - `src/output/completion.mbt` L125-129: `escape_fish_description` 関数
  - `src/output/completion.mbt` L146: 呼び出し箇所

### C-03: choices フィールド未活用

- **問題**: `OptMeta` に `choices` フィールドがあるのに補完で使われていない。
- **発見経緯**: codex レビューで choices の活用漏れを指摘。
- **解決策**: `collect_value_completions` 関数を別途提供。`collect_completions` は名前補完に限定。
- **選択理由**: 名前補完と値補完は文脈が異なる。名前補完はどこでも有効だが、値補完は特定オプションの後でのみ有効。2つを混ぜると、値候補がオプション名と並んで表示される不適切な状態になる。
- **コード参照**:
  - `src/output/completion.mbt` L38-39: Design rationale コメント
  - `src/output/completion.mbt` L110: `collect_value_completions` 関数

### C-04: Custom inversion の補完値が不正

- **問題**: `Custom(pos, neg)` を `--{pos}` / `--{neg}` で出力していたが、名前解決は `--{pos}-{name}` / `--{neg}-{name}` で行われる。補完値と実際に受理される名前が不一致。
- **発見経緯**: codex レビューで名前解決側との整合性を指摘。
- **解決策**: `--{pos}-{name}` / `--{neg}-{name}` に修正。
- **選択理由**: 名前解決側との整合性。補完で出力した値がそのまま CLI に入力可能であるべき。
- **コード参照**:
  - `src/output/completion.mbt` L82-90: Custom inversion の補完候補生成

### W-01: Deprecated エイリアスが補完に含まれる

- **問題**: `deprecated: true` のエイリアスも補完候補に出てしまう。
- **発見経緯**: codex レビューで deprecated エイリアスの補完除外漏れを指摘。
- **解決策**: deprecated エイリアスを補完候補から除外（`if not(al.deprecated)` フィルタ追加）。
- **選択理由**: 補完の目的はユーザーに推奨される入力を提示すること。deprecated なエイリアスを補完候補に含めると、ユーザーが古い形式を使ってしまう。
- **コード参照**:
  - `src/output/completion.mbt` L62-66: Option aliases の deprecated フィルタ
  - `src/output/completion.mbt` L97-100: Command aliases の deprecated フィルタ

---

## Step 11: 拡張コンビネータ

### C-01: count Negate テストが setter 直接操作

- **問題**: テストで `(verbose.setter)(0, 2)` を使って内部実装に依存している。内部構造の変更でテストが壊れる。
- **発見経緯**: codex レビューでテストの実装依存を指摘。
- **解決策**: `--verbose --verbose --no-verbose` の実パースフローでテスト。
- **選択理由**: テストは公開 API を通じて行うべき。setter の直接操作は内部実装への依存であり、リファクタリング耐性がない。

### W-01: custom の Thunk 二重評価

- **問題**: `custom()` 内で `Thunk` を評価して store に初期値を設定し、`to_opts()` 内の `reset_to_initial` でも再評価される。副作用のある Thunk で二重実行が問題になる。
- **発見経緯**: codex レビューで Thunk のライフサイクル管理の問題を指摘。
- **解決策**: `custom()` 内で `Val(initial_val)` に正規化してから `Opt` に格納。store の初期値と `Opt.initial` が同一の評価結果を共有する。
- **選択理由**: 副作用のある Thunk の二重実行を防止。正規化により `to_opts()` 内の `reset_to_initial` が再評価を行わず、最初の評価結果を再利用する。
- **コード参照**:
  - `src/core/combinators.mbt` L501-503: Design rationale コメント
  - `src/core/combinators.mbt` L512-519: Val への正規化処理

### W-02: optional_value Negate テストが setter 依存

- **問題**: テストで `(color.setter)(0, Some("always"))` により事前設定し、`reset_to_initial` で上書きされる可能性がある。テストが意図した動作（Negate）を正しく検証できていない。
- **発見経緯**: codex レビューでテストの実装依存を指摘（C-01 と同種の問題）。
- **解決策**: `--color --no-color` の実パースフローに変更。
- **選択理由**: C-01 と同様、テストは公開 API を通じて行うべき。実パースフローでの検証により、統合的な動作確認ができる。
