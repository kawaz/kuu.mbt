# DR-033: lexical スコープ = name が作るスコープ。command に限らない

## 決定

DR-025 で保留した「lexical スコープ」は、結果スコープと同一単位である。name を持つノードがスコープを作る (結果スコープ = lexical スコープ、同一)。command は children を持つから特別なのではなく、name を持つ多くのノードの一つにすぎない。

## ref/link の name 解決

ref/link の name 解決は、現在スコープから外側へ name を持つノードのスコープを順に辿る (レキシカルスコープチェーン)。command に限らず内側のノードもスコープ単位。見つからなければ最後に definitions (DR-032)。

## 例 (kawaz)

color.rgb の中で r/g/b を DRY に定義: rgb の seq 内で r を定義し、g/b は ref:"r" で継承。rgb スコープ内で r が見えるので g/b が r を ref できる。command をまたがず内側スコープで lexical 解決が起きる。

## 関連
- DR-025 (name=結果スコープ。lexical 保留を本 DR で解消)
- DR-032 (ref/link は name 参照)
- DR-006 (lexical scope chain)
