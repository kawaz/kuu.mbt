# struct-first CLI パーサ PoC: E. FieldRef + Binder 方式

## 背景

kuu は MoonBit 製 CLI 引数パーサライブラリ。現行は「パーサ定義 → Opt[T] → .get().unwrap()」のボトムアップ方式。

新しいアイデア「struct-first」:
- アプリの struct が先にある
- CLIパーサはその struct に値を直接注入する
- 取り出し問題（.get().unwrap() の嵐）が構造的に消滅

## このアプローチ: FieldRef + Binder（クロージャ型消去）方式

当初 `trait AnyBind[S]` + trait object を使う設計だったが、**MoonBit の trait は型パラメータを受け付けない**ことが判明（DR-001）。クロージャベースの型消去に変更した。

### コア型

```moonbit
// フィールドへの型安全参照（Lens パターン）
struct FieldRef[S, A] {
  name : String
  get : (S) -> A
  set : (S, A) -> S
}

// 型消去されたバインド（クロージャで T を隠蔽）
struct Binder[S] {
  apply : (S, String) -> Result[S, String]
}

// 型消去ファクトリ — T はこの関数内で消える
fn[S, T] make_binder(field : FieldRef[S, T], parse : (String) -> T?) -> Binder[S]
```

### ユーザー側（簡略化した例）

```moonbit
struct AppConfig {
  name : String
  age : Int
  verbose : Bool
}

// FieldRef 定義（struct update syntax で immutable 更新）
fn AppConfig::name_ref() -> FieldRef[AppConfig, String] {
  { name: "name", get: fn(s) { s.name }, set: fn(s, a) { { ..s, name: a } } }
}

// パーサ定義: make_binder で型消去して同じ配列に格納
let opts : Array[OptDef[AppConfig]] = [
  { opt_name: "--name", binder: make_binder(AppConfig::name_ref(), fn(raw) { Some(raw) }) },
  { opt_name: "--age",  binder: make_binder(
      AppConfig::age_ref(),
      fn(raw) { try { Some(@strconv.parse_int(raw)) } catch { _ => None } },
  ) },
]

let result = parse_args(args, AppConfig::default(), opts)
// result : Result[AppConfig, String]
```

## 検証結果

### MoonBit 技術的検証

| 検証項目 | 結果 |
|---|---|
| `FieldRef[S, A]` — ジェネリック struct | OK |
| struct update syntax `{ ..s, field: v }` | OK |
| `Binder[S]` — クロージャで型消去 | OK |
| `make_binder[S, T]` — 複数型パラメータ関数 | OK |
| 異なる型の Binder を同じ配列に格納 | OK |
| `pub(open) trait IntoOpt` — 手動 impl | OK |
| **`trait AnyBind[S]` — 型パラメータ付き trait** | **NG（MoonBit 非対応）** |
| **`&AnyBind[S]` — 型パラメータ付き trait object** | **NG（同上）** |

### テスト: 全22件パス

## 成功基準

1. MoonBit でコンパイルが通る — **達成**
2. 型消去が正しく動く — **達成**（クロージャベースで実現）
3. FieldRef による get/set が正しく動作 — **達成**
4. IntoOpt trait の手動実装パターンが確立 — **達成**

## 実行方法

```bash
moon run examples/20260314-sf-e-fieldref
moon test --package kawaz/kuu/examples/20260314-sf-e-fieldref
```

## ディレクトリ構成

```
examples/20260314-sf-e-fieldref/
  main.mbt          # PoC 実装 + main デモ
  main_wbtest.mbt   # テスト 22件
  moon.pkg           # パッケージ設定
  README.md          # 本ファイル
  docs/
    DESIGN.md        # 設計書
    decision-records/
      DR-001-*.md    # trait 型パラメータ制限
```
