# DR-002: WASM bridge のコマンドエイリアス未対応

## 問題

cargo CLI では `build` を `b`、`test` を `t`、`doc` を `d` 等のエイリアスで呼び出せる。
しかし kuu WASM bridge のスキーマで `aliases` フィールドを command に指定しても、エイリアス名ではマッチしない。

## 発見経緯

テスト実行時に `parse(["b", "--release"])` が `unexpected argument: b` エラーを返し発覚。
kuu コアでは option の aliases は対応しているが、command の aliases は WASM bridge のスキーマ変換で未実装の可能性がある。

## 解決策

- スキーマ定義に `aliases` は残すが、テストでは正式名のみを使用
- 将来的に kuu コアまたは WASM bridge 側で command aliases がサポートされれば自動的に動作する
- ホスト言語側でのエイリアス解決（args の前処理）も可能だが、今回のデモでは行わない

## 影響

- cargo の短縮コマンド（b, t, r, c, d）が使えない
- 実用的な CLI ツールではホスト側での前処理が必要
