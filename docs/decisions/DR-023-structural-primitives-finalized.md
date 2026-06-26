# DR-023: 構造プリミティブの確定形 (4プリミティブ + multiple 属性)

## 決定

トップダウン再設計の結果、構造を構成する要素を以下に確定する。

### 構造プリミティブ (4つ)

| プリミティブ | 役割 | 値の伝搬 |
|---|---|---|
| `primitive` (string/number/int/...) | 値の型。引数1個消費 or value literal | 自身の値を親へ |
| `exact` | name の完全一致でトリガ | value あれば literal を親へ、なければ値なし |
| `or` | 子から1つ選択 (排他) | 選ばれた子の値を親へ |
| `serial` | 子を順次消費 | 子の値の配列 (単独要素なら単独) を親へ |

### 値属性 (要素に付く)

| 属性 | 役割 |
|---|---|
| `multiple` | 複数値 (positional の個数 / option の累積)。repeat はここに統合 |
| `value` | literal 値 (持てば exact/primitive が値を発生) |
| `values` | or の選択肢ショートハンド (DR-015) |

### 定義時の糖衣 (1級語彙)

UsefulAST でユーザが書く糖衣。AtomicAST で上記プリミティブへ展開:

| 糖衣 | 展開 |
|---|---|
| `command` | name でトリガ + children をスコープ (exact + or/serial の組) |
| `flag` | boolean + default false + 起動で true セット |
| `count` | number + default 0 + 起動で increment (accumulator) |
| `commands` | `positionals: [{or: [...commands, ...positionals]}]` (DR-018) |
| `option` / `positional` | 配置 (所属配列) で決まる、type 省略可 (DR-018) |
| `help` | 起動時に ParserContext の help フラグセット |

## この構成に至るまで

トップダウン再設計で確定した骨格:

1. command は定義時1級、パース時同型 (DR-017)
2. 配置で区別、commands は or 糖衣 (DR-018)
3. repeat を multiple に統合、4プリミティブ化 (DR-019)
4. 復帰/途中分岐は専用概念を持たずプリミティブで組む (DR-020)
5. 最長一致パース、露出キー一意性は実行時、warn はする (DR-021)
6. キー名 snake_case、case 変換 pluggable (DR-022)

これらにより、前回ボトムアップでは表現できなかった `rm path...` / `mv a b c dst` / `cp src... dst` / 途中分岐 command が、すべて4プリミティブ + multiple + 糖衣で書けるようになった。

## 2層 AST との対応

```
UsefulAST (定義時):  command/option/positional/flag/count/commands を1級で書く
    ↓ 展開 (type 省略の復元・糖衣展開)
AtomicAST (パース時): primitive/exact/or/serial + multiple 属性の同型表現
```

定義時の C (配置主軸・type 省略) と、パース時の同型は、**type の省略/復元**で繋がる (DR-017)。

## 残る作業

- AtomicAST の正規形変換規則の網羅 (CONTEXT.md 論点 A)
- values 展開ルールの正式仕様 (論点 B)
- or の細則: scope を作るか、name 重複 (論点 C) ← DR-021 で実行時検査に整理されたが、定義時の表記は要確定
- これらが固まれば JSON Schema (論点 K)

## 関連

- DR-001 (2層 AST)
- DR-002 (同型)
- DR-015 (値の伝搬)
- DR-017〜022 (本セッションの決定群)
