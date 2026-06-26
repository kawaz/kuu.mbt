# DR-006: スコープは自動、lexical scope chain で ref/link 解決

## 決定

children (options / positionals) を持つ要素は **自動的にスコープを作る**。明示フラグは不要。

ref/link の解決は lexical scope chain:
1. `id` で global 検索
2. 自分の中の name
3. 兄弟の name
4. 親の name
5. 親の親の name
6. ... ルートまで

`name` は **スコープ内 (options + positionals すべて) で重複禁止**。

## 経緯

最初 Claude は or がスコープを作るか曖昧に書いていた。kawaz の整理:

> スコープを作るかどうかはまず暗黙では作らないのでは?スコープを作る事を明示するフィールドとかかな？
> いや違うか。基本的にorはスコープ作って側ないのかな。レキシカルスコープなら子（options,positionals,commands）を持つ度にスコープを作っても祖先方向に探索するから特に意識不要か。

つまり「スコープを作る/作らない」を明示する必要がなく、children を持つだけで自然にスコープが出来る。lexical scope chain なので祖先方向に探索すれば、暗黙でも事故にならない。

「精々がパフォーマンスを詰めようとした時に作らないがあっても良いが気にする必要は基本ない」

## name 重複ルール

kawaz の指摘:
> name重複はセクション間でもひつようではないかな？

options に `name: "config"` があって、positionals にも `name: "config"` があると:
- ref/link 解決が曖昧
- 結果オブジェクトのキー衝突

なので **同じ scope 内 (options + positionals 含む) で重複禁止**。

## 効果

- スコープを作るかどうかを意識せず書ける
- ref/link が予測可能に解決される
- name 重複による事故が防げる

## 関連

- DR-003 (name の3軸)
- DR-007 (definitions 領域)
