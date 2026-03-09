# DR-034: greedy/non-greedy による OC/P フェーズ分離の再導入

日付: 2026-03-09
ステータス: **決定** — greedy/non-greedy の区別で OC/P を実現する

## 問題

現在の実装では positional が常に greedy（ExactNode 不在時に即座にフォールバック消費）であるため、OC/P フェーズの区別がない。これにより:

- `--vrrbose`（タイポ）が positional に静かに吸収される
- エラーが原因箇所（`--vrrbose`）ではなく別の箇所で発生する
- `has_prefix("--")` というヒューリスティックで対処していたが、prefix 非依存の設計哲学と矛盾

## 根本原因

**greedy と non-greedy という本質的に異なるものを区別していなかった。**

- ExactNode（option, cmd）は greedy: 引数を見つけたら即座に消費する
- positional は本来 non-greedy: OC 系が全て消費した後の残りを食うべき
- しかし実装では positional も greedy に振る舞っていた（メインループのフォールバックで即消費）

`has_prefix("--")` は「greedy な positional の食欲を prefix で抑える」場当たり的な対処だった。本質は greedy/non-greedy の区別がなかったこと。

## 決定

### greedy = 「いつ食えるか」の宣言

| ハンドラ | greedy | 消費タイミング |
|----------|--------|--------------|
| ExactNode（option, cmd） | 暗黙 greedy | OC フェーズ |
| `--` separator | 明示 greedy | OC フェーズ（内部で positional を serial 消費） |
| positional（デフォルト） | non-greedy | P フェーズのみ |
| positional（greedy 指定） | 明示 greedy | OC フェーズ（ExactNode 不在時） |

### パースフロー: 2フェーズ

```
OC フェーズ（左から右へ）:
  for each arg:
    1. ExactNode 走査 → 最長一致 → consume
    2. ExactNode 全 Reject → greedy positional があれば consume
    3. 何も食わない → skip（unclaimed としてマーク）

P フェーズ:
  unclaimed args を順序保持で収集
  → serial(non-greedy positionals) で前から消費
  → 残りがあれば "unexpected argument" エラー
  → （おまけ）typo hint を error message に付加
```

### positional は serial で消費

positional は本質的に serial(opts) である。現在の実装は `positionals[]` フラットリストに `current_positional` カウンタで暗黙の serial を再実装しているが、これは不自然。

- `serial(file1, rest(dir), file2)` に入力 `F1 D1 D2 F2` → file1=F1, dir=[D1,D2], file2=F2
- 前から順に消費するだけで自然に解決する

### タイポ検出はパースロジックの外

タイポ検出（"did you mean --verbose?"）はパース失敗後のエラーメッセージ改善であり、パースロジックに組み込むべきではない。

- パースは strict に成功 or 失敗
- 失敗した引数を `registered_names` と照合 → 類似候補があれば hint を付加
- パースの正否判定には一切影響しない

## 動作例

### 基本: option と positional の interleave

```
args: [--verbose, F1, --output, out, F2]
定義: flag("verbose"), string_opt("output"), serial(positional("src"), positional("dst"))

OC: --verbose → consumed
    F1 → skip（ExactNode にマッチしない、greedy positional もない）
    --output → consumed（out も値として consumed）
    F2 → skip
unclaimed: [F1, F2]
P: serial(src, dst) → src=F1, dst=F2 ✓
```

### タイポ: 自然にエラーになる

```
args: [--vrrbose, file.txt]
定義: flag("verbose"), serial(positional("file"))

OC: --vrrbose → skip（どの ExactNode にもマッチしない）
    file.txt → skip
unclaimed: [--vrrbose, file.txt]
P: serial(file) → file=--vrrbose, file.txt が残る → "unexpected argument: file.txt"
   → hint: "did you mean --verbose?"

※ positional が1つしかない場合、--vrrbose が positional に入り file.txt がエラーになる。
  タイポ検出としては不完全だが、エラーは出る。完全な検出は hint 層の仕事。
```

### `--` separator: greedy として OC で消費

```
args: [--verbose, --, -f, dest]
定義: flag("verbose"), serial(positional("src"), positional("dst")), dashdash=true

OC: --verbose → consumed
    -- → separator（greedy ExactNode）が発火
      → 内部で positional を serial 消費: src=-f, dst=dest
      → consumed=3 で復帰
unclaimed: なし
P: serial 既に消費済み ✓
```

### greedy positional: OC フェーズで食う

```
args: [F1, --verbose, F2]
定義: flag("verbose"), serial(positional("file", greedy=true))

OC: F1 → ExactNode 全 Reject → greedy positional が consume
    --verbose → ExactNode consumed
    F2 → ExactNode 全 Reject → greedy positional が consume
unclaimed: なし
P: serial 既に消費済み ✓

※ greedy positional は「静かに食う」のではなく「明示的に greedy と宣言して食う」。
```

## 設計原則

> 大事なのは違うものをちゃんと違うと区別できるようにすること。

greedy と non-greedy は本質的に異なる振る舞い。同じ `positionals[]` に区別なく入れていたのが問題の根源だった。区別できれば設計が自然に正しくなる。

## has_prefix("--") が不要になる理由

OC/P フェーズ分離が greedy/non-greedy で自然に実現されるため:

- OC フェーズ: ExactNode のみ。prefix チェック不要（ExactNode は完全一致）
- P フェーズ: unclaimed args を serial 消費。prefix に関知しない
- `--` は greedy ExactNode として OC で処理。prefix の特別扱いではなくノードのマッチング

prefix は ExactNode の name に含まれる実装詳細であり、パースフローの制御には関与しない。

## 実装方針（概要）

1. positional に greedy フラグを追加
2. parse_raw を2フェーズに分割（OC → P）
3. positional のフラットリストを serial ベースに整理
4. エラーメッセージに typo hint を追加（registered_names との類似度照合）

### 注意: positional の配置順序による到達不能

non-greedy positional の後に greedy positional を配置すると、greedy 側が OC フェーズで到達不能になる。OC の greedy 消費は `current_positional` が指す先頭エントリのみを参照するため、先行する non-greedy エントリをスキップしない。non-greedy は P フェーズで消費されるが、greedy は P フェーズでスキップされるため、結果として greedy が一度も消費されない。

greedy positional は non-greedy positional よりも前に配置すること。

## 関連 DR

- DR-007: greedy の初出（Step 7-8）、OC/P 2層構造の明記（Step 10）
- DR-010: 先食い最長一致モデル、force_positional の状態変数化（決定事項 9）
- DR-017: force_positional 廃止、separator_node の ExactNode 化
