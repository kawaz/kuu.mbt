# kuu TypeScript 高級 API 設計

## 目標

TypeScript ユーザーが kuu を使うとき、以下の体験を実現する:

1. **パーサ定義が宣言的** -- オブジェクトリテラルでスキーマを記述し、型が自動推論される
2. **required option は non-optional 型** -- `string` であって `string | undefined` ではない
3. **サブコマンドのディスパッチが型安全** -- discriminated union により `switch` で網羅チェック可能
4. **`get().unwrap()` が不要** -- パース成功時点で型付きオブジェクトが得られる
5. **IDE 補完が効く** -- すべてが静的型で解決され、ランタイム型チェックが不要

---

## 設計原則

- **core は変えない** -- WASM FFI で export された低レベル API をそのまま使う
- **TypeScript の型システムで DX を解決** -- conditional types / infer / template literal types / discriminated union を駆使
- **ゼロランタイムオーバーヘッド** -- 型レベルの計算はコンパイル時のみ。実行時は薄い変換のみ

---

## API 設計案

### 概要

2 つのレイヤーで構成する:

| レイヤー | 役割 |
|---|---|
| **Schema DSL** | オブジェクトリテラルでパーサスキーマを宣言。型推論の入口 |
| **Result Types** | パース結果を型安全なオブジェクトとして返す。`Infer<Schema>` で自動導出 |

### Schema DSL

```typescript
import { kuu, flag, stringOpt, intOpt, count, appendString,
         positional, rest, dashdash, sub } from "@kuu/ts";

const schema = kuu({
  description: "mygit - A sample git-like CLI built with kuu",
  requireCmd: true,

  globals: {
    verbose: count({ short: "v", description: "Increase verbosity" }),
    quiet:   flag({ short: "q", description: "Suppress output" }),
    color:   stringOpt({
      default: "auto",
      choices: ["always", "never", "auto"] as const,
      implicitValue: "always",
      description: "When to use colors",
    }),
  },
  exclusive: [["verbose", "quiet"]],

  commands: {
    clone: sub({
      description: "Clone a repository",
      options: {
        url:       positional({ description: "Repository URL", required: true }),
        directory: positional({ description: "Target directory" }),
        depth:     intOpt({ default: 0, description: "Shallow clone depth" }),
        branch:    stringOpt({ default: "", short: "b", description: "Checkout branch" }),
        bare:      flag({ description: "Create a bare repository" }),
      },
    }),
    commit: sub({
      description: "Record changes",
      options: {
        message: stringOpt({
          default: "", short: "m", required: true,
          post: ["trim", "nonEmpty"],
          description: "Commit message",
        }),
        all:    flag({ short: "a", description: "Stage all modified" }),
        amend:  flag({ description: "Amend previous commit" }),
        verify: flag({ default: true, variationFalse: "no", description: "Run hooks" }),
      },
    }),
    remote: sub({
      description: "Manage remotes",
      requireCmd: true,
      commands: {
        add: sub({
          description: "Add a remote",
          options: {
            fetch: flag({ short: "f", description: "Fetch after adding" }),
            name:  positional({ description: "Remote name" }),
            url:   positional({ description: "Remote URL" }),
          },
        }),
        remove: sub({
          description: "Remove a remote",
          options: {
            name: positional({ description: "Remote name", required: true }),
          },
        }),
      },
    }),
  },
});
```

### 型推論の仕組み

#### 1. スキーマ型から結果型を自動導出 (`Infer<S>`)

```typescript
// スキーマリテラル型から結果型を自動導出
type Result = Infer<typeof schema>;
// ↓ 以下と等価な型が推論される:
// {
//   globals: {
//     verbose: number;
//     quiet: boolean;
//     color: "always" | "never" | "auto";
//   };
//   command:
//     | { name: "clone"; options: {
//         url: string;             // required → non-optional
//         directory?: string;      // optional → string | undefined
//         depth: number;
//         branch: string;
//         bare: boolean;
//       }}
//     | { name: "commit"; options: {
//         message: string;         // required → non-optional
//         all: boolean;
//         amend: boolean;
//         verify: boolean;
//       }}
//     | { name: "remote"; command:
//         | { name: "add"; options: { fetch: boolean; name?: string; url?: string } }
//         | { name: "remove"; options: { name: string } }
//       }
// }
```

#### 2. required → non-optional 変換

```typescript
// コンビネータ定義に required: true があるかを型レベルで検査
type IsRequired<D> = D extends { required: true } ? true : false;

// required なら T, そうでなければ T | undefined
type OptValue<D, T> = IsRequired<D> extends true ? T : T | undefined;

// flag は常に boolean（required の概念なし）
// stringOpt: required → string, optional → string | undefined
// intOpt: required → number, optional → number | undefined
// positional: required → string, optional → string | undefined
// count: 常に number
// rest: 常に string[]
// dashdash: 常に string[]
// appendString: 常に string[]
// appendInt: 常に number[]
```

#### 3. choices のリテラル型推論

```typescript
// choices を as const で渡すと、リテラルユニオン型に推論される
type ChoiceValue<D> =
  D extends { choices: readonly (infer C)[] } ? C : string;

// 例: choices: ["always", "never", "auto"] as const
// → "always" | "never" | "auto"
```

#### 4. サブコマンドの discriminated union

```typescript
// commands の各キーが discriminated union の tag になる
type CommandUnion<Cmds> = {
  [K in keyof Cmds]: Cmds[K] extends SubDef<infer Opts, infer SubCmds>
    ? SubCmds extends never
      ? { name: K; options: InferOptions<Opts> }
      : { name: K; options: InferOptions<Opts>; command: CommandUnion<SubCmds> }
    : never;
}[keyof Cmds];
```

### パース実行とディスパッチ

```typescript
async function main() {
  // parse() は Result 型を返す。パースエラーは例外
  const result = await schema.parse(process.argv.slice(2));

  // globals は常にアクセス可能
  console.log(`verbose: ${result.globals.verbose}`);
  console.log(`color: ${result.globals.color}`);

  // command は discriminated union → switch で網羅チェック
  switch (result.command.name) {
    case "clone": {
      const { url, directory, depth, branch, bare } = result.command.options;
      // url: string (non-optional, required)
      // directory: string | undefined (optional)
      console.log(`Cloning ${url} depth=${depth}`);
      break;
    }
    case "commit": {
      const { message, all, amend, verify } = result.command.options;
      // message: string (non-optional, required + nonEmpty)
      console.log(`Committing: ${message}`);
      break;
    }
    case "remote": {
      // ネストした discriminated union
      switch (result.command.command.name) {
        case "add": {
          const { name, url, fetch } = result.command.command.options;
          console.log(`Adding remote ${name} -> ${url}, fetch=${fetch}`);
          break;
        }
        case "remove": {
          const { name } = result.command.command.options;
          // name: string (non-optional, required)
          console.log(`Removing remote ${name}`);
          break;
        }
      }
      break;
    }
  }
}
```

---

## Core FFI との接続

### WASM FFI レイヤー

```
+--------------------------------------------+
|  TypeScript Schema DSL                     |  <-- ユーザーが触るレイヤー
+--------------------------------------------+
|  Schema -> FFI Call Translator             |  <-- スキーマを解釈して FFI 呼び出しに変換
+--------------------------------------------+
|  WASM FFI (kuu core)                       |  <-- MoonBit -> WASM コンパイル結果
|  - parser_new() -> handle                  |
|  - parser_flag(handle, name, ...) -> id    |
|  - parser_string_opt(handle, ...) -> id    |
|  - parser_parse(handle, args) -> result    |
|  - result_get_string(result, id) -> str    |
|  - result_get_int(result, id) -> int       |
|  - result_get_bool(result, id) -> bool     |
|  - result_child(result, name) -> result?   |
+--------------------------------------------+
```

### 変換フロー

1. **Schema -> FFI 呼び出し列**: `schema.parse(args)` 時に、スキーマ定義を走査して FFI を順次呼び出す
   - `kuu({ globals: { verbose: count(...) } })` -> `parser_new()` -> `parser_count(h, "verbose", ...)`
   - 各コンビネータ呼び出しで id を受け取り、`Map<optName, id>` に保持
2. **FFI パース実行**: `parser_parse(handle, args)` で低レベルパース実行
3. **結果変換**: id マップを使って `result_get_*` 系 FFI を呼び、TypeScript オブジェクトに変換
   - `flag` -> `result_get_bool(result, id)` -> `boolean`
   - `stringOpt` -> `result_get_string(result, id)` -> `string`
   - required かつ未設定の場合は FFI 側で既にエラー（core の `required()` が処理）
   - `result.child("clone")` -> `result_child(result, "clone")` -> 子結果の再帰変換

### ID ベースの値取得

core の `Opt[T]` は `id` を持つ。WASM FFI では:
- コンビネータ登録時に id を返す
- パース後に id で値を取得する
- TypeScript 側はスキーマの各エントリに id を紐づけ、型情報に基づいて適切な getter を呼ぶ

```typescript
// 内部実装イメージ（ユーザーには見えない）
class SchemaRunner<S extends SchemaDef> {
  private optIds = new Map<string, number>();
  private wasmHandle: number;

  async parse(args: string[]): Promise<Infer<S>> {
    // 1. WASM parser 構築
    this.wasmHandle = ffi.parser_new();

    // 2. スキーマからコンビネータを順次登録
    for (const [name, def] of Object.entries(this.schema.globals)) {
      const id = this.registerOpt(this.wasmHandle, name, def);
      this.optIds.set(`global.${name}`, id);
    }
    // ... commands も再帰的に登録

    // 3. パース実行
    const rawResult = ffi.parser_parse(this.wasmHandle, args);

    // 4. 型付きオブジェクトに変換
    return this.buildResult(rawResult) as Infer<S>;
  }
}
```

---

## 型システムの詳細設計

### コンビネータ定義型

```typescript
// 各コンビネータの定義型
interface FlagDef {
  readonly kind: "flag";
  readonly default?: boolean;
  readonly short?: string;
  readonly description?: string;
  readonly variationFalse?: string;
  readonly variationTrue?: string;
  readonly variationToggle?: string;
  readonly variationReset?: string;
  readonly variationUnset?: string;
  readonly hidden?: boolean;
}

interface StringOptDef<
  C extends readonly string[] = readonly string[],
  R extends boolean = boolean,
> {
  readonly kind: "stringOpt";
  readonly default?: string;
  readonly choices?: C;
  readonly implicitValue?: string;
  readonly required?: R;
  readonly short?: string;
  readonly description?: string;
  readonly post?: readonly PostFilter[];
  readonly hidden?: boolean;
}

interface IntOptDef<R extends boolean = boolean> {
  readonly kind: "intOpt";
  readonly default?: number;
  readonly implicitValue?: number;
  readonly required?: R;
  readonly short?: string;
  readonly description?: string;
  readonly hidden?: boolean;
}

interface CountDef {
  readonly kind: "count";
  readonly short?: string;
  readonly description?: string;
  readonly hidden?: boolean;
}

interface AppendStringDef {
  readonly kind: "appendString";
  readonly short?: string;
  readonly description?: string;
  readonly hidden?: boolean;
}

interface AppendIntDef {
  readonly kind: "appendInt";
  readonly short?: string;
  readonly description?: string;
  readonly hidden?: boolean;
}

interface PositionalDef<R extends boolean = boolean> {
  readonly kind: "positional";
  readonly description?: string;
  readonly required?: R;
}

interface RestDef {
  readonly kind: "rest";
  readonly description?: string;
}

interface DashdashDef {
  readonly kind: "dashdash";
  readonly separator?: string;
}

type PostFilter = "trim" | "nonEmpty";
```

### 値型の推論

```typescript
// コンビネータ定義から値の型を推論する
type InferOptType<D> =
  D extends FlagDef         ? boolean :
  D extends CountDef        ? number :
  D extends AppendStringDef ? string[] :
  D extends AppendIntDef    ? number[] :
  D extends RestDef         ? string[] :
  D extends DashdashDef     ? string[] :
  D extends StringOptDef<infer C, infer R> ?
    (C extends readonly [] | readonly string[]
      ? (R extends true ? string : string | undefined)
      : (R extends true ? C[number] : C[number] | undefined)) :
  D extends IntOptDef<infer R> ?
    (R extends true ? number : number | undefined) :
  D extends PositionalDef<infer R> ?
    (R extends true ? string : string | undefined) :
  never;
```

### default 値による non-optional 推論

default が明示的に設定されているコンビネータは、parse 後に値が必ず存在する。
この場合も non-optional にできる:

```typescript
// default が明示的にある場合も non-optional
type HasDefault<D> =
  D extends { default: infer V } ? (V extends undefined ? false : true) : false;

type InferOptType<D> =
  D extends FlagDef ? boolean :  // flag は常に boolean（default あり前提）
  D extends CountDef ? number :  // count は常に number（default=0）
  // ...
  D extends StringOptDef<infer C, infer R> ?
    (HasDefault<D> extends true
      ? (C extends readonly [] | readonly string[] ? string : C[number])
      : (R extends true ? string : string | undefined)) :
  // ...
```

### スキーマ全体の推論

```typescript
// options マップから結果型を構築
type InferOptions<Opts extends Record<string, any>> = {
  // required / has-default のエントリ
  [K in keyof Opts as IsOptional<Opts[K]> extends true ? never : K]:
    InferOptType<Opts[K]>;
} & {
  // optional のエントリ
  [K in keyof Opts as IsOptional<Opts[K]> extends true ? K : never]?:
    Exclude<InferOptType<Opts[K]>, undefined>;
};

type IsOptional<D> =
  D extends FlagDef | CountDef | AppendStringDef | AppendIntDef | RestDef | DashdashDef
    ? false
    : D extends { required: true } ? false
    : D extends { default: infer V } ? (V extends undefined ? true : false)
    : true;

// サブコマンド → discriminated union
type InferCommand<Cmds extends Record<string, SubSchema>> = {
  [K in keyof Cmds & string]: Cmds[K] extends { commands: infer SC }
    ? SC extends Record<string, SubSchema>
      ? { name: K; options: InferOptions<Cmds[K]["options"]>; command: InferCommand<SC> }
      : { name: K; options: InferOptions<Cmds[K]["options"]> }
    : { name: K; options: InferOptions<Cmds[K]["options"]> };
}[keyof Cmds & string];

// トップレベル
type Infer<S> = S extends {
  globals: infer G extends Record<string, any>;
  commands: infer C extends Record<string, SubSchema>;
}
  ? { globals: InferOptions<G>; command: InferCommand<C> }
  : never;
```

---

## TypeScript ならではの強み

### 1. テンプレートリテラル型によるオプション名検証

```typescript
// "--" prefix の自動付与を型レベルで表現
type LongOptionName = `--${string}`;
type ShortOptionName = `-${string}`;

// exclusive で指定する名前がスキーマに存在するかを型レベルでチェック
type ValidExclusive<G extends Record<string, any>> = [keyof G & string, keyof G & string][];
```

### 2. Conditional Types による required/optional 分岐

MoonBit の core では `Opt::get() -> T?` が常に `T?` を返すが、
TypeScript ではスキーマ定義に基づいて `T` と `T | undefined` を静的に分岐できる。
これにより `get().unwrap()` パターンが完全に不要になる。

### 3. Discriminated Union によるサブコマンドディスパッチ

core の `result.child("name")` は `ParseResult?` を返し、手動で存在チェックが必要。
TypeScript では `command.name` を tag とする discriminated union により、
`switch` 文で:
- 網羅チェック（`never` で未処理のサブコマンドを検出）
- 各 case 内で options の型が自動ナロー
を実現する。

### 4. `as const` による choices のリテラル型化

```typescript
// core: choices=["always", "never", "auto"] → get() は String
// TS:   choices: ["always", "never", "auto"] as const → type は "always" | "never" | "auto"
```

これは TS 固有の機能。Go や Rust では enum 定義が必要だが、
TS ではリテラル配列がそのまま型になる。

### 5. 型レベル網羅チェック

```typescript
function exhaustive(_: never): never {
  throw new Error("unreachable");
}

switch (result.command.name) {
  case "clone": /* ... */ break;
  case "commit": /* ... */ break;
  case "remote": /* ... */ break;
  // ここで全サブコマンドを処理しないと:
  default: exhaustive(result.command);
  //                   ^^^^^^^^^^^^^^ コンパイルエラー
}
```

---

## エラーハンドリング

core の `ParseError` / `HelpRequested` を TypeScript に変換:

```typescript
class KuuParseError extends Error {
  constructor(
    public readonly message: string,
    public readonly helpText: string,
  ) {
    super(message);
  }
}

class KuuHelpRequested extends Error {
  constructor(public readonly helpText: string) {
    super(helpText);
  }
}

// parse() の戻り値型
// 成功: Infer<S>
// 失敗: KuuParseError | KuuHelpRequested を throw
```

---

## ファイル構成

```
pkg/ts/
  DESIGN.md              ... この設計書
  examples/
    mygit.ts             ... mygit サンプル（型レベルのモック）
  src/                   ... (将来の実装)
    schema.ts            ... Schema DSL + 型定義
    combinators.ts       ... flag(), stringOpt() 等のコンビネータファクトリ
    infer.ts             ... Infer<S> 型の定義
    ffi.ts               ... WASM FFI バインディング
    runner.ts            ... SchemaRunner (parse 実行)
    errors.ts            ... エラー型
    index.ts             ... re-export
```
