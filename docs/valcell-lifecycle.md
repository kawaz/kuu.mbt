# ValCell / Accessor ライフサイクル設計

## 1. 概要図

```
  ┌─────────────────────────────────────────────────────┐
  │ ValCell[T]                                          │
  │  cell : Ref[T]           ← 値の実体                 │
  │  committed : Ref[Bool]   ← ユーザー入力で確定されたか │
  │  default_val : Lazy[T]   ← リセット時の初期値        │
  └───────────┬─────────────────────────────────────────┘
              │ .accessor()
              ▼
  ┌─────────────────────────────────────────────────────┐
  │ Accessor[T]  （ValCell へのクロージャ束）              │
  │  get()       : () -> T       cell.val を返す         │
  │  set(v)      : (T) -> Unit   set_value + set_commit  │
  │  set_value(v): (T) -> Unit   cell=v のみ             │
  │  set_commit(): () -> Unit    committed=true のみ     │
  │  reset()     : () -> Unit    cell=default, committed=false │
  └───────────┬─────────────────────────────────────────┘
              │ Opt に格納
              ▼
  ┌─────────────────────────────────────────────────────┐
  │ Opt[T]                                              │
  │  id       : Int          ← NodeTemplate 参照キー     │
  │  name     : String       ← "--verbose" 等           │
  │  accessor : Accessor[T]  ← 値の読み書きインターフェース │
  │  used     : () -> Bool   ← この Opt 名が使われたか    │
  │  parsed   : Ref[Bool]    ← Parser.parsed を共有      │
  └─────────────────────────────────────────────────────┘
        │                        │
        │ .get()                 │ .is_set()
        ▼                        ▼
   parsed=true なら            (self.used)() を
   Some(accessor.get())        そのまま返す
   parsed=false なら None
```

### Accessor 共有パターン

```
  alias の場合:
  ┌──────────────┐     ┌──────────────┐
  │ target       │     │ alias        │
  │ Opt[T]       │     │ Opt[T]       │
  │ used ← committed│  │ used ← opt_used│ ← 独立
  └────┬─────────┘     └────┬─────────┘
       │                    │
       ▼                    ▼
  ┌──────────┐         ┌──────────┐
  │Accessor A│─── 共有 ─│Accessor A│  ← 同一 Accessor を直接共有
  │ get      │         │ get      │
  │ set      │         │ set      │
  │ set_value│         │ set_value│
  │ set_commit│        │ set_commit│
  │ reset    │         │ reset    │
  └──────────┘         └──────────┘
       │
       ▼
  ┌──────────┐
  │ValCell[T]│  ← 1つの cell を共有
  └──────────┘

  clone の場合:
  ┌──────────┐     ┌──────────┐
  │ target   │     │ clone    │
  │ Opt[T]   │     │ Opt[T]   │
  └────┬─────┘     └────┬─────┘
       │                │
       ▼                ▼
  ┌──────────┐     ┌──────────┐
  │Accessor A│     │Accessor B│  ← 完全独立
  └────┬─────┘     └────┬─────┘
       ▼                ▼
  ┌──────────┐     ┌──────────┐
  │ValCell   │     │clone_cell│  ← 独立した cell
  └──────────┘     └──────────┘
```

## 2. 命名規則

### committed vs opt_used

| 名前 | スコープ | 意味 |
|---|---|---|
| `ValCell.committed` | 値レベル | この値がユーザー入力で commit されたか（どの名前経由でも） |
| `opt_used` (alias/clone 内ローカル) | Opt レベル | この特定の Opt 名がコマンドラインで使われたか |

### Opt.used の実装

| Opt の種類 | `used` の実装 | 説明 |
|---|---|---|
| 通常 Opt | `fn() { vc.committed.val }` | committed と同値 |
| alias Opt | `fn() { opt_used.val }` | 独立した使用フラグ |
| clone Opt | `fn() { opt_used.val }` | 独立した使用フラグ |

`Opt::is_set()` は `(self.used)()` を返す。`as_ref()` で `OptRef` を取ると `is_set` は `Opt.used` をキャプチャする。alias の `OptRef` は alias 固有の `opt_used` を返し、target の `committed` ではない。exclusive/required 制約で alias の `OptRef` を使う場合、alias 名でのみ `is_set=true` になることに注意。

サブコマンド構造では、子が committed なら親も必ず committed（再帰パースの構造的不変条件）。

### Accessor メソッドの対称性

- `set(v)` = `set_value(v)` + `set_commit()`
- `set_value(v)`: value のみセット、committed 非更新
- `set_commit()`: committed のみセット、value 非更新
- `reset()`: value も committed もリセット

## 3. パーサのライフサイクルフェーズ

### Phase 1: コンビネータ登録

ユーザーが `p.flag()`, `p.string()`, `p.custom()` 等を呼ぶフェーズ。

**何が起きるか:**

1. `ValCell::new(default)` で `cell`, `committed`, `default_val` を初期化
2. コンビネータごとに `make_main_node` クロージャを構築（`cell` と `pending` をキャプチャ）
3. `register_option` で:
   - `wrap_node_with_set` が ExactNode の commit に `committed = true` を注入
   - variation ノードを展開・登録
   - `node_templates[id]` に `make_node` ファクトリを保存（alias/clone 用）
   - `valcell.accessor()` で Accessor を生成し `Opt[T]` に格納
4. `Opt[T]` をユーザーに返す

**ValCell の状態:** `cell = default`, `committed = false`

### Phase 2: コンポジション構築

ユーザーが `alias`, `clone`, `adjust`, `link`, `deprecated` を呼ぶフェーズ。

| コンビネータ | Accessor 関係 | 主な操作 |
|---|---|---|
| alias | target.accessor を直接共有。used は独立した opt_used | commit 時に `set_commit()` で target まで伝搬 |
| clone | 完全独立 ValCell | save/restore パターンで target の cell を一時利用 |
| adjust | target の Accessor を `post_hooks` でキャプチャ | `is_set` チェック → `set_value` で値変換 |
| link | source/target 両方の Accessor をキャプチャ | `source.is_set` チェック → `set_value`/`set` で値転送 |
| deprecated | alias + post_hook | `is_set` チェック → `deprecated_usages` に記録 |

**ValCell の状態:** 変化なし（Phase 1 と同じ）

### Phase 3: パース実行 — OC フェーズ

`Parser::parse_raw` 内の Option/Command フェーズ。全 ExactNode に対して最長一致を試みる。

**1ラウンドの流れ:**

```
for node in nodes:
  result = node.try_reduce(args, pos)   ← 副作用は pending のみ
      ↓
最長一致の commit() を実行              ← cell に値を書き込み
      ↓
敗者の node は次ラウンドで
新しい位置から再び try_reduce           ← 前回の pending は上書きされる
```

#### try_reduce の詳細

投機的操作。cell や committed には一切触らない。pending のみ更新する。

全ノードに対して呼ばれるが、最長一致の1つだけが commit される。敗者の pending は放置され、次の try_reduce で上書きされる。

#### commit の詳細

勝者のみ実行。ここで初めて cell と committed が変化する。

**通常ノード:**
- `cell = pending`, `committed = true`（`wrap_node_with_set` 経由、consumed > 0 のみ）

**alias ノード:**
- `cell = pending`（target の cell）, `opt_used = true`, `set_commit()`（root まで伝搬）

**clone ノード:**
- save/restore パターン（target 退避 → commit → clone にコピー → target 復元）

#### reset の詳細

OC 競合敗者のリセット。

**通常:**
- `cell = default`, `pending = initial`, `committed = false`

**alias:**
- `cell = default`（target の cell）, `opt_used = false`（target の committed は reset しない）

**pending の役割:**

try_reduce は投機的に複数ノードが呼ばれるため、cell に直接書き込むと敗者の副作用が残る。pending に一旦書き込み、勝者の commit でのみ cell に反映する。

### Phase 4: パース実行 — P フェーズ

OC フェーズで消費されなかった引数（unclaimed + `--` 以降の force_unclaimed）を positional に割り当てる。

**何が起きるか:**

- `positional`: handler 内で `pending.val = args[pos]`、commit で `cell.val = pending.val` + `committed = true`
- `rest`: commit で `cell.val.push(value)` + `committed = true`
- `dashdash`: OC フェーズで消費済み（セパレータ + 後続引数をまとめて consumed）

### Phase 5: パース実行 — post_hooks フェーズ

OC + P フェーズ完了後、`post_hooks` を順に実行する。

| hook 種別 | is_set チェック | cell 操作 | committed 操作 |
|---|---|---|---|
| adjust | target.is_set → true の場合のみ | `set_value(transform(get()))` | 変更なし |
| link | source.is_set → true の場合のみ | `set_value(source.get())` or `set(source.get())` | propagate_set=true なら true |
| deprecated | alias.is_set → true の場合のみ | なし | なし |
| exclusive | 各 OptRef.is_set をチェック | なし | なし |
| required | OptRef.is_set → false なら Error | なし | なし |
| at_least_one | 全 OptRef.is_set → false なら Error | なし | なし |
| post (custom) | 無条件 | `cell.val = filter(cell.val)` | 変更なし |

**最後に `self.parsed.val = true` が設定され、`Opt::get()` が `Some` を返すようになる。**

### Phase 6: ユーザーアクセス

パース完了後のアプリケーションコード。

```moonbit
// get(): parsed=true なら Some(accessor.get()) を返す
let verbose = opt_verbose.get()  // Some(true) or Some(false)

// is_set(): used をそのまま返す（parsed 非依存）
let explicitly_set = opt_verbose.is_set()  // true: ユーザーが指定した

// as_ref(): 制約登録用の OptRef を返す（is_set は Opt.used にバインド）
let ref = opt_verbose.as_ref()  // OptRef { name, is_set }
```

**get と is_set の意味の違い:**

- `get()` は「パース済みか」のガード（`parsed` チェック）。パース前は常に `None`
- `is_set()` は「ユーザーが明示的に指定したか」（`Opt.used` 経由）。default で値があっても `is_set = false`

## 4. Accessor メソッド一覧表

| メソッド | cell への影響 | committed への影響 | 主な使用タイミング | 主な呼び出し元 |
|---|---|---|---|---|
| `get()` | なし（読み取り） | なし | Phase 5-6 | `Opt::get`, adjust, link, clone の save/restore |
| `set(v)` | `cell = v` | `true` | Phase 5 | link (propagate_set=true), clone の Accessor |
| `set_value(v)` | `cell = v` | 変更なし | Phase 5 | adjust, link (propagate_set=false), clone の save/restore |
| `set_commit()` | なし | `true` | Phase 3 | alias の commit（target の committed を連鎖更新） |
| `reset()` | `cell = default` | `false` | Phase 3 | ExactNode.reset（OC 競合敗者のリセット） |

> **注:** `is_set` は Accessor ではなく `Opt.used` で管理される（DR-048）。

### set と set_value の使い分け

- **`set`**: 「ユーザーが指定した」のと同等の意味を持たせたい場合。link の propagate_set=true
- **`set_value`**: 値だけ変えたいが「ユーザーが指定した」フラグは変えたくない場合。adjust, link のデフォルト

### set_commit の存在理由

alias の commit では、alias 自体の `opt_used = true` に加えて target の `committed = true` も必要。しかし alias は target の cell を共有しているため、`set` を呼ぶと二重書き込みになる。`set_commit` は committed のみを更新する。

alias は target の Accessor を直接共有するため、`set_commit` は常に root（元の ValCell）の `committed` を更新する。チェーン alias（alias の alias）でも `set_commit` 経由で root まで伝搬する。

## 5. コンビネータ別 ValCell 使用パターン

### flag

```
ValCell[Bool] + pending: Ref[Bool]

try_reduce: pending = !initial_val        ← 投機（副作用は pending のみ）
commit:     cell = pending                ← 確定
reset:      cell = initial_val, pending = initial_val
```

- `wrap_node_with_set` で commit 時に `committed = true`
- variation ノードは `vc.cell` と `vc.committed` を直接操作（pending 不使用）

### count

```
ValCell[Int] + pending: Ref[Int]

try_reduce: pending = pending + 1         ← 投機（累積）
commit:     cell = pending                ← 確定
reset:      cell = 0, pending = 0
```

- 複数回の try_reduce で pending が累積。最後に勝った commit で cell に反映
- `wrap_node_with_set` で commit 時に `committed = true`

### custom (string / int)

```
ValCell[T] + pending: Ref[T]

try_reduce: pending = pre.run(raw_string) ← 投機（フィルタ適用）
commit:     cell = pending                ← 確定
reset:      cell = initial_val
```

- `implicit_value` 付きの場合は or_node（soft_value + implicit_flag）構成
- `post` フィルタは post_hooks として登録（Phase 5 で無条件適用）

### custom_append (append_string / append_int)

```
ValCell[Array[T]]  ← Thunk(fn() { [] }) で初期化

try_reduce: (副作用なし)
commit:     cell.push(pre.run(raw_string))  ← 直接 push
reset:      cell = []
```

- pending 不使用。commit で直接 Array に push
- `Thunk` により reset のたびに新しい空配列を生成

### positional

```
ValCell[String] + pending: Ref[String]

handler:  pending = args[pos]             ← 投機
commit:   cell = pending, committed = true  ← 確定
```

- P フェーズで実行。greedy=true の場合のみ OC フェーズでも消費される

### rest

```
ValCell[Array[String]]  ← Thunk(fn() { [] }) で初期化

handler:  (副作用なし)
commit:   cell.push(value), committed = true  ← 直接 push
```

- 複数回 commit が呼ばれ、1引数ずつ push される

### dashdash / append_dashdash

```
ValCell[Array[String]] or ValCell[Array[Array[String]]]  ← Thunk で初期化

try_reduce: セパレータ以降の引数を収集（副作用なし）
commit:     cell に push, committed = true
reset:      cell = [], committed = false
```

- OC フェーズで消費。セパレータ + 後続引数をまとめて consumed
- `wrap_node_with_set` を使わず、commit 内で直接 `committed = true`

### cmd

```
ValCell[CmdResult?]  ← Val(None) で初期化

try_reduce: 子パーサで再帰的に parse（成功時のみ Accept）
commit:     cell = Some(CmdResult), committed = true
reset:      cell = None, committed = false
            子パーサの parsed/current_positional もリセット
```

- `Accessor` は手動構築（`ValCell::accessor()` 不使用）
  - `get` は `None` の場合に空の CmdResult を返す（安全アクセス）
- `Opt[T]` の `parsed` は子パーサの `parsed` を共有（親ではない）
  - `cmd_opt.get()` は子パーサの parse 完了で `Some` を返す

## 6. alias vs clone の Accessor 共有パターン

### alias

```moonbit
let verbose = p.flag(name="verbose")
let v = p.alias("-v", verbose)
```

**構造:**

- `v` の Accessor は `verbose` の Accessor を直接共有（同一インスタンス）
- `get`, `set`, `set_value`, `set_commit`, `reset` は全て共有 → 同じ `cell` を操作
- `used` のみ独立（`opt_used`）、Accessor は完全共有

**commit 時の動作:**

1. 元ノードの `commit()` → `cell` に値を書き込み
2. `opt_used = true`
3. `target_acc.set_commit()` → target の `committed = true`

**チェーン alias での伝搬:**

```moonbit
let a = p.flag(name="aaa")       // ValCell.committed = X
let b = p.alias("--bbb", a)      // opt_used = Y, set_commit → X = true
let c = p.alias("--ccc", b)      // opt_used = Z, set_commit → Y = true ... ?
```

`c` の commit で `b.accessor.set_commit()` が呼ばれる。`b` の Accessor は `a` の Accessor を直接共有しているため、`set_commit` は `a` の ValCell の `committed` を操作する。そのため `c` の commit は `a` の `committed` を直接 true にする。

ただし `b` 自身の `opt_used` は更新されない。これは `set_commit` が root の `committed` を操作するためで、中間 alias の `opt_used` には伝搬しない。

**is_set の意味:**

- `a.is_set()` → `a` 自身または alias 経由で値が設定されたか（root の committed）
- `b.is_set()` → `b` という名前で指定されたか（alias 固有の opt_used）

### clone

```moonbit
let verbose = p.flag(name="verbose")
let v = p.clone("-v", verbose)
```

**構造:**

- 独立した `clone_cell` + `opt_used` を持つ
- Accessor は完全に独立（target と共有するものはない）

**commit 時の save/restore パターン:**

1. `saved = target_acc.get()` — target の現在値を退避
2. 元ノードの `commit()` — target の cell に値を書き込み（ノードのクロージャが target の cell をキャプチャしているため）
3. `clone_cell = target_acc.get()` — 書き込まれた値を clone にコピー
4. `opt_used = true`（clone 専用の使用フラグ。root への伝搬はしない）
5. `target_acc.set_value(saved)` — target を元に戻す

この方式は、ノードの `commit` が常に target の cell に書き込む前提で動作する。clone は独自の cell を持つが、ノードの振る舞いは target のものを再利用するため、一時的に target を経由する。

### 比較表

| 特性 | alias | clone |
|---|---|---|
| cell | 共有 | 独立 |
| committed | 独立（opt_used） + root 伝搬 | 独立（opt_used）、root 伝搬なし |
| 値の独立性 | なし（同じ値） | あり（別の値） |
| ノードファクトリ | 共有 | 共有（save/restore でラップ） |
| `--name=value` 対応 | eq_fallback 登録 | eq_fallback を save/restore でラップ |
| global 伝搬 | target が global なら伝搬 | target が global なら伝搬 |

## 7. 制限事項

### mutable T (Array) での reset の制限

`Array` 等の mutable 型を `Val(initial_val)` で初期化すると、reset 時に同じインスタンスを再利用してしまう。これにより前回の値が残る可能性がある。

**緩和策:** `Lazy::Thunk` を使う。

```moonbit
// 良い: reset のたびに新しい空配列を生成
ValCell::new(Thunk(fn() { [] }))

// 悪い: 同じ配列インスタンスを再利用してしまう
ValCell::new(Val([]))
```

`custom_append`, `rest`, `dashdash`, `append_dashdash` は全て `Thunk` を使用している。ただしコンビネータ内で `reset` を個別に `fn() { cell.val = [] }` と定義している場合、`default_val.resolve()` ではなく直接空配列を生成しているケースもある。

### clone の save/restore と append 型

clone の save/restore パターンは「commit 前に target を保存 → commit 後に clone にコピー → target を復元」という流れ。append 型（`custom_append` 等）では commit が `cell.push(v)` を行うため:

1. saved = target の Array（参照コピー）
2. commit → saved と同じ Array に push
3. clone_cell = target.get()（= saved と同一参照）
4. target を saved で復元 → clone_cell と同一参照

この場合 clone と target が同じ Array インスタンスを共有してしまう可能性がある。append 型の clone は実用上注意が必要。

### clone の alias の制限

`alias(name, clone_opt)` は `clone_opt.id` の NodeTemplate を使って新ノードを生成する。このノードの commit は target（clone 元）の cell に書き込む。save/restore ラップは clone 側にのみ適用されるため、alias 経由では clone の独立 cell ではなく target の cell に書き込まれる。

**回避策:**

- target に先に alias してから clone する
- clone のさらなる clone を使う
