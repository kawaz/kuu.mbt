# DR-001: 2層 AST 構造 (UsefulAST と AtomicAST の分離)

## 決定

引数定義 AST を2層構造で扱う:

```
UsefulAST (人間が書く層、各言語DXコード本体、クロージャあり)
    ↕ export/import (JSON ⇆ コード、クロージャは $required マーカー)
AtomicAST (パーサが直接走る正規形、シリアライズ可能のみ)
```

変換関数 `parseDefinition(UsefulAST) -> AtomicAST` で UsefulAST から AtomicAST に展開する。

## 経緯

最初の議論では「JSON で AST を書く」前提だったが、これだと:
- クロージャ (custom parse, action handler) が表現できない
- 人間にとって書きにくい
- 各言語のイディオムに合わない

kawaz の指摘で気付いた重要な視点:

> UsefulAST は必ず JSON で書く必要はなく、各言語DXで基本1対1みたいな感じで定義出来るのが両側の基本だと思ってる。

つまり **UsefulAST は言語DXコードが本体**で、JSON は交換フォーマット。各言語が自然なイディオムで書ける。

JSON 化時に:
- 関数/クロージャの場所は `$required` マーカーに
- import 時に型付きスタブが生成
- 型エラーが「実装すべき場所」をガイド

## 効果

- 各言語の DX に最適化された書き方ができる
- AST の正規形 (AtomicAST) でツール間ハンドオフが完全に可能
- 同じ意味の引数定義は同じ AtomicAST になり比較可能
- パーサ本体は AtomicAST の最小要素種だけ知っていればよい
- シュガー追加が AtomicAST を変えずに可能 (parseDefinition での展開だけ)

## 関連

- 既存 kuu の Sugar層 / Convention層 / Pattern層 / Core層 / ExactNode に対応
- DR-053 (primitive decomposition) と同じ発想を AST 仕様レベルに引き上げた形
