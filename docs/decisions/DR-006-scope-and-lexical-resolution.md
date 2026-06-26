# DR-006: スコープは自動、lexical scope chain で ref/link 解決

## 決定

ref/link の解決は lexical scope chain:
1. `id` で global 検索
2. 自分の中の name
3. 兄弟の name
4. 親の name
5. 親の親の name
6. ... ルートまで

`name` は **スコープ内 (options + positionals すべて) で重複禁止**。

スコープを作るのは **name を持つノード** (DR-025 / DR-033 で確定)。

## 経緯

スコープを作るかどうかを明示フラグで持つ必要はない。lexical scope chain なので祖先方向に探索すれば、暗黙でスコープが出来ても事故にならない。

## name 重複ルール

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
- DR-025 (name を持つノードがスコープを作る)
- DR-033 (lexical = name scope の整理)

## Superseded (歴史)

> **更新: DR-025 により本 DR の「スコープ単位」が「children を持つ要素」から「name を持つノード」に変更。DR-033 で lexical scope = name scope と整理。本 DR の lexical chain 探索順序・name 重複禁止ルールは引き続き有効。**

### children を持つ要素がスコープを作る (DR-025 で更新)

当初の決定本文では:

> children (options / positionals) を持つ要素は **自動的にスコープを作る**。明示フラグは不要。

としていたが、DR-025 で **「name を持つノードがスコープを作る」** に訂正された。DR-033 で lexical scope = name scope と整理。

当時の経緯メモ (kawaz):

> スコープを作るかどうかはまず暗黙では作らないのでは?スコープを作る事を明示するフィールドとかかな？
> いや違うか。基本的にorはスコープ作って側ないのかな。レキシカルスコープなら子（options,positionals,commands）を持つ度にスコープを作っても祖先方向に探索するから特に意識不要か。

> 精々がパフォーマンスを詰めようとした時に作らないがあっても良いが気にする必要は基本ない

children 説でも lexical chain なら事故にならないという観察自体は正しかったが、スコープ単位を name に揃えるほうが設計上クリーンと判断され DR-025 で更新された。
