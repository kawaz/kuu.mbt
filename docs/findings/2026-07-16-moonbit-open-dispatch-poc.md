# MoonBit open dispatch PoC: Node open 化の実現手段

- Date: 2026-07-16
- MoonBit: `moon 0.1.20260709 (102a627 2026-07-09)`
- 対象: `engine` が定義する拡張点を `builtins` が実装し、`kuu` 相当の assembly が組み立てる 3 package 構成
- PoC: session scratchpad の `moonbit-poc/open-dispatch`（リポジトリには含めない）

## 判明した事実

- **PKG-#1 案 B の根本機構は MoonBit で表現できる。** `engine` に `pub(open) trait NodeExt`、閉じた構造 Node に `Ext(&NodeExt)` 1 variant を置き、別 package の `builtins` が自身の型へ `impl @engine.NodeExt` を定義できた。`engine` の evaluator は `ValueArg` / `Marker` という具象型を import せず、`extension.eval(...)` だけで dispatch した。
- `NodeExt::eval(Self, Ctx, Int, Array[String], Cont) -> Array[Branch]` の `Cont` を関数型 alias にすると、`engine` が生成した closure を cross-package trait method に渡せる。closure は残りの `Seq` と外側 continuation を capture でき、builtin node が token を消費した後に残りの評価へ復帰した。
- trait object の object safety 相当制約は実在する。`Self` が戻り値に現れる method は Error 4038（`Self occur in the return type`）、`Self` が receiver 以外の第2引数にも現れる method は Error 4038（`Self occur multiple times`）で `&Trait` 化できない。一方、`equal(Self, &NodeExt) -> Bool` は通った。
- `Ext(&NodeExt)` を持つ通常 enum に `derive(Eq, Debug)` は付けられない。`&NodeExt` が `Eq` / `Debug` を実装しないため Error 4018 になる。PoC では `NodeExt::equal` / `fingerprint` を拡張契約に含め、`Node` の比較・表示を engine が手書きして代替できた。
- MoonBit の `extenum` は別 package から constructor を追加できるが、**evaluator dispatch の単独解ではない**。engine の wildcard arm は plugin constructor の payload や意味論を取得できず、assembly が constructor を明示 match した場合だけ認識できた。また `extenum` 自体に `derive(Eq, Debug)` は付けられず、双方とも Error 4078 になった。
- cross-package 実装には `pub(open) trait` が必要。plain `pub trait` は他 package から readonly と扱われ、impl は Error 4145 になった。さらに「外部 trait × 外部 type」の impl は Error 4061（orphan rule）で拒否される。「engine の open trait × builtins 自身の concrete type」は通る。
- `pub` 型は他 package から型名・method を利用できるが、値の直接構築や field/constructor 参照はできない。`pub(all)` は直接構築まで開く。PoC は `Ctx` / `Branch` / `Registry` / `Node` を read-only `pub` または package-private に保ち、accessor / factory (`token_at`, `held`, `Registry::new`, `ext`) 経由で builtins から使えた。
- `_wbtest.mbt` は**その package だけ**の private symbol を参照できる。assembly package の wbtest から engine package の private symbol を参照すると Error 4021、blackbox `_test.mbt` から assembly 自身の private symbolを参照しても Error 4021 になった。assembly の blackbox test は engine / builtins の公開 API を通した conformance test を実行できた。
- registry は `Map[String, &NodeExt]` として保持でき、関数内で生成した concrete value を trait object に coercion して登録・lookup・dispatch できた。
- `init { ... }` 構文は存在せず Parse Error 3002 になった。`const Map[...]` も「constant type は immutable primitive のみ」として Error 4143 になった。
- package-level `let` initializer に副作用を書くこと自体は可能だが、**package の別関数を使うだけでは initializer は発火しない**。`builtins` の別 factory を呼んだ fresh executable でも global registry は wasm-gc / JS / native の全 target で `missing:value_arg` だった。initializer 値を明示的に touch した場合だけ登録された。
- 正の PoC は wasm-gc / JS / native の3 targetすべてで `7 passed, 0 failed` だった。

## 実用的な示唆 / ベストプラクティス

1. **推奨形は「閉じた構造 Node + `Ext(&NodeExt)` 1 variant」**。`extenum` 単独では engine が未知 constructor を評価できず、assembly の巨大 match へ具象知識を移すだけになる。trait object なら evaluator の dispatch 点を engine に保ったまま具象意味論を builtins に置ける。
2. 現行の defunctionalized `Cont` ADT は builtins に公開しなくてよい。engine 内で `Cont` を capture した `Resume` callback を作り、`NodeExt::eval` へ渡せば、completes-cache 用の内部表現を extension ABI から隠せる。PoC の raw closure はこの境界が MoonBit で成立することを確認するための最小形であり、現行 `Cont` の廃止を意味しない。
3. `Ctx` も `pub(all)` にせず read-only `pub` + capability method にする。builtins が必要とする token access、mode 判定、Held/Pending 構築を accessor / factory に限定すれば、engine 内部 field を公開せずに実装できる。
4. 自動 `Eq` / `Debug` は失われるため、extension 契約に**意味論的な比較と表示**を明示する必要がある。PoC の `fingerprint : String` は実現可能性確認用の最小例であり、本実装では collision のない descriptor identity と config 比較、安定した debug representation を契約として設計する。
5. trait method は object-safe な signature に限定する。具象 `Self` を返す clone、`equal(Self, Self)` のような第2の `Self`、具象型を戻す factory は registry/installer 側へ置き、runtime dispatch trait には入れない。比較相手を `&NodeExt` とする `equal(Self, &NodeExt)` は利用できる。
6. 登録は **`kuu` assembly が `builtins.install(registry)` を明示呼び出しする方式**を採る。package-level side effect は reachability に依存し、単なる import / package 使用では登録されない。明示 assembly は構成順・重複・テスト隔離も観測可能になる。
7. test 配置は、engine / builtins 各 package に内部 invariant 用 `_wbtest.mbt`、kuu assembly package に公開 API 経由の conformance runner (`_test.mbt`) を置く構成が成立する。assembly wbtest を engine private への friend access 代わりにはできない。
8. `extenum` は Node evaluator ではなく、「constructor を開くこと自体が目的で、未知 case を wildcard 処理できる」別のデータ境界には使える。MoonBit 公式にも cross-package constructor extension と wildcard 必須が明記されている（[Fundamentals](https://docs.moonbitlang.com/en/latest/language/fundamentals.html)、[2026-05-13 release notes](https://www.moonbitlang.com/updates/2026/05/13/index)）。

## 検証の詳細

### 検証マトリクス

| # | 項目 | 期待 | 実態 | 判定 |
|---|---|---|---|---|
| 1 | trait object dispatch | engine の open trait を builtins が実装し、engine が具象型なしで呼べる | `pub(open) trait NodeExt` + `Ext(&NodeExt)` + cross-package impl が3 targetで動作 | 成立 |
| 1a | object safety: callback | function type / closure を method 引数で渡せる | `Cont` callback を渡し、builtins が呼び戻せた | 成立 |
| 1b | object safety: `Self` return | trait object にできる可能性 | Error 4038 | 不成立 |
| 1c | object safety: 第2 `Self` | `equal(Self, Self)` を trait object で使える可能性 | Error 4038 | 不成立 |
| 1d | object safety: trait object 引数 | `equal(Self, &NodeExt)` を使える | compile/test 成功 | 成立 |
| 2 | enum 共存 | 構造 variant + `Ext` 1 variant を match できる | `Exact` / `Seq` / `Ext` の再帰評価が動作 | 成立 |
| 2a | `derive(Eq, Debug)` | 現行 derive をそのまま維持できる可能性 | `&NodeExt` に Eq/Debug がなく Error 4018 | 不成立 |
| 2b | 手書き Eq/表示 | extension 契約経由で代替できる | `NodeExt::equal` / `fingerprint` で wbtest 成功 | 成立 |
| 2c | `extenum` cross-package constructor | Node 型自体を constructor open にできる | plugin が `ValueArg` constructor を追加できた | 成立 |
| 2d | `extenum` evaluator dispatch | engine wildcard から plugin 意味論を呼べる | engine は `unknown-to-engine`、assembly の具象 match だけが認識 | 単独では不成立 |
| 2e | `extenum derive(Eq, Debug)` | open enumでも derive 可能な可能性 | Error 4078 | 不成立 |
| 3 | CPS 継続受け渡し | builtin node が token 消費後、残りの Seq へ復帰できる | `--port 8080` → `Accept(2, ["port=8080", "seen=true"])` | 成立 |
| 3a | closure capture | engine closure が残り items / idx / outer k を保持できる | `eval_seq` の closure 経由で Marker まで実行 | 成立 |
| 4 | cross-package visibility | `pub(open)` / `pub` / `pub(all)` を使い分けられる | open trait impl、read-only public API、factory 構築が動作 | 成立 |
| 4a | plain `pub trait` の外部 impl | open と同様に実装可能な可能性 | readonly Error 4145 | 不成立 |
| 4b | orphan rule | foreign trait × foreign type も実装可能な可能性 | Error 4061 | 不成立 |
| 4c | plain `pub` 型の外部直接構築 | field / constructor を直接使える可能性 | read-only Error 4036 | 不成立（意図どおり隠蔽） |
| 5 | wbtest 分離 | assembly wbtest が engine private に届く可能性 | symbol not found Error 4021 | 不成立 |
| 5a | package-local wbtest | 自 package private に届く | engine/assembly 双方で成功 | 成立 |
| 5b | assembly blackbox conformance | 公開 API 経由で package 横断実行できる | dispatch/registry test 成功 | 成立 |
| 6 | 明示 registry | assembly が registry を生成し builtins を登録できる | 2 extension を登録・lookupできた | 成立 |
| 6a | `init {}` | 専用 init block が使える可能性 | Parse Error 3002 | 不成立 |
| 6b | const registry | const Map を持てる可能性 | Error 4143、immutable primitive のみ | 不成立 |
| 6c | package-level side effect | package 使用だけで自動登録される可能性 | 3 target とも `missing:value_arg` | 不成立 |
| 6d | initializer の明示 touch | touch すれば登録できる | global registry に2 extension 登録 | 成立（明示呼出しが必要） |

### 動いた最小インターフェース

engine 側は具象 builtin 型を一切参照しない。

```moonbit
pub type Cont = (Ctx, Int, Array[String]) -> Array[Branch]

pub(open) trait NodeExt {
  fn kind(Self) -> String
  fn fingerprint(Self) -> String
  fn equal(Self, &NodeExt) -> Bool
  fn eval(Self, Ctx, Int, Array[String], Cont) -> Array[Branch]
}

enum Node {
  Exact(String)
  Seq(Array[Node])
  Ext(&NodeExt)
}

pub fn eval_node(
  node : Node,
  ctx : Ctx,
  pos : Int,
  acc : Array[String],
  k : Cont,
) -> Array[Branch] {
  match node {
    Exact(s) =>
      if pos < ctx.toks.length() && ctx.toks[pos] == s {
        k(ctx, pos + 1, acc)
      } else {
        [Held("expected " + s, pos, acc)]
      }
    Seq(items) => eval_seq(items, 0, ctx, pos, acc, k)
    Ext(extension) => extension.eval(ctx, pos, acc, k)
  }
}
```

`eval_seq` が作る callback は残りの sequence と outer continuation を capture する。

```moonbit
(ctx2, pos2, acc2) => eval_seq(items, idx + 1, ctx2, pos2, acc2, k)
```

builtins 側は engine の open trait を自身の型へ実装する。`Ctx` は read-only `pub` で、token access は method 経由。`Branch` の constructor も直接公開せず factory を使う。

```moonbit
impl @engine.NodeExt for ValueArg with fn eval(self, ctx, pos, acc, k) {
  match ctx.token_at(pos) {
    Some(token) => {
      let next : Array[String] = []
      for value in acc {
        next.push(value)
      }
      next.push(self.name + "=" + token)
      k(ctx, pos + 1, next)
    }
    None => [@engine.held("missing " + self.name, pos, acc)]
  }
}

pub fn value_arg(name : String) -> @engine.Node {
  @engine.ext(ValueArg::{ name } as &@engine.NodeExt)
}
```

### CPS の観測結果

assembly は次の Node を構築した。

```moonbit
@engine.seq([
  @engine.exact("--port"),
  @builtins.value_arg("port"),
  @builtins.marker("seen", "true"),
])
```

blackbox test の観測:

```text
input  = ["--port", "8080"]
output = [Accept(2, ["port=8080", "seen=true"])]
```

`ValueArg` が `pos=1` の token を消費して `k(ctx, 2, next)` を呼び、engine closure が残りの `Marker` を評価したため、`seen=true` が最終 acc に入っている。これは単に trait method が呼ばれた証拠ではなく、**builtin hook から engine の残り CPS 経路へ復帰できた証拠**である。

### `Eq` / `Debug` の制約

通常 enum の trait object payload:

```moonbit
enum Node {
  Exact(String)
  Extension(&Ext)
} derive(Eq, Debug)
```

`moon check` は以下を返した。

```text
Type &Ext does not implement trait Debug
Type &Ext does not implement trait Eq
```

`extenum` も別理由で derive 不可だった。

```text
Cannot derive trait Eq for type OpenNode: target type is an extensible enum
Cannot derive trait Debug for type OpenNode: target type is an extensible enum
```

したがって「通常 enum + trait object」から `extenum` へ替えても現行の構造比較 derive は戻らない。比較・表示契約を明示する必要がある。

### `extenum` の確認

base package:

```moonbit
pub(all) extenum OpenNode {
  Exact(String)
}
```

plugin package:

```moonbit
pub(all) extenum @extengine.OpenNode += {
  ValueArg(String)
}
```

assembly は `@extplugin.ValueArg` を match できたが、base engine の関数は wildcard に落ちた。

```text
["exact:--port", "unknown-to-engine", "value_arg:port"]
```

`extenum` は open data constructor の機構であって、unknown constructor の behavior を base package へ逆注入する機構ではない。

### visibility と orphan rule

| 宣言 / impl | 観測 |
|---|---|
| `pub(open) trait NodeExt` + builtins-local `ValueArg` | cross-package impl 成功 |
| `pub trait ClosedExt` + builtins-local `Concrete` | Error 4145: trait is readonly |
| `pub(open) trait NodeExt` + foreign `String` | Error 4061: foreign trait for foreign type |
| `pub struct Ctx` | 他 package で型として受け取り method 呼出し可能、直接構築不可 |
| `pub(all) struct OpenCtx` | 他 package で record literal 構築可能 |
| package-private `enum Node` + public factory | concrete constructor を隠したまま opaque return/argument として利用可能 |

このため、extension ABI の型をすべて `pub(all)` にする必要はない。builtins が自身で構築すべき concrete extension type だけ builtins 側の判断で公開し、engine carrier は read-only 型 + factory にできる。

### test 可視性

正の test:

- `engine/engine_wbtest.mbt` → engine private を参照: 成功
- `assembly/assembly_wbtest.mbt` → assembly private を参照: 成功
- `assembly/assembly_test.mbt` → assembly public API 経由で engine + builtins を実行: 成功

負の test:

```text
assembly _wbtest -> @engine.private_engine_probe
Value private_engine_probe not found in package `engine` (Error 4021)

assembly _test -> @assembly.private_assembly_probe
Value private_assembly_probe not found in package `assembly` (Error 4021)
```

`_wbtest` は package 横断 friend ではない。conformance runner を kuu assembly に置く場合、runner が必要とする engine/builtins の観測面は公開 API として設計する必要がある。

### registry / 初期化機構

明示 registry は次の形で動作した。

```moonbit
pub struct Registry {
  entries : Map[String, &NodeExt]
}

pub fn install(registry : @engine.Registry) -> Unit {
  registry.register(ValueArg::{ name: "prototype" } as &@engine.NodeExt)
  registry.register(Marker::{ name: "prototype", value: "true" } as &@engine.NodeExt)
}
```

assembly の `install` 後:

```text
["Ext(value_arg:prototype)", "Ext(marker:prototype=true)"]
```

一方、package-level initializer を用意した builtins package の別 factory だけを呼び、initializer 値を参照しない fresh executable では:

| target | global lookup |
|---|---|
| wasm-gc | `missing:value_arg` |
| JS | `missing:value_arg` |
| native | `missing:value_arg` |

明示的に initializer 値を touch した test では登録された。よって「import された builtins が起動時に自動登録」という設計は成立せず、assembly の明示 install が必要である。

### backend マトリクス

| command | 結果 |
|---|---|
| `moon test --target wasm-gc` | `Total tests: 7, passed: 7, failed: 0.` |
| `moon test --target js` | `Total tests: 7, passed: 7, failed: 0.` |
| `moon test --target native` | `Total tests: 7, passed: 7, failed: 0.` |

検証 suite は cross-package trait object、再帰 enum wrapper、CPS callback、manual equality、明示/明示-touch registry、package-local wbtest、assembly blackbox test、cross-package `extenum` constructor を含む。

### 公式資料との照合

MoonBit 公式資料は `extenum` について、別 package から constructor を追加できること、pattern match に wildcard が必要なことを明記している。

- [MoonBit Fundamentals — Extensible enums](https://docs.moonbitlang.com/en/latest/language/fundamentals.html)
- [MoonBit v0.9.2 release notes (2026-05-13)](https://www.moonbitlang.com/updates/2026/05/13/index)

derive 可否、trait object との比較、evaluator dispatch、initializer reachability、wbtest 境界は公式記述だけでは決めず、上記 PoC の実機結果を根拠とした。
