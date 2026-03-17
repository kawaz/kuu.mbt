# ValCell / Accessor ライフサイクル設計

## 1. 概要図

```
  ┌─────────────────────────────────────────────────────┐
  │ ValCell[T]                                          │
  │  cell : Ref[T]         ← 値の実体                   │
  │  was_set : Ref[Bool]   ← ユーザーが明示的に指定したか │
  │  default_val : Lazy[T] ← リセット時の初期値          │
  └───────────┬─────────────────────────────────────────┘
              │ .accessor()
              ▼
  ┌─────────────────────────────────────────────────────┐
  │ Accessor[T]  （ValCell へのクロージャ束）              │
  │  get()       : () -> T       cell.val を返す         │
  │  set(v)      : (T) -> Unit   cell=v, was_set=true   │
  │  set_quiet(v): (T) -> Unit   cell=v のみ             │
  │  is_set()    : () -> Bool    was_set を返す           │
  │  mark_set()  : () -> Unit    was_set=true のみ       │
  │  reset()     : () -> Unit    cell=default, was_set=false │
  └───────────┬─────────────────────────────────────────┘
              │ Opt に格納
              ▼
  ┌─────────────────────────────────────────────────────┐
  │ Opt[T]                                              │
  │  id       : Int          ← NodeTemplate 参照キー     │
  │  name     : String       ← "--verbose" 等           │
  │  accessor : Accessor[T]  ← 値の読み書きインターフェース │
  │  parsed   : Ref[Bool]    ← Parser.parsed を共有      │
  └─────────────────────────────────────────────────────┘
        │                        │
        │ .get()                 │ .is_set()
        ▼                        ▼
   parsed=true なら            accessor.is_set() を
   Some(accessor.get())        そのまま返す
   parsed=false なら None
```

### Accessor 共有パターン

```
  alias の場合:
  ┌──────────┐     ┌──────────┐
  │ target   │     │ alias    │
  │ Opt[T]   │     │ Opt[T]   │
  └────┬─────┘     └────┬─────┘
       │                │
       ▼                ▼
  ┌──────────┐     ┌──────────────────────────┐
  │Accessor A│     │Accessor A'               │
  │ get ─────┤─共有─┤ get                      │
  │ set ─────┤─共有─┤ set                      │
  │ set_quiet┤─共有─┤ set_quiet                │
  │ is_set ──┤     │ is_set ← alias_was_set   │ ← 独立
  │ mark_set ┤─共有─┤ mark_set                 │
  │ reset ───┤─共有─┤ reset                    │
  └──────────┘     └──────────────────────────┘
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

## 2. パーサのライフサイクルフェーズ

### Phase 1: コンビネータ登録

ユーザーが `p.flag()`, `p.string_opt()`, `p.custom()` 等を呼ぶフェーズ。

**何が起きるか:**

1. `ValCell::new(default)` で `cell`, `was_set`, `default_val` を初期化
2. コンビネータごとに `make_main_node` クロージャを構築（`cell` と `pending` をキャプチャ）
3. `register_option` で:
   - `wrap_node_with_set` が ExactNode の commit に `was_set = true` を注入
   - variation ノードを展開・登録
   - `node_templates[id]` に `make_node` ファクトリを保存（alias/clone 用）
   - `valcell.accessor()` で Accessor を生成し `Opt[T]` に格納
4. `Opt[T]` をユーザーに返す

**ValCell の状態:** `cell = default`, `was_set = false`

### Phase 2: コンポジション構築

ユーザーが `alias`, `clone`, `adjust`, `link`, `deprecated` を呼ぶフェーズ。

| コンビネータ | Accessor 関係 | 主な操作 |
|---|---|---|
| alias | `with_is_set` で共有（is_set のみ独立） | commit 時に `mark_set()` で target まで伝搬 |
| clone | 完全独立 ValCell | save/restore パターンで target の cell を一時利用 |
| adjust | target の Accessor を `post_hooks` でキャプチャ | `is_set` チェック → `set_quiet` で値変換 |
| link | source/target 両方の Accessor をキャプチャ | `source.is_set` チェック → `set_quiet`/`set` で値転送 |
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

**commit で起きること:**

- `cell.val = pending.val`（flag/count/custom の pending → cell 転送）
- `was_set.val = true`（`wrap_node_with_set` 経由、consumed > 0 の場合のみ）

**reset で起きること:**

- `cell.val = default`, `was_set.val = false`
- cmd ノードの場合は子パーサの `parsed`, `current_positional` もリセット

**pending の役割:**

try_reduce は投機的に複数ノードが呼ばれるため、cell に直接書き込むと敗者の副作用が残る。pending に一旦書き込み、勝者の commit でのみ cell に反映する。

### Phase 4: パース実行 — P フェーズ

OC フェーズで消費されなかった引数（unclaimed + `--` 以降の force_unclaimed）を positional に割り当てる。

**何が起きるか:**

- `positional`: handler 内で `pending.val = args[pos]`、commit で `cell.val = pending.val` + `was_set.val = true`
- `rest`: commit で `cell.val.push(value)` + `was_set.val = true`
- `dashdash`: OC フェーズで消費済み（セパレータ + 後続引数をまとめて consumed）

### Phase 5: パース実行 — post_hooks フェーズ

OC + P フェーズ完了後、`post_hooks` を順に実行する。

| hook 種別 | is_set チェック | cell 操作 | was_set 操作 |
|---|---|---|---|
| adjust | target.is_set → true の場合のみ | `set_quiet(transform(get()))` | 変更なし |
| link | source.is_set → true の場合のみ | `set_quiet(source.get())` or `set(source.get())` | propagate_set=true なら true |
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

// is_set(): was_set をそのまま返す（parsed 非依存）
let explicitly_set = opt_verbose.is_set()  // true: ユーザーが指定した

// as_ref(): 制約登録用の OptRef を返す
let ref = opt_verbose.as_ref()  // OptRef { name, is_set }
```

**get と is_set の意味の違い:**

- `get()` は「パース済みか」のガード（`parsed` チェック）。パース前は常に `None`
- `is_set()` は「ユーザーが明示的に指定したか」。default で値があっても `is_set = false`

## 3. Accessor メソッド一覧表

| メソッド | cell への影響 | was_set への影響 | 主な使用タイミング | 主な呼び出し元 |
|---|---|---|---|---|
| `get()` | なし（読み取り） | なし | Phase 5-6 | `Opt::get`, adjust, link, clone の save/restore |
| `set(v)` | `cell = v` | `true` | Phase 5 | link (propagate_set=true), clone の Accessor |
| `set_quiet(v)` | `cell = v` | 変更なし | Phase 5 | adjust, link (propagate_set=false), clone の save/restore |
| `is_set()` | なし | なし（読み取り） | Phase 5-6 | `Opt::is_set`, adjust, link, deprecated, constraints |
| `mark_set()` | なし | `true` | Phase 3 | alias の commit（target の was_set を連鎖更新） |
| `reset()` | `cell = default` | `false` | Phase 3 | ExactNode.reset（OC 競合敗者のリセット） |

### set と set_quiet の使い分け

- **`set`**: 「ユーザーが指定した」のと同等の意味を持たせたい場合。link の propagate_set=true
- **`set_quiet`**: 値だけ変えたいが「ユーザーが指定した」フラグは変えたくない場合。adjust, link のデフォルト

### mark_set の存在理由

alias の commit では、alias 自体の `alias_was_set = true` に加えて target の `was_set = true` も必要。しかし alias は target の cell を共有しているため、`set` を呼ぶと二重書き込みになる。`mark_set` は was_set のみを更新する。

`with_is_set` で Accessor を分岐する際、`mark_set` は差し替えない。これは `mark_set` が root（元の ValCell）の `was_set` を更新する責務を持つため。チェーン alias（alias の alias）でも `mark_set` 経由で root まで伝搬する。

## 4. コンビネータ別 ValCell 使用パターン

### flag

```
ValCell[Bool] + pending: Ref[Bool]

try_reduce: pending = !initial_val        ← 投機（副作用は pending のみ）
commit:     cell = pending                ← 確定
reset:      cell = initial_val, pending = initial_val
```

- `wrap_node_with_set` で commit 時に `was_set = true`
- variation ノードは `vc.cell` と `vc.was_set` を直接操作（pending 不使用）

### count

```
ValCell[Int] + pending: Ref[Int]

try_reduce: pending = pending + 1         ← 投機（累積）
commit:     cell = pending                ← 確定
reset:      cell = 0, pending = 0
```

- 複数回の try_reduce で pending が累積。最後に勝った commit で cell に反映
- `wrap_node_with_set` で commit 時に `was_set = true`

### custom (string_opt / int_opt)

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
commit:   cell = pending, was_set = true  ← 確定
```

- P フェーズで実行。greedy=true の場合のみ OC フェーズでも消費される

### rest

```
ValCell[Array[String]]  ← Thunk(fn() { [] }) で初期化

handler:  (副作用なし)
commit:   cell.push(value), was_set = true  ← 直接 push
```

- 複数回 commit が呼ばれ、1引数ずつ push される

### dashdash / append_dashdash

```
ValCell[Array[String]] or ValCell[Array[Array[String]]]  ← Thunk で初期化

try_reduce: セパレータ以降の引数を収集（副作用なし）
commit:     cell に push, was_set = true
reset:      cell = [], was_set = false
```

- OC フェーズで消費。セパレータ + 後続引数をまとめて consumed
- `wrap_node_with_set` を使わず、commit 内で直接 `was_set = true`

### cmd

```
ValCell[CmdResult?]  ← Val(None) で初期化

try_reduce: 子パーサで再帰的に parse（成功時のみ Accept）
commit:     cell = Some(CmdResult), was_set = true
reset:      cell = None, was_set = false
            子パーサの parsed/current_positional もリセット
```

- `Accessor` は手動構築（`ValCell::accessor()` 不使用）
  - `get` は `None` の場合に空の CmdResult を返す（安全アクセス）
- `Opt[T]` の `parsed` は子パーサの `parsed` を共有（親ではない）
  - `cmd_opt.get()` は子パーサの parse 完了で `Some` を返す

## 5. alias vs clone の Accessor 共有パターン

### alias

```moonbit
let verbose = p.flag(name="verbose")
let v = p.alias("-v", verbose)
```

**構造:**

- `v` の Accessor は `verbose` の Accessor を `with_is_set` で複製
- `get`, `set`, `set_quiet`, `mark_set`, `reset` は全て共有 → 同じ `cell` を操作
- `is_set` のみ `alias_was_set` を参照（独立）

**commit 時の動作:**

1. 元ノードの `commit()` → `cell` に値を書き込み
2. `alias_was_set = true`
3. `target_acc.mark_set()` → target の `was_set = true`

**チェーン alias での伝搬:**

```moonbit
let a = p.flag(name="aaa")       // ValCell.was_set = X
let b = p.alias("--bbb", a)      // alias_was_set = Y, mark_set → X = true
let c = p.alias("--ccc", b)      // alias_was_set = Z, mark_set → Y = true ... ?
```

`c` の commit で `b.accessor.mark_set()` が呼ばれる。`b` の Accessor は `with_is_set` で `is_set` のみ差し替えているが、`mark_set` は元の Accessor（= `a` の ValCell）のものを共有している。そのため `c` の commit は `a` の `was_set` を直接 true にする。

ただし `b` 自身の `alias_was_set` は更新されない。これは `mark_set` が root の `was_set` を操作するためで、中間 alias の `alias_was_set` には伝搬しない。

**is_set の意味:**

- `a.is_set()` → `a` 自身または alias 経由で値が設定されたか（root の was_set）
- `b.is_set()` → `b` という名前で指定されたか（alias 固有の was_set）

### clone

```moonbit
let verbose = p.flag(name="verbose")
let v = p.clone("-v", verbose)
```

**構造:**

- 独立した `clone_cell` + `clone_was_set` を持つ
- Accessor は完全に独立（target と共有するものはない）

**commit 時の save/restore パターン:**

1. `saved = target_acc.get()` — target の現在値を退避
2. 元ノードの `commit()` — target の cell に値を書き込み（ノードのクロージャが target の cell をキャプチャしているため）
3. `clone_cell = target_acc.get()` — 書き込まれた値を clone にコピー
4. `clone_was_set = true`
5. `target_acc.set_quiet(saved)` — target を元に戻す

この方式は、ノードの `commit` が常に target の cell に書き込む前提で動作する。clone は独自の cell を持つが、ノードの振る舞いは target のものを再利用するため、一時的に target を経由する。

### 比較表

| 特性 | alias | clone |
|---|---|---|
| cell | 共有 | 独立 |
| was_set | 独立 + root 伝搬 | 独立 |
| 値の独立性 | なし（同じ値） | あり（別の値） |
| ノードファクトリ | 共有 | 共有（save/restore でラップ） |
| `--name=value` 対応 | eq_fallback 登録 | eq_fallback を save/restore でラップ |
| global 伝搬 | target が global なら伝搬 | target が global なら伝搬 |

## 6. 制限事項

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
