---
type: decision
---

# DR-0061: コンビネータの合成的分解設計

## 背景

DR-0037 で設計された adjust の 6 パラメータ（before/after × pre/post/accum）が DR-0044 で「v1 は after_post のみ」に縮小され、その結果 `append_string`, `append_int`, `append_float`, `append_dashdash`, `custom_append`（現 `append`）が独立実装として増殖した。

本 DR は元の設計思想に立ち返り、コンビネータの合成的分解の全体像を記録する。

## 設計

### レイヤモデル

他言語では「各言語 DX → 各言語低レイヤ API → FFI → MoonBit Core」となるが、MoonBit は全部 MoonBit なので FFI 境界がない。同じ 3 レイヤ構造:

```
MoonBit DX (@dx)
  register, struct-first, Parseable 等。DX の一つの姿（他の書き方の DX もあり得る）
  ↓
MoonBit 低レイヤ API
  option, long, short, dashdash, append, split, concat...
  ちょっと便利なコンビネータ集
  ↓
MoonBit Core
  string/int/bool（value descriptor）, clone/link/adjust, or, serial, exact, rest, sub_parser...
  純粋関数、最小プリミティブ
```

パッケージ構成: 内部で core と低レイヤ API を分離しつつ、`@kuu` = `@core` + `@低レイヤAPI` を re-export。ユーザーは `@kuu` だけ使えば両方見える。`@dx` は別パッケージ。

**重要**: core は直接ユーザーが触るものではない。超バラバラのプリミティブを手書きするのは苦行だが、core を直接使う想定はない。DX 層が上手く束ねる。全部 MoonBit だから境界が見えにくいが、他言語なら FFI の向こう側にある部分。

### 各レイヤの詳細

#### Core: 最小プリミティブ

**`value(initial~=Lazy[T]?)`** — 真のプリミティブ。pre も post も accum も何もない、ただの値の入れ物。

**Value Descriptor** — value に pre を付けただけ。pre は型変換であり同時にマッチ条件（pre 成功=マッチ、失敗=リジェクト）。

```
value()    : Opt[T]        (pre=None, post=None — 裸のプリミティブ)
string()   : Opt[String]   = adjust(value(), pre=identity)     — 何でもマッチ
int()      : Opt[Int]      = adjust(value(), pre=parse_int)    — int パース可能ならマッチ
bool()     : Opt[Bool]     = adjust(value(), pre=parse_bool)   — bool パース可能ならマッチ
number()   : Opt[Number]   = adjust(value(), pre=parse_number)
```

value descriptor はポジショナルとして引数を消費できる。配置の文脈（long option? positional? 何番目?）は serial, or, exact 等の別コンビネータが与える。

注意: value descriptor の定義は Core（value + adjust(pre=...)）だが、ユーザーへの提供は低レイヤ API として string/int/bool/number の名前で行う。

**合成プリミティブ**:

| プリミティブ | 役割 |
|---|---|
| `exact(str, greedy?)` | リテラル文字列マッチ。値を持たず引数を消費するだけ（`Opt[Unit]` 的）。option や flag では value descriptor とセットで使われることで「オプション」に見える |
| `serial([...])` | スコープ（グループ）を作り、子を順に処理 |
| `or([...])` | 複数の候補から最初にマッチするものを選択 |
| `simple(t, ...params)` | `Object.assign(clone(t), ...params)` — clone して params を上書き |
| `adjust(t, before_pre?, after_pre?, before_post?, after_post?, ...)` | pre/post の 4 挿入点は確定。accum の 2 挿入点はペンディング（§ accum フェーズ参照） |
| `clone`, `link` | 値の複製・連携。**値を増やさない** — 既存の値の振る舞いを変えるだけ |

#### 低レイヤ API: 便利なコンビネータ集

Core プリミティブの合成で作られるシュガー。他言語なら FFI の向こう側に相当。

| コンビネータ | 合成元 |
|---|---|
| `option(name, shorts, variations, t)` | `or(long(t), short(t))` — 高階シュガー |
| `long(t)` | variation ごとの exact + = 分割を or で束ねる |
| `short(t)` | Parser の short レジストリに登録 |
| `flag(name, ...)` | `option(name, bool(initial=false))` + adjust で直接 true セット。「値を消費しない」のは flag の特性ではなく option 展開時の設定 |
| `count(name, ...)` | `option(name, int(initial=0))` + adjust でインクリメント |
| `dashdash(sep)` | `serial([exact(sep, greedy=true), rest(string())])` |
| `append(t)` | `Opt[T]` → `Opt[Array[T]]`。parallel 上に構築（内部構造セクション参照） |
| `split(t, sep)` | `Opt[T]` → `Opt[Array[T]]`。pre でセパレータ分割（split は pre の責務） |
| `concat(t)` | `Opt[Array[T]]` の複数回指定時に配列を結合。命名は merge だと意味が広すぎるため concat を採用 |
| `rest(t)` | parallel 上に構築。t を連続マッチ試行し、マッチする限り配列に蓄積 |
| `positional(nth, t)` | n 番目の引数として t を配置 |

### option() の分解（低レイヤ API）

`option()` は大量のプリミティブを組み合わせる高階コンビネータ。

```
option(t) = or(long(t), short(t))
```

#### greedy と option の関係

greedy は option のための仕組み。option がなければ全部 positional で 1 フェーズで回る。option を先に拾う必要があるから greedy フェーズが存在する。long も short も greedy。

dashdash が greedy なのは option の greedy に対する対抗策。`--` 以降を option に食われないようにするため。

#### long(t)

variation ごとのマッチを or で束ねる。greedy=true。

```
long(t) = or(greedy=true, [
  serial(exact("--{name}"), t),                           // --name value
  simple(t, pre=eq_split("--{name}=")),                   // --name=value（prefix 除去した clone）
  serial(exact("--{variation1}{name}"), adjust(t, ...)),  // e.g. --no-name (toggle)
  serial(exact("--{variation2}{name}"), adjust(t, ...)),  // e.g. --reset-name
  ...
])
```

各 variation は adjust で値の変換を付ける（toggle, false, reset 等）。`=` 形式は `simple(t, pre=...)` — t を clone して pre を差し替えただけ。

#### short(t)

option は **short を Parser の short レジストリに登録する**。greedy=true。

```
short(t) = register_short("f", t)  // greedy
```

short combining（`-abc` → `-a -b -c` の分解）は個々の option の責務ではない。Parser レベルで全登録済み short を横断的に集め、sub_parse で処理する別の仕組み。

### 合成例

```
option(name="verbose", flag())                              // Opt[Bool]
option(name="count",   int())                               // Opt[Int]
option(name="tag",     append(string()))                    // Opt[Array[String]]
option(name="fields",  concat(split(string(), sep=",")))    // Opt[Array[String]]
option(name="number",  concat(split(number(), sep=",")))    // Opt[Array[Number]]
```

`append` と `concat(split(...))` は結果の型が同じ `Opt[Array[T]]` でも構造が違う:

- **append**: 各出現で 1 要素追加。`--tag v1 --tag v2` → `["v1", "v2"]`
- **concat(split(...))**: 各出現で分割結果を結合。`--fields a,b --fields c` → `["a", "b", "c"]`

variation 付きの例:

```
option(
  name="number",
  variation_reset="no",    // --no-number で initial=[] にリセット
  concat(split(number(), sep=","))
)
// → Opt[Array[Number]]
```

### append と rest の内部構造

append と rest は `Opt[Array[T]]` を作る機能を共有する。仮に `parallel` と呼ぶ:

```
parallel(Opt[T]) -> Opt[Array[T]]:
  1. Opt[Array[T]] を作る（配列の入れ物）
  2. Opt[T] がマッチするたびに accessor を deep clone
  3. clone 上で pre → post チェーンが走る
  4. clone の getter から値を取り出し → Opt[Array[T]] に push
  5. 元の accessor はテンプレートとして汚れない
```

append と rest はこの parallel の上に構築される:

```
append(t): parallel(t) + t がどこでマッチしても都度 push
rest(t):   parallel(t) + t を連続マッチ試行、マッチする限り push、失敗で停止
```

accessor の clone タイミング（before_pre? before_post?）は実装時に詰める。初期値の扱いなどの都合で変わり得るが、最悪 pre の最初で clone して、マッチ失敗なら捨てるだけなので実害はない。

### accum フェーズの位置づけ（ペンディング）

DR-0037 では pre/post/accum の 3 フェーズとしたが、append の実態は after_post + 外部配列への push であり、独立した accum フェーズなしで実装できる可能性がある。

ただし他のユースケースで accum が必要になる可能性を排除できないため、accum フェーズの削除はペンディング。実装を進めながら判断する。

### dashdash の分解

dashdash はプリミティブではなく、合成のシュガー:

```
dashdash("--") = serial([
  exact("--", greedy=true),
  rest(string()),
])
```

- `serial` がスコープ（グループ）を作る
- `exact("--", greedy=true)` が greedy フェーズでマッチしてスコープを起動
- `rest(string())` がスコープ内で残りを全収集
- greedy は exact（または serial）に付く。rest の収集方法ではなくスコープの起動タイミングの制御
- dashdash が greedy なのは option の greedy に対する対抗策（`--` 以降を option に食われないため）

`append(dashdash(...))` → `Opt[Array[Array[String]]]` — 各 `--` グループが配列の要素。

### adjust（DR-0037 元設計 + 再検討）

コンビネータのパースパイプラインは 2〜3 フェーズ:

```
raw_string → [pre] → typed_value → [post] → validated_value → [accum?] → stored_value
```

DR-0037 の元設計では 3 フェーズ × before/after の 6 パラメータ:

```
adjust(target,
  before_pre?,  after_pre?,
  before_post?, after_post?,
  before_accum?, after_accum?,
)
```

- **pre**: 型変換（String → T）であり同時にマッチ条件。split もここ
- **post**: バリデーション・加工（T → T）。choices, in_range 等
- **accum**: 蓄積戦略 — **ペンディング**。append/rest は after_post + 外部配列 push で実装可能であり、独立フェーズとして必要か未確定。他のユースケースで必要になる可能性を排除できないため削除はしない

現在の実装は after_post のみ。少なくとも pre/post の 4 パラメータは実装すべき。accum は実装しながら判断。

### group は特別な概念ではない

`serial` がスコープを作り、`append` が繰り返しを作る。この2つを入れ子にすれば任意の深さのグループが表現できる。特別な "group" コンビネータは不要。

例: `--upstream path --socket sock filter...` の入れ子構造:

```
append(
  serial(
    exact('--upstream'),
    simple(name="upstream", string()),
    append(
      serial(
        exact('--socket'),
        simple(name="socket", string()),
        rest(name="filters", string()),
      )
    )
  )
)
```

入力: `--upstream p1 --socket s1 f1 f2 --socket s2 f3 --upstream p2 --socket s3`

結果:
```
[
  { upstream: "p1", socket: [{ socket: "s1", filters: ["f1", "f2"] }, { socket: "s2", filters: ["f3"] }] },
  { upstream: "p2", socket: [{ socket: "s3", filters: [] }] },
]
```

serial = スコープ、append = 繰り返し。入れ子にすれば入れ子のグループ。

### 標準 vs ユーザーランド

レイヤごとの提供物:

| レイヤ | 提供物 | 例 |
|---|---|---|
| Core: 値のプリミティブ | `value(initial~=Lazy[T]?)` | 唯一の真の値の入れ物 |
| Core: 合成プリミティブ | `exact`, `serial`, `or`, `simple` | マッチングの構造 |
| Core: エフェクトプリミティブ | `clone`, `link`, `adjust` | 振る舞い変更。値を増やさない |
| Core: 配列化プリミティブ | `parallel(Opt[T]) -> Opt[Array[T]]` (仮名、ユーザー非公開。命名は実装時に決定) | append/rest の共通基盤 |
| 低レイヤ API: Value Descriptor | `string`, `int`, `bool`, `number` | `adjust(value(), pre=...)` |
| 低レイヤ API: コンビネータ | `option`, `flag`, `count`, `dashdash`, `append`, `rest`, `split`, `concat`, `positional` | プリミティブの合成 |
| DX | `register`, `struct-first`, `Parseable` 等 | ユーザー向け高級 API |

antenna-cli の `+`/`-`/`...` マージのようなドメイン固有ロジックはユーザーランド。adjust のフック + カスタムロジックで実現できる。標準機能にする必要はない。

## 現状との差分

### 不要になるもの

adjust の完全実装と合成モデルにより、以下の独立実装が不要になる:

| 現状 | 合成表現 |
|---|---|
| `custom_append[T]`（リネーム済み: `append[T]`） | `append(custom[T](...))` |
| `append_string` | `append(string(...))` |
| `append_int` | `append(int(...))` |
| `append_float` | `append(float(...))` |
| `append_dashdash` | `append(dashdash(...))` |
| `dashdash`（独自実装） | `serial([exact("--", greedy=true), rest(string())])` |

### 経緯と教訓

| DR | 内容 |
|---|---|
| DR-0037 | adjust 6 パラメータの元設計 |
| DR-0044 | 「v1 は after_post のみ」に縮小 — **設計の勝手な変更** |
| DR-0045 | after_post のまま Accessor 統合 |
| DR-0053 | プリミティブ分解の構想（append[T] 列挙あり） |
| DR-0060 | example レビューで append 系独立実装の問題が顕在化 |
| DR-0061 | 本 DR。元設計に立ち返り合成モデルを明文化 |

**因果関係**: DR-0044 で adjust が after_post のみに縮小された結果、蓄積戦略の変更（append）を adjust で表現できなくなり、`custom_append`（現 `append`）, `append_string`, `append_int`, `append_float`, `append_dashdash` が独立実装として増殖した。元の 6 パラメータ設計が実装されていればこれらは全て不要だった。

**後日注記**: `custom_append` は `append` にリネームされた。合成モデルにおける `append(custom[T](...))` との名前衝突は、合成モデルが将来の設計構想であり現在の API ではないため問題ない。

**教訓**: ユーザーが設計した構想を「v1 ではこれだけ」「ユースケース出現時に追加」等の理由で AI が勝手にスコープ縮小してはならない。
