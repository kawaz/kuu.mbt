# Phase 4 初期設計議論（アーカイブ）

この文書は Phase 4 の初期段階の設計議論の記録です。
その後の検証・議論で設計が大幅に発展したため、アーカイブに移動しました。
最新の設計は `docs/DESIGN.md` を参照してください。

主な変更点:
- reducer シグネチャ: `(T, String?) -> T` → `(ReduceContext, ReduceAction) -> Array[String]`
- MoonBit の trait object (`&Trait`) サポートが確認され、heterogeneous collection が可能に
- ReduceContext による戦略判断の完全なカプセル化

---

# Phase 4: API 再設計 — コンビネータ + Reducer パターン

### 9. 背景・動機

Phase 1-3 は PoC（概念実証）として要件の実現可能性を検証した。OptKind enum ベースの設計は要件検証には十分だったが、以下の課題が浮上した:

- ParsedValue が全て String ベース（Flag/Count 以外）で、ユーザーが結果取得時に型変換を行う必要がある
- "Parse, don't validate" の原則に反する二度手間が発生している
- OptKind の各バリアントが独立しており、合成や拡張に制約がある

Phase 4 では、コンビネータ合成と Reducer パターンを軸に API を再設計する方向性を模索する。

---

### 10. 型付きアクセサ Opt[T] の導出

#### 10.1 heterogeneous container 問題

ParsedValue にジェネリクスを適用する最初の発想（`ParsedValue[T]`）は、`Map[String, ParsedValue[???]]` で異なる `T` を混在できないという問題に直面する。MoonBit には mapped types、マクロ、trait object、Any 型がなく、型レベルでの自動導出は不可能。

#### 10.2 Opt[T] — 型付きアクセサ（レンズ）

解決策として、`Opt[T]` を「値を保持しない型付きアクセサ」として設計する方向性が見えた:

- 内部の `ParseResult` は String ベースのまま維持する
- `Opt[T]` は取り出し時に parser を適用して `T` に変換する
- `Opt[T]` 自体は immutable で値を保持しない — 定義情報と変換ロジックのみ

```moonbit
// Opt[T] は値を保持しない。定義情報 + 変換関数のみ
struct Opt[T] {
  initial : T
  reducer : (T, String?) -> T  // raise ParseError
  // + メタ情報
}

// 使用時: ParseResult から型付きで取り出す
let port : Int = result.get(port_opt)
let verbose : Bool = result.get(verbose_opt)
```

Design rationale: 内部を String ベースに保つことで、apply_defaults の多段畳み込み等の既存設計と整合性を維持しつつ、ユーザー向け API では型安全なアクセスを提供する二層構造となる。MoonBit の型システム制約下で heterogeneous container 問題を回避する現実的なアプローチ。

---

### 11. コンビネータ合成による OptKind の置換

OptKind enum を廃止し、プリミティブ + コンビネータで合成する設計が可能であることが見えた。

#### 11.1 プリミティブ

```moonbit
// 基本型
opt::int(long="port")              // Opt[Int]
opt::string(long="name")           // Opt[String]
opt::bool(long="verbose")          // Opt[Bool]
opt::path(long="config")           // Opt[Path]
opt::regex(long="pattern")         // Opt[Regex]

// カスタム型
opt::custom(parser=(s) -> MyType::parse(s))  // Opt[MyType]
```

#### 11.2 合成コンビネータ

```moonbit
// 蓄積
opt::append(opt::string)           // Opt[Array[String]]

// 固定長複数値
opt::tuple(opt::string, opt::int)  // Opt[(String, Int)]
opt::append(opt::tuple(opt::int, opt::int, opt::int))
                                   // Opt[Array[(Int, Int, Int)]]

// 選択（先頭トークンで区別）
opt::or(rgb, css_color_string)     // Opt[Color]
```

#### 11.3 tuple の内部表現

~~内部的には tuple2（cons cell / HList 相当）のみで任意長を表現する:~~

~~`1個: tuple(int, nil)` / `2個: tuple(int, tuple(string, nil))` / `3個: tuple(int, tuple(int, tuple(int, nil)))`~~

**→ 左畳み込みに変更:**

内部的には `tuple(pre, cur)` の 2 引数のみで任意長を表現する:

```
1個: tuple(tuple(none, o1))                         -- tuple(none, o) で single 相当
2個: tuple(tuple(none, o1), o2)
3個: tuple(tuple(tuple(none, o1), o2), o3)
```

Design rationale: 右畳み込み（cons cell）から左畳み込みに変更した理由:
- パースはトークンを左から右に消費する
- 左畳み込みなら消費順と構造が一致し、パース中に逐次的に結果を積み上げられる
- 右畳み込みだと末端まで展開してから戻る形になり不自然

これにより内部表現は `tuple(pre, cur)` の 2 引数だけで任意長を表現。`tuple(none, o)` で single も統一。

ユーザー API は `tuple2` / `tuple3` / `tuple4` / `tuple5` を提供し、平坦な型 `(A, B, C)` を返す。内部 1 種類 + 表面 N 種類の責務分離。

#### 11.4 or コンビネータ

`or(rgb, css_color_string)` は複数パーサの試行。値を受けるオプションの数が固定であるという制約のもとで、先頭トークンでの部分マッチングに曖昧さがなければ許容される方向。

---

### 12. 核心: Reducer パターンによる OptKind 完全統一

parser のシグネチャを `(pre: T, cur: String?) -> T` にすることで、全 OptKind が統一的に表現できることがわかった。

```moonbit
struct Opt[T] {
  initial : T
  reducer : (T, String?) -> T  // raise ParseError
  // + メタ情報 (long, short, env, help, required, inversion, visibility, completion_hint, ...)
}
```

#### 12.1 各 OptKind の Reducer 表現

| 現 OptKind | initial | reducer | cur の役割 |
|------------|---------|---------|-----------|
| Flag | `false` | `(_, None) -> true` | None（値なし） |
| Count | `0` | `(n, None) -> n + 1` | None（値なし） |
| Single(Int) | `None` | `(_, Some(s)) -> Some(parse_int(s))` | Some（次トークン） |
| Append(String) | `[]` | `(arr, Some(s)) -> [...arr, s]` | Some（次トークン） |
| OptionalValue | `None` | 値あり: `(_, Some(s)) -> Some(s)`, 値なし: `(_, None) -> Some(implicit)` | Some or None |

`cur: String?` で値を取らない Flag/Count（`None`）と値を取る Single/Append（`Some`）を統一的に扱える。

#### 12.2 プリミティブは custom の特殊化

`opt::int` は `opt::custom(parse_int)` のシンタックスシュガーとなる。全ての組み込み parser は `custom` の特殊化であり、特別扱いする必要がない。

Design rationale: reducer パターンは畳み込み（fold）の一般化であり、Phase 1-3 の apply_defaults と同じ思想を個々のオプション値レベルに適用したもの。全 OptKind を単一のインターフェースで表現できるため、パーサコアの分岐が消え、新しい値パターンの追加がコンビネータの追加だけで完結する。

---

### 13. 各言語ライブラリの型変換方式調査

#### 13.1 比較表

| ライブラリ | 型変換方式 | バリデーション | 補完候補 |
|-----------|-----------|-------------|---------|
| clap (Rust) | ValueParser trait | value_parser! マクロ | ValueHint enum |
| bpaf (Rust) | FromStr + .parse() コンビネータ | .guard(fn, msg) | .complete() |
| cobra (Go) | 型別メソッド IntVar/StringVar | Args バリデータ関数 | ValidArgsFunction コールバック |
| kong (Go) | struct タグ + MapperFunc | enum タグ | Completer interface |
| click (Python) | ParamType クラス (INT/FLOAT/Path/Choice) | callback 引数 | shell_complete() メソッド |
| swift-argument-parser | ExpressibleByArgument protocol | transform クロージャ | CompletionKind enum |
| yargs (JS) | .number()/.boolean() | .check() コールバック | completion コマンド |
| optparse-applicative (Haskell) | ReadM monad | ReadM 内で検証 | bashCompleter/completeWith |

#### 13.2 設計パターン分類

- **パターン A（型システム）**: clap, swift-argument-parser, typer — trait / protocol / 型アノテーションで変換を駆動
- **パターン B（コールバック/関数）**: click, yargs, cobra — 関数やコールバックで明示的に変換
- **パターン C（文字列+後処理）**: argparse, commander — パース結果は文字列、ユーザーが後で変換
- **パターン D（コンビネータ）**: bpaf, optparse-applicative — パーサ自体を合成・変換する

本設計は **A+D のハイブリッド**（trait で型変換 + コンビネータで合成 + reducer で統一）の方向性。MoonBit の trait を型変換の拡張ポイントとし、コンビネータで合成、reducer で全パターンを統一する。

---

### 14. メタ情報の分離

#### 14.1 reducer で表現できるもの

- 型変換（String → T）
- choices バリデーション
- or（複数パーサの試行）
- tuple（固定長複数値）

#### 14.2 reducer 外のメタ情報

以下は reducer のロジックではなく、パーサの振る舞いや表示に関わる定義情報として `Opt[T]` のフィールドに残る:

- `long`, `short`, `aliases` — 名前解決
- `env` — 環境変数フォールバック
- `required` — 必須制約
- `inversion` — `--no-xxx` 等の反転フラグ生成
- `help`, `visibility` — ヘルプ/補完での表示制御
- `completion_hint` — 補完候補の種別（File / Dir / Custom 等）
- `value_name` — ヘルプ表示用のプレースホルダ（例: "PORT", "PATH"）

---

### 15. MoonBit 型システムの制約と設計判断

#### 15.1 調査結果

| 機能 | MoonBit での状況 |
|-----|----------------|
| ジェネリクス | あり（HKT なし） |
| trait | あり（associated types なし） |
| derive | あり（カスタム derive 不可） |
| マクロ | なし |
| mapped types / conditional types | なし |
| trait object / Any | なし |
| heterogeneous collections | 不可 |

#### 15.2 制約から導かれる設計方針

「定義 struct から結果 struct を自動導出」は不可能。したがって:

- **外部表現**: `Opt[T]` 型付きアクセサでユーザーに型安全なインターフェースを提供
- **内部表現**: `OptDef`（型消去済み）→ `CmdDef` → `parse()` → `ParseResult`（String ベース）
- **接続**: `Opt[T].get(result)` で reducer を適用し `T` を返す

この二層構造が MoonBit の型システム制約下での現実的な落としどころとなる。

---

### 16. 設計の全体像

```
[ユーザー API]
  opt::int, opt::string, opt::bool, opt::path, opt::custom
  opt::append, opt::tuple2/3/4/5, opt::or
  opt::flag, opt::count
  Opt[T] { initial, reducer, meta }

[メタ情報]
  long, short, aliases, env, required, inversion
  help, visibility, value_name, completion_hint

[内部表現]
  OptDef (型消去済み) → CmdDef → parse() → ParseResult (String ベース)

[取り出し]
  Opt[T].get(result) → reducer 適用 → T
```

Design rationale: ユーザーは `Opt[T]` を通じて型安全な定義と取得を行い、内部では型消去された `OptDef` / `ParseResult` でパーサコアのロジックを単純に保つ。Phase 1-3 の `ParsedValue` enum + `get_flag` / `get_string` アクセサの延長線上にあるが、型変換の責務を定義側（`Opt[T]` の `reducer`）に移すことで、アクセサの型ごとの分岐を不要にする。

---

### 17. 未解決課題

1. **Group のコンビネータ表現** → **解決** — Group は子スコープ + positional を持つ特殊なオプション。reducer パターンにどう統合するか検討が必要

   **回答:** コンビネータ合成 + append + メタフラグで表現できる:

   ```
   namedGroup("upstream",
     path("path", required=true),
     int("timeout"),
     namedGroup("socket",
       path("path", required=true),
       rest("filters", string)
     )
   )
   ```

   - `namedGroup` は実質的に `append` の特殊化
   - グループ化は meta 側に group フラグを持てば表現可能
   - append の中身がコンビネータ合成 Opt で表現可能なら、名前付き (namedGroup) と名前なし (append) の区別も reducer で統一的に表現できる可能性がある

   namedGroup の挙動:
   - 出現するたびに新しいスコープを開く
   - 値あり (WithValue 相当): `namedGroup("upstream", ...)` → `--upstream u1` で "u1" をキーにスコープ開始
   - 値なし (Valueless 相当): namedGroup の名前だけでスコープ開始
   - 子要素は合成 Opt で定義、スコープ内でパースされる
   - 同じ値のインスタンスが再出現したらマージ（reducer の pre に前回結果が渡される）

2. **inversion の reducer 統合** → **解決** — `--no-xxx` 時に reducer に何を渡すか。`pre` をリセットして `initial` に戻す方式、別の reducer を呼ぶ方式、あるいは reducer の第3引数として `inverted: Bool` を渡す方式が考えられる

   **回答:** reducer の pre を initial にリセットするだけ。

   `--no-upstream` が出現したら:
   1. 該当 Opt の値を `initial` に戻す
   2. reducer は呼ばない（値消費なし）

   これは inversion 用の特別な処理ではなく、「pre を initial にリセット」という汎用操作。メタ情報として `inversion: FlagInversion?` を持ち、`--no-xxx` トークンを検出したら initial リセットを発動する。

3. **tuple の or での曖昧さ判定** → **解決** — 先頭トークンだけで判定可能かの静的チェックアルゴリズム。曖昧な場合のエラー報告も含む

   **回答:** 貪欲マッチ + 段階的絞り込みアルゴリズム:

   各 or 候補を 1 トークン目から順に試行する:

   1. 全候補 NG → パースエラー（引数が足りないか要件に合う引数ではない）
   2. 1 個だけ OK、他 NG → OK（確定）
   3. 2 個以上 OK → n+1 個目の opt で絞り込み:
      - 全候補の n+1 個目の opt が全て無し → パースエラー（曖昧です）
      - tuple の最後まで OK が 1 つだけ → OK（確定）
      - tuple の最後まで OK が複数 → パースエラー（曖昧です）

   つまり各トークンを消費するたびに候補を絞り込み、一意に確定するか最後まで曖昧なままかを判定する。

4. **completion hint の設計** → **方式確定、詳細設計は後日** — ValueHint enum 的なものと custom コールバックの統合。reducer からは補完候補を導出できないため、メタ情報として明示的に指定する必要がある

   **方式決定:**
   - 静的ソース出力（bash/zsh/fish スクリプト生成）は採用しない
   - **自己コマンドのセルフ呼び出しによる動的ヒント方式を確定**
     - コマンド自身が `--completion` 等の隠しオプションで呼ばれた際に、現在のカーソル位置と入力済みトークンを受け取り、補完候補を動的に返す
     - shell の completion 設定はコマンド自身を呼び出す薄いラッパーのみ
   - 詳細設計（プロトコル、出力形式、shell 連携の具体）は後日

5. **ヘルプ生成** → **未解決** — reducer パターンからヘルプテキストをどう生成するか。型名、可能な値、デフォルト値の表示には reducer 外のメタ情報が必要

6. **PoC（Phase 1-3）からの移行パス** → **解決: 全削除 + 完全作り直し** — 既存の OptKind ベース実装をどう段階的にリプレースするか。Opt[T] ラッパーを被せて段階的に移行する方式が有力

   **回答:** 移行不要。Phase 1-3 の PoC 実装は全削除して完全作り直し。

   方針:
   - PoC コードは `jj split` でコミット切り出し、bookmark またはタグで残しておく（しばらく振り返れるように）
   - 新設計はゼロから実装
   - まだ誰も使っていない PoC なので捨てて構わない
   - PoC は無駄ではなく、新設計の礎として役立った

   **テストケースは漏れなく再利用する:**
   - 要件定義の具現化であるテストケース集こそが宝物
   - 詳細なエッジケースを網羅したテストケースがあるからこそ、大きな設計判断（全削除＋作り直し）ができる
   - テストケースの期待値は新 API に合わせて書き換えるが、テストしている「要件・エッジケース」自体は全て引き継ぐ

---

### 18. 大統一: Command / Option / Positional の Reducer 統一

Phase 4 の議論の中で、reducer パターンがオプションだけでなく、サブコマンドと位置パラメータまで統一的に表現できる可能性が見えた。

#### 洞察

サブコマンド、オプション、位置パラメータは全て「トークンを消費して結果を積み上げる」という同じ構造を持つ:

| 種別 | マッチ条件 | long の意味 | reducer |
|------|----------|-----------|---------|
| Command | 名前でマッチ | サブコマンド名 (`serve`) | 子スコープの結果を返す |
| Option | `--long` でマッチ | オプション名 (`port`) | 値を変換・蓄積 |
| Positional | 位置でマッチ | プレースホルダ名 (`FILE`) | 値を変換・蓄積 |

meta に `kind: Command | Option | Positional` を持たせれば、全てを同じ reducer パターンで定義できる。

#### long フィールドの文脈依存的な意味

`long` フィールドは kind によって意味が変わる:
- `Option`: `--long` のオプション名 → コマンドラインで `--port 8080` と指定
- `Positional`: プレースホルダ名 → ヘルプ表示で `<FILE>` と表示
- `Command`: サブコマンド名 → コマンドラインで `serve` と指定

#### 位置パラメータとオプション引数のプレースホルダ統一

RGB の例:
```
--color int("R") int("G") int("B")
```
ヘルプ表示: `--color <R> <G> <B>`

ここで `"R"`, `"G"`, `"B"` は位置パラメータのプレースホルダ名。オプションの引数（tuple で合成された子要素）も位置パラメータと同じパターンで表現される。

つまり `int("R")` は:
- kind: Positional
- long: "R"（プレースホルダ名）
- reducer: `(_, Some(s)) -> parse_int(s)`

#### 設計の全体像（更新）

```
Opt[T] {
  initial : T
  reducer : (T, String?) -> T raise ParseError
  meta : Meta {
    kind : Kind          // Command | Option | Positional
    long : String        // 名前 or プレースホルダ
    short : ...          // Option のみ
    env : ...            // Option のみ
    help : String
    ...
  }
}
```

全ての定義が Opt[T] の合成で表現される:
- `opt::command("serve", children=[...])` → Command 種別の Opt
- `opt::int(long="port")` → Option 種別の Opt
- `opt::positional("FILE", opt::path)` → Positional 種別の Opt
- `opt::tuple(int("R"), int("G"), int("B"))` → 内部的に Positional の合成

これにより CmdDef / OptDef / PositionalDef の3つの型が Opt[T] の1つに統一される可能性がある。

#### 注意

この大統一はまだ構想段階。実装上の課題:
- Command の reducer は子スコープ全体を処理する必要があり、単純な `(T, String?) -> T` に収まるか要検討
- パーサのトークン消費ロジックが kind によって異なる（Option は `--` プレフィックスでマッチ、Command は名前でマッチ、Positional は位置でマッチ）
- ヘルプ生成時の kind による表示分け
