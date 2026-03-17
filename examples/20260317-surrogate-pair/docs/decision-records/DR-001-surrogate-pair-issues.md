# DR-001: サロゲートペア問題の調査と分析

## ステータス

調査完了

## 背景

MoonBit の String は UTF-16 内部表現を採用しており、U+10000 以上の文字（Supplementary Plane）はサロゲートペア（2つの UTF-16 コードユニット）で表現される。kuu の short combining 実装がこの特性に対応しているか調査する。

## 発見された問題

### 問題1: short node 収集条件の不一致

**ファイル**: `src/core/parse.mbt:169`

```moonbit
node.name.length() == 2
```

short combining で使用する short node の収集条件が `name.length() == 2` となっている。`length()` は UTF-16 コードユニット数を返すため:

- BMP 文字の short option（例: `-v`）: `"-v".length() == 2` → 収集される
- Supplementary Plane 文字の short option（例: `-😀`）: `"-😀".length() == 3` → 収集されない

**修正案**: `node.name.char_length() == 2` に変更

### 問題2: インデックスアクセスによるサロゲートペア分割

**ファイル**: `src/core/parse.mbt:195-196`

```moonbit
while ri < rest.length() {
  let ch = rest[ri].to_int().unsafe_to_char()
```

`rest[ri]` は UTF-16 コードユニット単位のインデックスアクセスで、サロゲートペアの high/low を個別に取得してしまう。`unsafe_to_char()` で変換すると、不正なコードポイント（0xD800-0xDFFF）が生成される。

さらに、壊れた Char の `to_string()` は **abort** を引き起こし、recover 不能。

**修正案**: `for ch in rest` のイテレータを使用し、位置管理を別途行う

### 問題3: インデックス算術の不整合

**ファイル**: `src/core/parse.mbt:230, 259, 277`

```moonbit
ri += 1
ri = ri + 1 + try_len
```

インデックス `ri` が常に 1 コードユニットずつ進むため、サロゲートペア文字（2 コードユニット）の後の位置計算がずれる。

**修正案**: 各文字の UTF-16 コードユニット数（BMP: 1, Supplementary: 2）を考慮した加算、またはイテレータベースへの全面書き換え

### 問題4: substring 位置のずれ

**ファイル**: `src/core/parse.mbt:210`

```moonbit
let remaining = rest.unsafe_substring(start=ri + 1, end=rest.length())
```

`ri + 1` がサロゲートペアの途中を指す可能性がある。

## 影響範囲

### 影響を受ける機能

- short combining（`-abc` → `-a -b -c` 展開）
  - Supplementary Plane 文字の short option が combining に参加できない
  - BMP 文字と Supplementary Plane 文字の混在 combining が失敗する（abort の可能性あり）

### 影響を受けない機能

- 個別の short option 使用（`-😀` 単体）: ノードマッチングは文字列比較なので正常
- long option: `--emoji` 等は影響なし
- shorts パラメータの登録: `for ch in shorts` イテレータ使用で安全
- `String.to_array()`: Char（コードポイント）配列を返すので安全

## 実用上の影響度

**低〜中**:
- CLI の short option にサロゲートペア文字を使うケースは極めて稀
- 実用的には ASCII 文字（a-z, A-Z, 0-9）がほぼ全て
- ただし `unsafe_to_char()` + `to_string()` の組み合わせが abort を引き起こす点は潜在的な安全性問題
- MoonBit の String が UTF-16 であることを前提としたコードは他にも存在する可能性があり、体系的な確認が必要

## 修正方針

### 最小修正（推奨）

1. `install_short_combine_node` の収集条件を `char_length()` ベースに変更
2. 文字分割ループをイテレータベースに変更
3. 位置管理をコードポイント単位ではなく、イテレータの進行に委ねる
4. `unsafe_to_char()` の使用を排除

### 代替案

- short option を ASCII 文字に制限するバリデーション追加（実用的だが制約が増える）

## 決定

本 PoC で問題を検証・記録。修正は本 PoC のスコープ外とし、別ワークスペースで対応する。
