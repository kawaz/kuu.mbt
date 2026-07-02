# DR-043: repeat と multiple の分離 — 閉包は構造、畳みは値パイプライン

> 由来: 本セッションの議論 (findings F-020 / F-021 の前段)。DR-019 の「repeat を multiple に統合」を部分的に覆し、DR-034 が宣言した「個数制約は別軸として分離」に受け皿を与える。

## 決定

### 2 概念の分離

- **repeat (構造閉包)**: 「同じ要素を複数回」という反復構造。`repeat: {min, max}` / `repeat: true` (無制限)。主戦場は positional 文脈だが「構造が書ける場所ならどこでも」書ける (greedy 内部の可変長値スロット、opts 群の反復 等)。min / max は閉包のパラメータであり、**path-search の枝生成に効く構造制約** (事後検証ではない): `cp src... dst` は src の取り分ごとの枝のうち完全経路が 1 本に絞れることで解ける (DR-038 の創発)。
- **multiple (値の畳み)**: option の複数回発火や separator 分割片が生む値列を畳む DR-034 のパイプライン (separator / mapper / collector)。**出現回数・出現位置の制約は持たない** (回数は repeat、位置の自由は greedy の軸)。

両者の共有部品は値パイプラインだけ: repeat が生む値列にも option 再発火の値列にも、同じ accumulator (DR-036) が使える。

### どちらも installer (基本属性から降格)

positional / options で互いに使えない語彙を全要素共通の基本属性として持つ座りの悪さは、installer 所有語彙 (DR-042) にすることで解消する:

- **repeat installer**: `repeat` 属性を回収し、**ref を使った再帰リスト構造に lowering する**:

  ```json
  {"name": "file", "type": "string", "repeat": {"min": 1}}
  ```

  →

  ```json
  {"name": "file", "seq": [{"type": "string"}, {"ref": "file", "optional": true}]}
  ```

  ([T, T[]] の cons 構造。3 引数なら [T,[T,[T]]] と unfold される)。min は必須段の unroll、max は unroll 段数の上限、上限なしは再帰尾部で表現する。平坦化 ([T,[T,…]] → T[]) の accumulator を同時にインストールする。ゼロ進捗ガード (再帰 1 周で 1 トークン以上消費すること) は静的検査で保証する。unfold は現在の背骨に留まる (DR-041 §4) ため、反復間の greedy 割り込み (`cp src... --verbose dst`) は保たれる。

  repeat の対象要素は形を問わない (DR-042)。inline 型だけでなく **ref 要素にもそのまま付く**:

  ```json
  {"name": "hlcolors", "ref": "color", "repeat": {"min": 1}}
  ```

  →

  ```json
  {"name": "hlcolors", "seq": [{"ref": "color"}, {"ref": "hlcolors", "optional": true}]}
  ```

  (`color` を `[r,g,b] | colorname` のような構造テンプレとして export: false で定義し bg / fg から ref する使い方の延長)。head の消費は ref 先の構造が担うため、ゼロ進捗ガードは「ref 先が 1 トークン以上消費すること」の検査に帰着する。

- **multiple installer**: `multiple` 属性を回収し、要素の値セルに accumulator / pipeline (DR-034 / DR-036) を構成する (env と同型の、席・能力宣言型の installer)。

これにより **AtomicAST コアから閉包プリミティブが消える**: 構造は exact / or / seq / primitive + ref/link (+ greedy マーク) で閉じ、反復は再帰 (DR-020「再帰はプリミティブで組む」) に、畳みは registry に、それぞれ帰着する。

### required との関係

repeat の min は閉包の反復回数 (CLI トークン消費の構造) であり、required (committed であること、値源 DR-031 込みの充足) とは別概念として立てる。両者は重ならない。

## 採用しなかった案

### min/max を multiple のサブフィールドに戻す (DR-019 原型)

「option の複数回起動」と「positional の反復個数」が別概念であることは DR-034 の経緯で判明済み。1 フィールドに再同居させると「min/max が option 文脈で無意味」という罠が戻り、同名 1 語が発生 (何回) と畳み (どう積む) の両義を再び呼び込む。

### top-level 属性 (min_count / max_count)

repeat しない要素に付いても意味を成さず、required の隣に文脈限定の属性が散らばる。

### 閉包プリミティブの維持 (multiple ノードを AtomicAST コアに残す)

再帰 + ref で表現可能 (DR-020) であり、コアの要素数を増やす理由がない。評価器は再帰 1 本を扱えばよい。

## DR-019 との関係

DR-019 の「repeat を独立**構造要素**にしない (要素属性で表す)」は引き続き有効。「repeat と multiple を multiple 一本に統合する」は本 DR で覆す (DR-019 に Superseded 注記)。

## 検証 (垂直スライス第 2 弾へ)

- ref 再帰 lowering の枝生成と `cp src... dst` の取り分一意性
- repeat 反復間の greedy 割り込み (unfold が背骨に留まること)
- 平坦化 accumulator と name 駆動 result builder の噛み合わせ
- multiple × repeat の併用 (`prog a,b c,d` — separator 分割と反復の合成)

## 関連

- DR-019 (統合の判断 — 部分的に Superseded)
- DR-034 (パイプライン 4 要素 — 共有部品として存続) / DR-036 (accumulators / multiple registry)
- DR-020 (再帰はプリミティブで組む — repeat lowering の根拠)
- DR-038 (取り分の一意性) / DR-041 (背骨・先食い) / DR-042 (installer アーキテクチャ)
- findings `2026-06-29-ast-missing-pieces.md` F-020 / F-021
