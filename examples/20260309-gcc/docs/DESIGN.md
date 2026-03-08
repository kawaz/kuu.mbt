# mygcc Example 設計書

## 概要

gcc のコマンドラインオプション体系を題材に、kuu の **Variation** 機能を集中的に検証するデモプログラム。

## 目的

- kuu の Variation 機能（`variation_false`, `variation_toggle`, explicit `variations` 配列）の実用パターンを示す
- gcc の `-W`/`-Wno-` および `-f`/`-fno-` パターンが Variation で自然に表現できることを実証する
- `default=true` + `variation_false` による「デフォルトON、明示OFF」パターンの検証

## gcc オプションの kuu マッピング

### 命名規則

gcc は `-` プレフィックス（短いオプション）と `--` プレフィックス（長いオプション）を混在させるが、
kuu は `--` プレフィックスを標準とするため、全オプションを `--` スタイルにマッピング。

| gcc | mygcc (kuu) | 備考 |
|---|---|---|
| `-Wall` | `--wall` | variation_false="no" で `--no-wall` 生成 |
| `-Wno-all` | `--no-wall` | 自動生成された variation |
| `-fPIC` | `--fpic` | variation_false="no" で `--no-fpic` 生成 |
| `-fno-PIC` | `--no-fpic` | 自動生成された variation |
| `-O2` | `--optimize 2` | string_opt + choices |
| `-std=c17` | `--std c17` | string_opt + choices |
| `-DFOO=BAR` | `--define FOO=BAR` | append_string |
| `-I/path` | `--include-path /path` | append_string |
| `-o file` | `--output file` | string_opt |

### Variation パターンの分類

| パターン | Variation 種別 | 例 |
|---|---|---|
| デフォルトOFF、`--flag`でON、`--no-flag`でOFF | `False("no")` | `--wall`/`--no-wall` |
| デフォルトON、`--no-flag`でOFF | `default=true` + `False("no")` | `--pie`/`--no-pie` |
| トグル（指定ごとに反転） | `Toggle("toggle")` | `--toggle-diagnostics-color` |
| sugar vs explicit | `variation_false=Some("no")` vs `variations=[False("no")]` | 同等の2形式 |

## オプション構成

### 出力制御 (4個)
- `--output` / `-o` — 出力ファイル名
- `--compile` / `-c` — コンパイルのみ
- `--assemble` / `-S` — アセンブリ出力
- `--preprocess` / `-E` — プリプロセスのみ

### 最適化 (1個)
- `--optimize` / `-O` — 最適化レベル (choices: 0,1,2,3,s,g,fast)

### 警告制御 (8個、全て Variation 付き)
- `--wall`, `--wextra`, `--werror`, `--wpedantic`
- `--wformat`, `--wunused-parameter`, `--wimplicit-fallthrough`, `--wshadow`

### デバッグ (1個、Variation 付き)
- `--debug` / `-g`

### 言語標準 (1個)
- `--std` — 言語標準 (choices: c11, c17, c23, gnu11, ...)

### プリプロセッサ (3個、append_string)
- `--define` / `-D`, `--undefine` / `-U`, `--include-path` / `-I`

### リンカ (5個)
- `--lib` / `-l`, `--lib-path` / `-L`
- `--shared`, `--static` (exclusive)
- `--pie` (default=true, Variation 付き)

### コード生成 (6個、全て Variation 付き)
- `--fpic`, `--fomit-frame-pointer`, `--fexceptions` (default=true)
- `--fcommon`, `--fstack-protector`, `--flto`

### 高度な Variation デモ (1個)
- `--diagnostics-color` (Toggle)

### マシンオプション (4個)
- `--arch`, `--tune`, `--m32`, `--m64` (exclusive)

### その他 (3個)
- `--verbose` / `-v`, `--pipe`, `--language` / `-x`

### 位置引数・特殊
- ソースファイル (rest)
- リンカ引数パススルー (dashdash)

## 制約

| 制約種別 | 対象 |
|---|---|
| exclusive | `--compile` / `--assemble` / `--preprocess` |
| exclusive | `--shared` / `--static` |
| exclusive | `--m32` / `--m64` |

## 合計

- オプション定義: 37個
- うち Variation 付き: 16個
- exclusive 制約: 3組
- shorts 定義: 13個
