# Phase 4 設計議論ログ（2026-02-27）

Phase 4 の API 再設計に至った議論の流れを生のまま記録。
設計書（`../phase4-design.md`）だけでは失われがちな思考プロセスと意図を保存する目的。

## 議論の流れ

### heterogeneous container 問題から Opt[T] へ
- ParsedValue にジェネリクスを適用する最初の発想（ParsedValue[T]）は、Map[String, ParsedValue[???]] で異なる T を混在できない問題に直面
- Ref[T] パターン（struct Ref[T] { mut val : T }）と同じ構造で Opt[T] を設計
- Opt[T] は値を保持せず、parser を持つ型付きアクセサとして設計

### 書き込み不要の洞察
- 当初は Opt[T] に値を書き込む設計（on_parsed コールバック）を検討
- 「書き込む必要はあるの？parser を常に必要とするなら？」というユーザーの指摘
- → Opt[T] は immutable、ParseResult から get 時に parser 適用する方式に

### コンビネータ合成の着想
- opt::int, opt::string 等のプリミティブ
- opt::append, opt::tuple, opt::or の合成
- bpaf に近い設計パターン

### tuple の内部表現
- 可変長引数をどう表現するか
- cons cell（右畳み込み）vs 左畳み込みの議論
- パースがトークンを左→右に消費するので左畳み込みが自然
- 内部は tuple(pre, cur) の2引数だけ、ユーザーAPIは tuple2/3/4/5

### Reducer パターンの発見（核心）
- 「int の中身は custom(parse_int) か？」
- 「(pre: T, cur: String) -> T じゃなくて (pre: T, cur: String?) -> T なら Flag も Count も集約できるのでは？」
- → initial + reducer で全 OptKind を統一

### 大統一: Command / Option / Positional
- サブコマンドの消費も reducer で表現可能
- 位置パラメータも同様
- meta に kind: Command | Option | Positional を持てば全定義が Opt[T] に統一
- long フィールドが kind によって文脈依存的に意味が変わる（オプション名 / プレースホルダ名 / サブコマンド名）

### Group の表現
- namedGroup + append + メタフラグで表現
- namedGroup は append の特殊化

### --no-xxx パターン
- reducer の pre を initial にリセットするだけ

### or の曖昧さ判定
- 貪欲マッチ + 段階的絞り込みアルゴリズム
- 各トークン消費ごとに候補を絞り込み

### PoC からの移行方針
- 全削除 + 完全作り直し
- テストケース（要件の具現化）は漏れなく再利用
- 「テストケースこそ宝物、コードは捨てて構わない」

### completion
- 静的ソース出力なし
- セルフ呼び出しによる動的ヒント方式を確定
