# struct-first CLI パーサ PoC: D. ValuePath 方式

## 背景

kuu は MoonBit 製 CLI 引数パーサライブラリ。現行は「パーサ定義 → Opt[T] → .get().unwrap()」のボトムアップ方式。

新しいアイデア「struct-first」:
- アプリの struct が先にある
- CLIパーサはその struct に値を直接注入する
- 取り出し問題（.get().unwrap() の嵐）が構造的に消滅

## このアプローチ: ValuePath 方式（ユーザーのオリジナルスケッチ）

**これはユーザー（kuu 作者）が最初に思いついたアプローチ**。以下はユーザーの殴り書きから抽出したイメージ:

```
Opt[T]はValRef[T]の代わりにこんな感じのを持つのかな?

enum Commit[T] {
  Exist(() -> T)        // フラグ的。存在したらTを返す
  Value((T) -> T)       // 変換的。現在の値を受け取って新しい値を返す
}
```

```
vervoseならvp=VP::Exist(()->true)
--nameなら vp=VP::Value((String)->String)

app = Docker::new(
  vervose: ValuePath("--vervose"を見つけたら呼ばれる)
)
```

```
parse(args,
  (arg, path) { マッチしたらvp実行してね }
)
```

**核心**: `Commit[T]` で値注入の戦略を表現し、`ValuePath[T]` で CLI引数パターンと struct フィールドの対応を記述する。

```moonbit
// 値注入の戦略
enum Commit[T] {
  Exist(() -> T)      // フラグ: 存在したら値を返す
  Value((T) -> T)     // 値変換: 現在値を変換して返す
}

// CLI引数 → structフィールドの対応
struct ValuePath[S, T] {
  pattern : String         // "--verbose" 等
  commit : Commit[T]       // 値の生成方法
  apply : (S, T) -> S      // structへの適用方法
}

// 使用イメージ
let config = AppConfig { verbose: false, name: "", count: 0 }
let paths = [
  ValuePath {
    pattern: "--verbose",
    commit: Exist(fn() { true }),
    apply: fn(s, v) { { ..s, verbose: v } },
  },
  ValuePath {
    pattern: "--name",
    commit: Value(fn(v) { v }),      // String → String
    apply: fn(s, v) { { ..s, name: v } },
  },
]
let result = parse(args, config, paths)
```

## 検証すべき MoonBit 技術的疑問

1. **Commit[T] enum**: ジェネリック enum は動くか？
2. **型消去**: `ValuePath[S, Bool]` と `ValuePath[S, String]` を同じ配列に入れるには？
   - Trait object 化？
   - クロージャで内部を束縛して `(S, String) -> S` に統一？
3. **struct update syntax**: `{ ..s, verbose: v }` は動くか？
4. **パターンマッチング**: CLI引数文字列と ValuePath.pattern のマッチング

## ユーザーが追加で考えていたこと

```
struct Value[T] {
  val : T?
  getter : ValuePath[T]
  setter : ...
}
```

Opt[T] が ValuePath[T] を内部に持ち、パースとstruct書き込みを一体化するイメージ。

## 検証手順

1. `Commit[T]` enum の定義と基本動作確認
2. `ValuePath[S, T]` の定義と型消去パターンの試行
3. `parse` 関数の実装（型消去された ValuePath 配列を走査）
4. struct update syntax の動作確認
5. サブコマンド対応（ネストした ValuePath）

## 成功基準

1. MoonBit でコンパイルが通る
2. Commit enum で flag/string_opt/int_opt の区別が自然にできる
3. 型消去が実現でき、異なる型の ValuePath を統一的に扱える
4. ユーザーの書くコードが直感的

## 既存 kuu の使い方参考

`examples/20260308-mydocker/main.mbt` を参照。
パッケージ: `import { "kawaz/kuu/src/core" }` + `options("is-main": true)`

## 作業方法

/itumono-full-loop でフルオートループ。PoC なので「動くかどうか」の確認が最優先。
動かない場合は「なぜ動かないか」を DR に記録すること。

ユーザーのオリジナルスケッチをできるだけ忠実に実現することを目指しつつ、MoonBit の制約で変更が必要な場合はその理由を記録する。
