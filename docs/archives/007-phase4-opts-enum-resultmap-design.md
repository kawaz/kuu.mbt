# DR-007: Opts enum + ResultMap + immutable Opt 設計（2026-03-01）

## 概要

Phase 4 設計において、ユーザー定義 struct + val() フィールドアクセス方式から、JSON-like な Opts enum + ResultMap + immutable Opt 方式への大幅な設計転換を行った。

## 前提（前セッション 006 時点の設計）

- Opt[T] が `mut value : T` を持ち、parse が直接書き込む
- ユーザー定義 struct（ColorChoice, RgbArgs 等）のフィールドが Opt[U] で、`.val()` + フィールドアクセスでツリーを辿る
- parse がツリーを走査するために子ノードを発見する仕組みが未解決（MoonBit にリフレクションがない）

## 問題点

1. **リフレクション問題** — MoonBit では無名 struct をその場で作って T として渡せず、ユーザー定義 struct のフィールドから Opt[U] を自動発見できない。children() の実装が困難
2. **Opt の mutable 性** — `mut value` を持つと defaults のスナップショットが面倒。グループの clone 時にも状態管理が複雑になる
3. **グループ（Append されるオプション群）** — 同じ構造が複数回出現する場合、個別の変数バインドでは対応できない

## 設計変更の経緯

### Step 1: Opts enum の導入

リフレクション問題の解消として、JSON の Value のような再帰的 enum 構造を採用:

```moonbit
enum Opts {
  Node(&ErasedNode)
  Array(Array[Opts])
  Map(Map[String, Opts])
}
```

- パーサがリフレクション不要でツリーを走査できる
- 名前は Map のキーで管理（フィールドアクセスではなく）

### Step 2: グループの雛形 + clone 方式

グループ（繰り返しオプション群）は:
- 最初に渡された Opts を雛形として保持
- parse がグループ出現ごとに clone して値を詰める
- namedGroup → Map、namelessGroup → Array[Opts] で返す
- 雛形の Opt[T] をレンズ/キーとして、clone 先から型安全に値を取り出す

### Step 3: Opt[T] の immutable 化 + ResultMap

- Opt[T] から `mut value` を削除し、`id : Int` を追加。完全 immutable
- 結果は外部の ResultMap（Map[Int, 型消去された値]）に保持
- Opt[T] の id で ResultMap をルックアップし、T への変換は Opt[T] が知っている
- defaults のスナップショットは ResultMap のコピーで完結
- グループの clone は新 ID 発行で自然に動く

### Step 4: サブコマンド・位置パラメータの具体的表現

- サブコマンド: `opt::cmd(name, children_opts)` kind=Command
  - 同一階層で常に1つに決まる（引数消費ループの仕様）
  - `result.command() -> Opt?` で選ばれたサブコマンドを取得
- グローバルオプション: `meta.global` フラグ。そのスコープ以下全体に伝搬
- 位置パラメータ:
  - `serial(o1, o2, o3)` — 固定長、順番消費
  - `rest(opt)` — 可変長消費
  - `serial(file, rest(path))` — 固定 + 末尾 rest
  - 中間 rest は未サポート（将来検討）

## 決定事項

| 項目 | 決定 |
|---|---|
| ツリー構造 | Opts enum（Node/Array/Map）— JSON-like 再帰構造 |
| Opt の mutability | 完全 immutable。id : Int で一意識別 |
| 結果保持 | ResultMap（外部 Map[Int, 型消去された値]） |
| 値の取得 | result.get(opt) — Opt をレンズ/キーとして使用 |
| グループ | 雛形 + clone（新 ID 発行）。result.get_groups(upstream) -> Array[ResultMap] |
| サブコマンド取得 | result.command() -> Opt? |
| グローバルオプション | meta.global フラグ。スコープ以下に伝搬 |
| 位置パラメータ | serial（固定長）+ rest（可変長）+ 組み合わせ |
| defaults | 後勝ち上書き。ResultMap コピーでスナップショット |

## 不採用とした設計

### ユーザー定義 struct + val() フィールドアクセス方式
不採用理由: MoonBit にリフレクションがなく、struct のフィールドから子 Opt を自動発見できない。children() trait を要求するとユーザーの負担が大きい。

### Opt[T] に mut value を持たせる方式
不採用理由: defaults のスナップショットが複雑（snapshot/restore が必要）。グループの clone 時に状態管理が煩雑。ResultMap で外部化した方がシンプル。

### Map[String, Array[String]] ベースの ParseResult
不採用理由: trait object で heterogeneous collection が可能になった以上、String ベース中間表現は不要。ネームレス Opt の存在で名前キー Map は構造的に破綻。

## 未解決事項

- ResultMap 内部の型消去された値の保持方法（`Map[Int, ???]` の ??? 部分）
- `&ErasedNode` に `store_to(ResultMap)` / `load_from(ResultMap)` 的なメソッドを持たせてクロージャで T を閉じ込める方向

## 付録: 生チャットログ

以下は設計議論の主要なやりとりの記録。

### Opts enum の着想

ユーザー:
> ちなみにMoonbitってJson走査するの考えたらいける気がするけど、こういうの処理できるよね？多分。
> enum Opt { Map(Map[String,Opt]), Array(Array[Opt]), Single(Opt) }
> だとしたら parse(args, Opt) でいけて、構造も何もいじらないでも良いんじゃないかな。ユーザは自分が好きに作った構造からオプション取り出せば良い。

### グループの雛形 + clone

ユーザー:
> 考慮しなきゃいけないのはグループを作るoptだね。これは外で一つの変数にバインドじゃダメでグループ毎のoptのcloneが必要になるのでその参照をどう取らせるか。シンプルに最初に渡されたOptsは雛形として持って、リザルト用はOptsをcloneしてそれに値詰めて返せば良いんかな。namedGroupならMap,namelessGroupならArray(Opts)で返せば良いか。

### 雛形 Opt をレンズとして使う

ユーザー:
> opt[T].as_typed(opt) みたいに自己解決すればよい？

→ 雛形の Opt[T] の meta.name で Map をルックアップし、T への変換も Opt[T] が知っている。

### immutable Opt + ResultMap

ユーザー:
> moonbitって Hash+Eq でキーになるのか。jsみたいにsameでキーになるみたいなやつってないのかな？
> それができるなら Opt は値を持たなくて、opt.value してるところを resultMap.set(opt, v) みたいにして置いて、resultMap.get(opt) で取り出す感じにすると Opt をまた immutable に出来るのでは?

### サブコマンド・位置パラメータ

ユーザー:
> 1 同一階層一つ。というか引数消費ループの仕様からに常に一つになる筈。
> 2 result.command() -> Opt? Noneはトップレベルコマンドの場合とカレントresultがサブコマンド以外の場合
> 3 opt.meta.globalフラグの導入が自然かな。ただしここでは仮にグローバルと言ってるが正確にはそのスコープ以下でのグローバルが正しい。
> 4 位置パラメータは serial(o1,o2,o3)は順番消費、それ以外は単にrest(opt)で単一Optの可変長消費。あとはその組み合わせパターンもあり得るか。mv=serial(rest(file),dir) とか、zip=serial(file,rest(path)) みたいなパターン。中間restは未検討だが論理的には可能なパターンなら可能かもだが大変なので取り敢えず今は未サポートとして考えない。
