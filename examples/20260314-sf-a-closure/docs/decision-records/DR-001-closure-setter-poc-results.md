# DR-001: クロージャ Setter 方式 PoC 結果

## 概要

struct-first CLI パーサ構想の方式 A「クロージャ Setter 方式」の技術的検証結果。

## 検証結果サマリ

| 検証項目 | 結果 | 備考 |
|---|---|---|
| mut struct + クロージャキャプチャ | **動作する** | MoonBit の struct は参照型 |
| 型消去（`() -> Unit` 配列） | **動作する** | setter クロージャに値を束縛して型消去 |
| kuu Parser + setter ラッパー | **動作する** | StructFirst ラッパーで実現 |
| サブコマンドネスト | **動作する** | Docker 風 3 階層で検証 |

## 検証 1: MoonBit のクロージャキャプチャ

MoonBit の struct は参照型（ヒープ割り当て）のため、クロージャが struct を捕捉すると参照が共有される。`mut` フィールドへの書き込みは呼び出し元にも反映される。

```moonbit
let config = { verbose: false, name: "", count: 0 }
let setter = fn() { config.verbose = true }
setter()
// config.verbose == true ← 反映される
```

型の異なる setter も `() -> Unit` に型消去して配列に格納可能:

```moonbit
let setters : Array[() -> Unit] = [
  fn() { config.verbose = true },
  fn() { config.name = "x" },
]
```

## 検証 2: StructFirst ラッパー

kuu の既存 API（`Opt[T]` + `.get().unwrap()`）の上に薄いラッパーを構築:

```moonbit
struct StructFirst {
  parser : @core.Parser
  copiers : Array[() -> Unit]  // parse 後に実行
}
```

各コンビネータ（flag, string_opt, int_opt 等）に `setter` パラメータを追加。内部で `Opt[T]` を生成し、parse 後に copier クロージャで struct にコピー:

```moonbit
fn StructFirst::flag(self, name~, setter~) {
  let opt = self.parser.flag(name~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => setter(v)
      None => ()
    }
  })
}
```

### 利点

- **`.get().unwrap()` の嵐が消滅**: parse 後は struct を直接参照
- **型安全**: setter の引数型は Opt[T] の T と一致（コンパイル時チェック）
- **kuu core 無改造**: 既存 API の上に構築可能

### 制限事項

- **サブコマンド判定**: `result.child("cmd")` による分岐は StructFirst ラッパーでは隠蔽できない。サブコマンド部分は kuu の raw API を直接使う混合スタイルになる
- **copiers の実行タイミング**: parse 成功後に一括実行。サブコマンドの copiers も含めて全実行するため、マッチしなかったサブコマンドの copiers も走る（`opt.get()` が `None` を返すだけなので実害なし）

## 検証 3: サブコマンドネスト

Docker 風の 3 階層（docker → compose → up）を検証:

```
docker --debug run -dit ubuntu bash
docker compose -f prod.yml up -d --scale 3 web db
```

**結果**: 完全に動作。グローバルオプション（`--debug`）もサブコマンド内で正しく反映。

**サブコマンドの struct-first パターン**:

```moonbit
// グローバルは StructFirst ラッパー
sf.flag(name="debug", global=true, setter=fn(v) { config.global.debug = v })

// サブコマンドは raw kuu API + copiers 直接登録
let run_cmd = sf.parser.sub(name="run")
let detach = run_cmd.flag(name="detach")
sf.copiers.push(fn() {
  match detach.get() {
    Some(v) => config.run.detach = v
    None => ()
  }
})
```

## 代替アプローチとの比較

### commit ヘルパー（post フィルタ方式）

kuu の `post` パラメータを使い、パース時点で直接 struct に注入:

```moonbit
fn commit[T](setter) -> FilterChain[T, T]? {
  Some({ run: fn(v) { setter(v); v } })
}
p.string_opt(name="name", post=commit(fn(v) { config.name = v }))
```

- **利点**: parse 中にリアルタイム反映
- **制限**: flag/count は `post` パラメータ未対応。StructBinder との混合が必要

### StructFirst ラッパー（本方式）

- **利点**: 全コンビネータで統一的に setter パターンを使える
- **制限**: parse 後の一括コピーなので、パース中に struct 参照しても値が入っていない

## 結論

クロージャ Setter 方式は MoonBit + kuu で完全に動作する。struct-first DX レイヤーの基盤技術として有効。

ただし、サブコマンド周りの API 設計（特にマッチ判定の隠蔽）は今後の課題。

## 型安全性・エルゴノミクス評価

### 型安全性

setter クロージャの型は **コンパイル時に検出される**。

```moonbit
// Int フィールドに String setter → コンパイルエラー
sf.string_opt(name="count", setter=fn(v) { config.count = v })
// → error: String は Int に代入できない
```

- `sf.flag()` は `setter~ : (Bool) -> Unit` を期待
- `sf.string_opt()` は `setter~ : (String) -> Unit` を期待
- フィールドの型と setter の型が不一致なら MoonBit がコンパイル時に弾く
- `get().unwrap()` 方式と同等の型安全性を保持

### ボイラープレート比較

| 層 | 現行方式 | StructFirst | 削減 |
|---|---|---|---|
| グローバルオプション | `.get().unwrap()` × N | setter クロージャ | 20-30% 削減 |
| サブコマンド Lv1 | 手動 match | 手動 copier | 削減なし |
| ネストサブコマンド | 手動 match | 手動 copier | 削減なし |

### サブコマンドの制約

StructFirst は現状サブコマンド内のオプション登録に対応していない。`setup_docker_parser` では直接 kuu API を使い、`sf.copiers.push()` で手動登録している。

改善案:
- `StructFirst::sub()` メソッドで子ビルダーを返す設計
- ただし型消去がさらに複雑化するため、kuu core の post_hooks パターンのほうが適切な可能性

### kuu core 統合の方針

- Layer 1 (core) への統合は **非推奨**。core は最小限のパースに特化すべき
- Layer 3 (KuuCore) または Layer 4 (DX API) で提供するのが適切
- 他言語（Go の struct tag、TS の schema）では別パターンが自然なため、core に bake-in しない
