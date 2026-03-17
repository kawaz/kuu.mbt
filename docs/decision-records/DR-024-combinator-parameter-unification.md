---
type: decision
---

# DR-024: コンビネータパラメータ共通化

options.mbt（892行）の6コンビネータ（flag, string_opt, int_opt, count, append_string, append_int）が
共有する重複パターンを共通ヘルパーに抽出し、Variation enum で否定パターンを汎用化する。

## 決定事項

### 1. Initial[T] -> Lazy[T] リネーム

`Initial[T]` は汎用の ValueThunk であり、名前が用途に縛られすぎていた。
`Lazy[T]` に改名し、`Val(T)` / `Thunk(() -> T)` の構造はそのまま維持。

ユーザー API では `implicit_value~ : T` と `implicit_value_fn~ : () -> T` の
2パラメータ方式も検討するが、まずは `Lazy[T]` での統一を優先。

### 2. default/initial 統合 + consumed=0 廃止

#### 現状の問題

各コンビネータで `default` パラメータから `initial_val` ローカル変数を作り、
`let initial_val = default` としているが、両者が異なったことは一度もない。

さらに implicit_value パスでは `committed: Ref[Bool]` と `make_default_fallback_node`
（consumed=0 で Accept を返すノード）を使って「何もマッチしなかった場合にデフォルトを commit」
する仕組みがあるが、cell は生成時に default で初期化済みのため、この finalize は NO-OP。

#### 決定

- `default` に名前統一（`initial_val` は内部変数として残るが概念は1つ）
- `make_default_fallback_node` を削除
- `committed: Ref[Bool]` を implicit_value パスから削除
- parse.mbt の consumed=0 finalize パスを削除
- composite ノード（make_or_node）から fallback 子ノードを除去
- `is_main` パラメータ（fallback を含めるかの判定）も不要に

#### 根拠

```
cell は生成時に default で初期化済み
→ 何もマッチしない場合、cell は自然に default のまま
→ consumed=0 で改めて default を書き込む必要がない
→ committed Ref も不要（was_set で「何かマッチしたか」は判定可能）
```

reset() シナリオ（`--` separator 等）でも、reset が cell を default に戻すため、
finalize 後も cell = default。consumed=0 はやはり NO-OP。

### 3. Variation enum（DR-014 の2軸分解を置き換え）

DR-014 で設計した negate/prefix_pair の2軸分解を廃止し、
1軸の Variation リストに統合する。

```moonbit
pub(all) enum Variation {
  Toggle(String)    // --{p}-{name}: !current（トグル）。Bool 専用。偶数回で元に戻る
  True(String)      // --{p}-{name}: 常に true（Bool 専用、冪等）
  False(String)     // --{p}-{name}: 常に false（Bool 専用、冪等）
  Reset(String)     // --{p}-{name}: cell=default, was_set=true
  Unset(String)     // --{p}-{name}: cell=default, was_set=false
}
```

全て `--{prefix}-{name}` パターンで、全て flag 的（consumed=1、値引数なし）。

#### 各 Variation の挙動

| Variation | 生成ノード | commit |
|-----------|-----------|--------|
| `Toggle(p)` | `--{p}-{name}` | Bool: !current（トグル）。非Bool: Reset と同等 |
| `True(p)` | `--{p}-{name}` | Bool: 常に true。非Bool: Reset と同等 |
| `False(p)` | `--{p}-{name}` | Bool: 常に false。非Bool: Reset と同等 |
| `Reset(p)` | `--{p}-{name}` | cell = default, was_set = true |
| `Unset(p)` | `--{p}-{name}` | cell = default, was_set = false |

#### デフォルト

全コンビネータで `variations=[]` がデフォルト。理由:
- `--no-` の正しい Variation は default 値次第で変わる（default=true なら False、default=false なら別）
- 自動で生やすと「--no- を付けたくない」場合と区別がつかない
- ユースケースによるので明示指定のみ

#### DR-014 との差異

- 2軸（negate × prefix_pair）→ 1軸（Variation リスト）に簡素化
- 組み合わせの自由度は向上（任意の数の Variation を指定可能）
- Unset を追加（was_set=false でデフォルトソースマージに効く）

### 4. 共通登録ヘルパー

6コンビネータの展開・登録ループを `expand_and_register` に抽出。

```
expand_and_register(name, aliases, shorts, global, was_set, variations,
                    make_main_nodes, make_variation_nodes)

処理:
  for name_variant in [name, ...aliases]:
    register(make_main_nodes("--" + name_variant), wrap=true)
    for v in variations:
      register(make_variation_nodes(name_variant, v), wrap=varies)
  for ch in shorts:
    register(make_main_nodes("-" + ch), wrap=true)
```

**注記**: shorts は String 型（`shorts="vV"` で複数 short 対応）。各文字が独立した `-v`, `-V` ノードとして登録される。

- メインノード: `wrap_node_with_set` で was_set をラップ
- Variation ノード: Unset 以外は wrap、Unset は自前で was_set=false を処理
- OptMeta 構築もヘルパー内に移動可能（検討中）

### 5. Variation enum 再設計: Pair → True/False 分解 + Negate → Toggle リネーム

初回実装で `Pair(String, String)` としていたが、分解して独立させる。
さらに `Negate(String)` を `Toggle(String)` にリネームする。

#### 変更点

- `Pair(String, String)` → `True(String)` + `False(String)` に分解
- `Negate(String)` → `Toggle(String)` にリネーム。セマンティクス（!current）は変更なし

リネーム理由: "Negate" は「false にする」と誤読されやすい。Toggle は !current（反転）の意味が明確。

#### 5つの Variation の正確なセマンティクス

```moonbit
pub(all) enum Variation {
  Toggle(String)    // --{p}-{name}: !current（トグル）。Bool 専用。偶数回で元に戻る
  True(String)      // --{p}-{name}: 常に true（Bool 専用、冪等）
  False(String)     // --{p}-{name}: 常に false（Bool 専用、冪等）
  Reset(String)     // --{p}-{name}: cell=default, was_set=true
  Unset(String)     // --{p}-{name}: cell=default, was_set=false
}
```

#### Main / True / False / Toggle の意味の違い

| 操作 | 動作 | `--x --x` (2回) | default=false 時 | default=true 時 |
|------|------|-----------------|-----------------|----------------|
| **Main** (`--foo`) | `!default` を設定 | 冪等 | cell=true | cell=false |
| **True(p)** | 常に true | 冪等 | cell=true | cell=true |
| **False(p)** | 常に false | 冪等 | cell=false | cell=false |
| **Toggle(p)** | `!current` に反転 | 元に戻る | 1回:true, 2回:false | 1回:false, 2回:true |

重要: Main と True は異なる。`flag(name="foo", default=true)` の場合:
- `--foo` は `!default = false` を設定（メインフラグ = デフォルトからの変更を意味する）
- `--true-foo` は常に true を設定

Toggle はトグルであり「false を設定」ではない。`--toggle-foo --toggle-foo` は偶数回で元に戻る。

#### Sugar パラメータ

variations を直接指定する代わりに、個別の named parameter で指定可能:

```moonbit
p.flag(name="color",
  variation_toggle="no",
  variation_true="enable",
  variation_false="disable",
)
// → variations=[Toggle("no"), True("enable"), False("disable")]
```

解決ロジック: `variations` と `variation_xx` は全て append（合算）。
デフォルトが `[]` なので、指定した分だけ加算される。

```
variations=[]     + variation_toggle="no"                  → [Toggle("no")]
variations=[Reset("reset")] + variation_false="no"         → [Reset("reset"), False("no")]
variations=[]     + variation_toggle="no"
                  + variation_true="enable"
                  + variation_false="disable"              → [Toggle("no"), True("enable"), False("disable")]
```

### 6. default_fn パラメータ

動的デフォルト値のために `default_fn` パラメータを追加。環境変数連携とは独立。

```moonbit
// 日時のデフォルト
p.string_opt(name="since", default_fn=fn() { now().to_string() })

// ランタイム検出
p.string_opt(name="color", default_fn=fn() { detect_color_support() })
```

内部的には `default` と `default_fn` を `Lazy[T]` に統合。両方指定はエラー。

### 7. 名前重複の検証

variation 展開等で同名の ExactNode が生成される場合（例: `name="foo"` + `variation_negate="no"` と
`name="no-foo"` が衝突）、parse() 冒頭で検出してエラーにする。

```moonbit
// parse_raw 冒頭（install_eq_split_node の前）
fn Parser::validate_no_duplicate_names(self) raise ParseError
```

コンビネータ構築時ではなく parse() で検証する理由:
- コンビネータが `raise` を返すと `let port = try! p.int_opt(...)` になり使いにくい
- parse() は既に `raise ParseError` なので自然に混ぜられる
- 全ノード登録済みなのでグローバルに検証可能

### 8. custom コンビネータの位置づけ【実装済み】

int_opt, string_opt 等は `custom[T : Show](name, pre=FilterChain[String, T], ...)` の sugar と整理できる。

**実装**: `custom[T : Show]` として実装完了。Show 制約により、`default_display` が未指定（None）の場合は
`initial_val.to_string()` で自動導出される。string_opt, int_opt は明示的な `default_display` 指定が不要になった。

- `default_display? : String? = None` — None 時は `T.to_string()` で自動導出
- int_opt の「default=0 なら非表示」特殊処理は廃止（0 も表示される）
- int_opt にも post, choices パラメータが追加され、string_opt と同等の機能を提供
- string_opt, int_opt は pre パラメータを固定した custom のシュガー

consumed=1（flag 系）と consumed=2（value 系）の軸が異なるため、
custom は「値を取るオプション」の一般化にあたる。flag/count は custom を経由しない。

## 不採用としたもの

- **default と initial の分離** — 「reset 先」と「未指定時の値」を別概念にする案。
  現実のユースケースが見つからず、consumed=0 の複雑さを正当化できない
- **DR-014 の2軸分解（negate × prefix_pair）** — 直交する2軸の組み合わせより、
  1軸のリストの方がユーザーにとって直感的で表現力も高い
- **consumed=0 finalize の維持** — cell が default で初期化済みのため NO-OP。
  将来の default/initial 分離のために残す案も、YAGNI に反する
- **variations のデフォルトを `[Reset("no")]` とする案** — default 値に応じて正しい variation が
  変わるため（default=true なら False、default=false なら別）、自動で生やすと
  「--no- を付けたくない」場合との区別がつかない。明示指定のみとする
- **Toggle variant の廃止** — 一時的に検討されたが、Toggle(!current) は True/False とは異なる
  セマンティクス（奇偶で変わるトグル vs 冪等な値設定）であり、独立した概念として残す
