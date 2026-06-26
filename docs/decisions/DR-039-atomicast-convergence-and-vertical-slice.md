# DR-039: 合流方針 — AtomicAST = 既存エンジンのシリアライズ形、垂直スライスで共設計

> 由来: kawaz × Claude のリモートセッション議論。トップダウン AST とボトムアップ実装の合流地点を確定。

## 決定

### 合流テーゼ

**AtomicAST = ボトムアップ kuu エンジンのノードグラフを宣言的にシリアライズした形。逆に、既存エンジンは AtomicAST のインタプリタの実体。**

裏付け (コードで確認済み):

- `parse_raw` は `Array[ExactNode]` だけを舐め、`commit : () -> Unit` という型を持たない普遍クロージャで解釈を確定 → AtomicAST の {exact/or/seq/primitive} と bounded path-search (DR-038) で構造同型。
- `make_or_node` = `or`、`serial` = `seq`、`make_value_node` = primitive、`install_eq_split`/`install_short_combine` = `--k=v`/`-abc` の合成ノード。
- `TryResult{Accept(consumed, commit) | Reject | Error}` が DR-037 の Reject/Error を**先取りで実装済み**。
- `make_reducer(pre, accum)` = DR-034 の peaceProcessor + mapper。

### 三層アーキテクチャ (合流後の実装像)

```
1. ノードADT      AtomicAST を MoonBit 再帰 enum で表現
                  葉: primitive(string/number/.../exact) / 枝: or, seq / 属性: multiple / name(=結果スコープ)
2. 評価器         bounded path-search (DR-038)。完全経路の数を数え 0/1/2+ で結末。
                  TryResult/Reject/Error を再利用。
3. 結果ビルダー   name 駆動で結果オブジェクトを自動構築 (DR-025「最も浅い name 層」)。
                  ★ ボトムアップに無い新層。
```

### name 駆動の結果ビルダーは registry ボイラープレートへの別解

ボトムアップは型付き `Opt[T]` ハンドルを握り `opt.get()` で読む (struct-first DX では `set=fn(v){self.x=v}` を毎フィールド書く問題があった)。トップダウンは **name が結果スコープを作り、結果オブジェクトが自動構築され key で読む** → ハンドルも setter クロージャも不要 = **言語非依存版の struct-first DX**。MoonBit の custom derive 待ちだった問題が AST 側の name 駆動で別解になっている。

### 進め方: AtomicAST は単独で仕様確定せず、実装と同時に削り出す (垂直スライス)

AtomicAST はパーサの入力言語そのもので実装と密結合。JSON Schema を先に固めるのは罠。よって walking skeleton で共設計:

1. ノードADT を MoonBit enum で最小定義 (`exact/or/seq/primitive` + `multiple` + `name`)。
2. **bounded path-search 評価器を最初に実装** (DR-038)。← ボトムアップと最も違う = 最初に検証すべき最大リスク。
3. name 駆動の結果ビルダーを足す。
4. 評価器が要求する形に AtomicAST enum を反復。**JSON Schema は最後** (動く enum から導出)。

UsefulAST と registry はトップダウンの設計ドキュメントのまま据え置き、AtomicAST が「トップダウン × ボトムアップ」の合流点としてコードで握られる。

### 起点分岐 (コード着手時に決める)

破壊的変更は許容方針。着手時に「既存 kuu.mbt をリファクタ」か「良い部品 (TryResult/filter/parser) だけ持って新規実装」かを最初に分岐。

## MoonBit 現状の含意

- trait object `&Trait` 有り。**generic trait `trait Foo[T]` と custom derive は未提供**。
- → 存在型ストレージが要る所はクロージャ型消去が依然必要だが、**ノードADT は素直な再帰 enum で表せる**ので、新コアは旧来の型消去ハック (OptRef/Accessor/node_templates) の多くを回避できる可能性が高い。実装時に再評価。

## 関連
- 再設計 DR-015/021/025/026/027/034/037、DR-038 (パース意味論)
- ボトムアップ kuu: `kuu/core/parse.mbt`、`kuu/core/nodes.mbt`、`kuu/core/types.mbt` (TryResult/ExactNode)、[external: kuu.mbt DR-042] (struct-first DX、derive 待ち)
