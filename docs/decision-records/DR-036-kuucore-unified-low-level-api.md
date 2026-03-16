# DR-036: KuuCore — 各言語向け統一低レベル API 設計

type: decision

日付: 2026-03-09
ステータス: **設計中**

## 背景

DR-027 で「core は純粋パースエンジン、各言語で高級API」を構想し、DR-030 で opt AST のポータビリティを確認、DR-035 で WASM bridge の全機能対応を実装した。

しかし WASM bridge は JSON 往復の生のインターフェースであり、各言語から直接使うには以下の問題がある:

- JSON の組み立て/パースがボイラープレート
- custom[T] や任意 post はクロージャなので JSON に載らない
- エラーハンドリングが JSON の ok/error フィールドの手動チェック
- 各 DX ラッパーが個別に bridge 呼び出しを実装すると車輪の再発明

## 決定

### 4層アーキテクチャ

```
Layer 4: DX API (各言語のイディオムに最適化)
           TypeScript: builder / schema / valibot-style 等
           Go: functional options / cobra-compat 等
         ────────────────────────────────────
Layer 3: KuuCore (各言語向け統一低レベル API)
           - WASM bridge の JSON 往復を隠蔽
           - custom[T] / post のコールバック中継
           - 直接 export と WASM の差を吸収
           - 全言語で同じ API 面
         ────────────────────────────────────
Layer 2: WASM bridge (JSON in → kuu core → JSON out)
         ────────────────────────────────────
Layer 1: kuu core (MoonBit 純粋パースエンジン)
```

### KuuCore の責務

1. **bridge 抽象化**: JSON の組み立て・パースを隠蔽し、型付き API を提供
2. **コールバック中継**: custom[T] や任意 post クロージャの往復を解決
   - 往路: クロージャを保持 → schema には string_opt として載せる → WASM に投げる
   - 復路: WASM パース結果 (String) を受け取る → 保持していたクロージャで変換/検証
3. **バックエンド非依存**: 直接 export（MoonBit ネイティブ FFI）と WASM bridge の差を吸収
4. **エラー型変換**: JSON の ok/error を各言語のエラー型（例: Go の error, Swift の throws）に変換
5. **結果の型安全アクセス**: パース結果を型付きで取得する API

### KuuCore の設計原則

- **全言語で同じ API 面**: 言語間で学習コストを最小化
- **堅い API**: 型安全、完全なエラーハンドリング、全機能カバー
- **DX は上に任せる**: KuuCore は多少使いづらくてもいい。sugar は Layer 4 の仕事
- **テスト可能**: KuuCore レベルでの統合テストを各言語で実施

### コールバック中継の仕組み

```
ユーザーコード: kuu.custom("port", parse: parseInt, validate: isPort)

KuuCore 内部:
  1. callbacks["port"] = { parse: parseInt, validate: isPort } に保持
  2. JSON schema には { kind: "string", name: "port" } として載せる
  3. WASM bridge でパース → result.values.port = "8080" (String)
  4. callbacks["port"].parse("8080") → 8080 (Int)
  5. callbacks["port"].validate(8080) → true
  6. 最終結果: port = 8080

エラー時:
  3'. WASM bridge でパース → result.values.port = "abc"
  4'. callbacks["port"].parse("abc") → ParseError
  5'. KuuCore がエラーを各言語のエラー型で返す
```

### 直接 export vs WASM bridge の統一

```
               KuuCore API (同一)
                    |
         ┌─────────┴──────────┐
         │                    │
   NativeBackend         WasmBackend
   (MoonBit FFI)       (JSON 往復)
```

- **NativeBackend**: MoonBit から直接ビルドされた言語バインディング（将来）
- **WasmBackend**: 現在の WASM bridge 経由

利用者は Backend を選ぶだけで、API は同一。

## DX API (Layer 4) の位置づけ

KuuCore の上に、各言語のイディオムに合った DX API を自由に構築できる:

- 同一言語に複数の DX スタイルが共存可能（DR-027）
- 既存ライブラリ互換 API も構築可能（kuu-clap, kuu-cobra 等）
- コミュニティが独自 DX API を作ることも可能

## KuuCore 具体 API 設計

### 統一 API 面（全言語共通）

以下は TypeScript で記述するが、全言語で同等の API 面を持つ。

#### スキーマ定義

```typescript
// KuuCore はビルダーではなく、型付きスキーマヘルパーを提供
// DX 層がビルダーパターン等を上に構築する

interface KuuSchema {
  description?: string;
  opts: KuuOptDef[];
  require_cmd?: boolean;
  exclusive?: string[][];
  required?: string[];
}

// 各 kind の型付き定義ヘルパー（JSON リテラルの薄いラッパー）
KuuCore.flag(name, { default?, shorts?, global?, description?, hidden?, aliases?, variations? })
KuuCore.stringOpt(name, { default, shorts?, global?, description?, choices?, implicit_value?, post? })
KuuCore.intOpt(name, { default, shorts?, global?, description?, choices?, implicit_value?, post? })
KuuCore.count(name, { shorts?, global?, description? })
KuuCore.appendString(name, { shorts?, global?, description? })
KuuCore.appendInt(name, { shorts?, global?, description? })
KuuCore.positional(name, { description? })
KuuCore.rest(name, { description?, stop_before? })
KuuCore.dashdash()
KuuCore.serial(opts)
KuuCore.command(name, { description?, aliases?, opts?, require_cmd? })
```

#### コールバック付きオプション（custom[T] 相当）

```typescript
// KuuCore が bridge に string_opt として載せ、結果を parse 関数で変換
KuuCore.custom<T>(name, {
  parse: (raw: string) => T,          // String → T 変換
  validate?: (value: T) => boolean,   // バリデーション
  default: T,
  // ...他の共通パラメータ
})

// 任意 post フィルタ（プリセット以外）
KuuCore.stringOpt(name, {
  default: "",
  postFn: (value: string) => string,  // ホスト側で実行
})
```

#### パース実行

```typescript
// 同期（TypeScript の場合は async）
const result: KuuResult = await KuuCore.parse(schema, args);

// KuuResult は discriminated union
type KuuResult =
  | { ok: true; values: KuuValues; command?: KuuCommand }
  | { ok: false; error: string; help?: string }
  | { ok: false; help_requested: true; help: string }
```

#### 結果取得

```typescript
// 型安全な getter（名前ベース）
result.getString(name): string | undefined
result.getInt(name): number | undefined
result.getBool(name): boolean | undefined
result.getStrings(name): string[]     // append_string
result.getInts(name): number[]        // append_int
result.getCount(name): number         // count
result.getDashdash(): string[]        // dashdash

// デフォルト値付き getter（get().unwrap() の嵐を解消）
result.getStringOr(name, default): string
result.getIntOr(name, default): number
result.getBoolOr(name, default): boolean

// コマンド走査
result.command?: { name: string; values: KuuValues; command?: KuuCommand }
```

### コールバック中継の実装詳細

```
parse() 呼び出し時の内部フロー:

1. スキーマ走査: custom/postFn を持つ opt を発見
2. コールバック登録: callbacks[name] = { parse, validate, postFn } に保持
3. スキーマ変換: custom → string_opt に降格、postFn → 除外してプリセットのみ残す
4. WASM 呼び出し: 変換済み JSON schema + args → kuu_parse → JSON result
5. 結果後処理:
   for (name, cb) of callbacks:
     raw = result.values[name]  // String
     if cb.parse:
       result.values[name] = cb.parse(raw)  // T に変換
     if cb.validate:
       if !cb.validate(result.values[name]):
         return Error("validation failed for " + name)
     if cb.postFn:
       result.values[name] = cb.postFn(result.values[name])
6. 型付き KuuResult として返却
```

### バックエンド抽象化

```typescript
// Backend インターフェース（各言語で実装）
interface KuuBackend {
  parse(schemaJson: string): string;  // JSON in → JSON out
}

// TypeScript: 直接 WASM 呼び出し
class WasmDirectBackend implements KuuBackend {
  private kuu_parse: (input: string) => string;
  async init() {
    const { instance } = await WebAssembly.instantiate(wasmBytes, {}, {
      builtins: ["js-string"],
      importedStringConstants: "_",
    });
    this.kuu_parse = instance.exports.kuu_parse;
  }
  parse(input: string): string { return this.kuu_parse(input); }
}

// Go/Python/Swift: サブプロセス経由
class SubprocessBackend implements KuuBackend {
  // node/bun/deno + bridge.mjs を subprocess で呼ぶ
  parse(input: string): string { ... }
}

// 将来: MoonBit ネイティブ FFI
class NativeBackend implements KuuBackend { ... }
```

### エラー型の統一

```typescript
// 各言語で等価な型を定義
enum KuuErrorKind {
  UnexpectedArgument,   // "unexpected argument: --foo"
  MissingRequired,      // "required option missing: --name"
  MutuallyExclusive,    // "mutually exclusive options: --a, --b"
  InvalidValue,         // "value must not be empty" / "value 10 out of range [0, 9]"
  SubcommandRequired,   // "subcommand required"
  AmbiguousArgument,    // "ambiguous argument: --foo"
  SchemaError,          // "opt definition missing 'name'"
  HelpRequested,        // ヘルプ表示（エラーではないが特別扱い）
}

interface KuuError {
  kind: KuuErrorKind;
  message: string;
  help?: string;        // エラー時のヘルプテキスト
}
```

現在の bridge はエラーメッセージが文字列のみ。KuuCore がメッセージをパターンマッチして kind に分類するか、bridge 側で error_code フィールドを追加するかは実装時に判断。

### bridge.mjs テンプレートの統一

```javascript
// 全言語のサブプロセスバックエンドが共有する bridge スクリプト
// kuu npm パッケージに同梱、または KuuCore が自動展開
import { readFileSync } from "node:fs";

const wasmPath = new URL("./kuu.wasm", import.meta.url);
const wasmBytes = readFileSync(wasmPath);
const { instance } = await WebAssembly.instantiate(wasmBytes, {}, {
  builtins: ["js-string"],
  importedStringConstants: "_",
});

let input = "";
for await (const chunk of process.stdin) input += chunk;
const result = instance.exports.kuu_parse(input);
process.stdout.write(result);
```

### 各言語での bridge.mjs の配置

KuuCore パッケージが以下を同梱:
- `kuu.wasm` — ビルド済み WASM モジュール
- `bridge.mjs` — stdin/stdout JSON 往復スクリプト

TypeScript は bridge.mjs 不要（直接 WASM ロード）。

## 既存 example からの知見

### 共通ボイラープレート（KuuCore で解消すべき）

1. **WASM ロード/サブプロセス起動** — 各 example で独自実装。KuuCore の Backend に統一
2. **JSON スキーマ組み立て** — 型なし辞書リテラルの手書き。KuuCore のヘルパー関数で型付き化
3. **結果の値取得** — `values["name"]` からの手動キャスト。KuuCore の getter で型安全化
4. **エラーハンドリング** — ok/error の手動チェック。KuuCore のエラー型で統一

### 言語ごとの差異（KuuCore 内部で吸収）

| 言語 | WASM 実行 | JSON ライブラリ | エラー型 |
|---|---|---|---|
| TypeScript | WebAssembly.instantiate 直接 | JSON.parse/stringify | throw / union |
| Go | subprocess + Node.js | encoding/json | error interface |
| Python | subprocess + Node.js | json モジュール | Exception / dataclass |
| Swift | subprocess + bun | JSONSerialization | throws / enum Error |

## 実装優先度

1. TypeScript KuuCore（V8 で WASM 直接実行、最もシンプル。リファレンス実装）
2. Go / Python KuuCore（Node.js サブプロセス経由）
3. Swift KuuCore（bun サブプロセス経由）
4. 各言語の DX API（KuuCore 安定後）

## 関連 DR

- DR-027: core 純粋関数主義 + 多言語 DX レイヤー構想（本 DR の出発点）
- DR-030: opt AST の言語間ポータビリティ（KuuCore が活用する基盤）
- DR-035: WASM bridge 全機能対応（Layer 2 の完成）
