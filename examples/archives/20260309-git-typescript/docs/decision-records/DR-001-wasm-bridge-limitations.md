# DR-001: WASM bridge の制限事項と対処

## 背景

kuu の WASM bridge (`kuu_parse`) は、kuu コアの全機能ではなく JSON schema で表現可能な機能のみをサポートしています。このデモプロジェクトでは、サポートされない機能に対してどう対処するかの判断が必要でした。

## 制限事項と対処

### serial 非対応

**問題**: `git push <remote> <branch>` のように複数の位置引数を順番に消費する `serial` が使えません。

**対処**: `positional` (最初の1つ) + `rest` (残り全部) で代用しています。

- `push`: `positional("remote")` + `rest("refspecs")`
- `pull`: `positional("remote")` + `rest("refspecs")`
- `remote rename`: `positional("old")` + `rest("remaining")`

**影響**: 2番目以降の位置引数に個別の名前を付けられないため、`rest` として配列で受け取ることになります。パース結果の意味を TypeScript 側で解釈する必要があります。

### exclusive 非対応

**問題**: `--rebase` と `--ff-only` のような排他的オプションの制約を WASM bridge 側で検証できません。

**対処**: 今回は省略しています。必要であれば TypeScript 側でパース結果を検証するバリデーション層を追加できます。

**影響**: 排他的なオプションを同時に指定してもエラーにならず、両方 `true` になります。

### required 非対応

**問題**: `commit -m` の `-m` を必須にする `required` が使えません。

**対処**: 今回は省略しています。TypeScript 側でパース結果を検証してエラーを出すことは可能です。

**影響**: 必須オプションなしでも正常にパースが完了します（デフォルト値が使われます）。

### require_cmd 非対応

**問題**: サブコマンドなしで実行された場合に自動でヘルプを表示する `require_cmd` が使えません。

**対処**: TypeScript 側で `result.command === undefined` を検出してヘルプ表示を実装できます（今回は省略し、メッセージ表示のみ）。

**影響**: 引数なしで実行すると `ok: true` でサブコマンドなしの結果が返ります。

### variations 非対応

**問題**: `--no-verify` (verify のデフォルト true を false に反転) のような `variations` パターンが使えません。

**対処**: 対応不可。WASM bridge のスキーマに variations の概念がありません。

**影響**: `--no-xxx` 形式のフラグ反転は実装できません。git の `commit --no-verify` のようなパターンはこのデモでは省略しています。

### implicit_value 非対応

**問題**: `--color` (値省略で "always") のような `implicit_value` が使えません。

**対処**: `--color always` のように常に値の指定を要求します。

**影響**: `git --color` (値なし) は使えず、`git --color always` と書く必要があります。

### post フィルタ非対応

**問題**: パース後のバリデーション (`trim`, `non_empty`, `one_of`, `in_range`) が使えません。

**対処**: TypeScript 側でバリデーション層を実装可能です（今回は省略）。

**影響**: 空文字列や範囲外の値もそのまま受け入れられます。

### dashdash 非対応

**問題**: `--` 以降の引数を個別に取得する `dashdash` / `append_dashdash` が使えません。

**対処**: `rest` で全ての位置引数を一括収集する方式で代用可能です。

**影響**: `--` の前後を区別する厳密な処理は実装できません。ただし `rest` は `--` 以降の引数も含めて全て収集するため、実用上は問題ない場合が多いです。

### _start() は不要

**発見経緯**: コード品質レビューで指摘
**確認結果**: MoonBit が生成する _start (WASM の main 相当) は空関数であり、kuu_parse は _start なしで正常動作する。
**対処**: _start() 呼び出しを削除。

## まとめ

WASM bridge は「スキーマ定義 + パース」のコア機能に特化しています。バリデーション（exclusive, required）やユーザビリティ（require_cmd, implicit_value）の高度な機能はホスト言語（この場合 TypeScript）側で補完する設計思想です。

今回のデモでは制限事項の対処を最小限に留めていますが、本格的なCLIツールを作る場合は TypeScript 側のバリデーション層を充実させることで、ネイティブ kuu API と遜色ない使い勝手を実現できます。
