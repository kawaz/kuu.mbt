# DR-043: kuu OptAST — 公式 JSON スキーマ仕様 v2

日付: 2026-03-16
ステータス: **設計中**

## 背景

DR-030 で「opt 定義は JSON で完全に表現可能」という着想が生まれ、DR-035 で WASM bridge が JSON in/out の全機能対応を実装した。しかし現在の JSON schema (version 1) は WASM bridge の実装に合わせてアドホックに成長したもので、以下の問題がある:

1. **名前が不明瞭**: トップレベルの `"opts"` は「ノード一覧」なのか「スキーマ全体」なのか曖昧
2. **args が schema に混入**: 定義 (what to parse) と入力 (what to parse from) が同一 JSON 内
3. **型情報の欠如**: `"kind": "string"` のような文字列リテラルに依存し、拡張性が低い
4. **version 1 の暗黙ルール**: dashdash の有無でパーサの挙動が変わる等、schema からは読み取れない暗黙の仕様がある
5. **将来の拡張に非対応**: env combinator (DR-041)、clone/adjust primitive (DR-037) 等を組み込む余地がない

## 設計目標

1. **定義と実行の分離**: AST (cli 定義) と args (パース対象) を明確に分ける
2. **自己記述的**: AST JSON 単体で opt 定義を完全に理解・再現できる
3. **言語間ポータビリティ** (DR-030): Go で export → TS で import → 同一パース結果
4. **段階的拡張**: 未知のフィールドは無視、新機能は optional フィールドで追加
5. **美しさ**: 人間が読み書きする JSON としても美しい構造

## 決定

### 全体構造: Scope ベースのツリー

```
OptAST
  └─ Scope (root)
       ├─ nodes: [Node...]     ← オプション/コマンド定義
       ├─ constraints           ← 制約 (exclusive, required, ...)
       └─ meta                  ← スコープのメタ情報
```

kuu のパーサは「スコープ」単位で動く。ルートスコープがあり、サブコマンドごとに子スコープが生まれる。AST はこのスコープツリーをそのまま反映する。

### OptAST JSON 仕様

```jsonc
{
  "$schema": "https://kuu.dev/schema/v2.json",   // 将来の JSON Schema 参照
  "version": 2,
  "scope": { /* root Scope */ }
}
```

#### Scope

```jsonc
{
  // --- メタ情報 ---
  "description": "My CLI tool",
  "name": "myapp",                    // optional: コマンド名 (ルートでは省略可)

  // --- ノード定義 ---
  "nodes": [ /* Node[] */ ],

  // --- 制約 ---
  "constraints": {
    "exclusive": [["json", "yaml"]],  // 排他グループ
    "required": ["output"],           // 必須オプション
    "at_least_one": [["verbose", "debug"]],
    "require_cmd": true               // サブコマンド必須
  }
}
```

#### Node (discriminated union by `"node"` field)

全ノードの共通フィールド:

```jsonc
{
  "node": "<node-type>",        // ノード種別 (discriminator)
  "name": "verbose",            // 識別名 (--verbose の "verbose")
  "description": "Enable verbose output",
  "hidden": false,              // help 非表示
  "deprecated": "Use --debug instead"  // 非推奨メッセージ (optional)
}
```

> **なぜ `"kind"` → `"node"` に変更するか**: `"kind"` は多くの JSON スキーマで使われる汎用ワードで衝突しやすい。`"node"` は kuu の ExactNode アーキテクチャと直接対応し、kuu 固有の語彙として明確。

---

### Node 種別

#### `flag` — ブール値フラグ

```jsonc
{
  "node": "flag",
  "name": "verbose",
  "default": false,
  "shorts": ["v"],
  "aliases": ["verb"],
  "global": false,
  "variations": {
    "false": "no",          // --no-verbose
    "toggle": "toggle",     // --toggle-verbose
    "true": "with",         // --with-verbose
    "reset": "reset",       // --reset-verbose
    "unset": "unset"        // --unset-verbose
  }
}
```

#### `string` — 文字列オプション

```jsonc
{
  "node": "string",
  "name": "output",
  "default": "",
  "shorts": ["o"],
  "aliases": [],
  "global": false,
  "value_name": "FILE",         // ヘルプ表示のプレースホルダ
  "choices": ["json", "yaml", "toml"],
  "implicit_value": "json",     // --output (値省略時)
  "filter": "trim",             // プリセットフィルタ
  "variations": {}
}
```

#### `int` — 整数オプション

```jsonc
{
  "node": "int",
  "name": "port",
  "default": 8080,
  "shorts": ["p"],
  "aliases": [],
  "global": false,
  "value_name": "PORT",
  "choices": null,
  "implicit_value": null,
  "filter": { "in_range": [1, 65535] },
  "variations": {}
}
```

#### `count` — カウンタ

```jsonc
{
  "node": "count",
  "name": "verbose",
  "shorts": ["v"],
  "aliases": [],
  "global": false,
  "variations": {}
}
```

#### `string_list` — 文字列リスト (append)

```jsonc
{
  "node": "string_list",
  "name": "tag",
  "shorts": ["t"],
  "aliases": [],
  "global": false,
  "value_name": "TAG",
  "filter": null,
  "variations": {}
}
```

> **なぜ `append_string` → `string_list` か**: AST の名前は実装詳細ではなくセマンティクスを表す。`append` は「追加する」という動作の名前であり、結果の型は「文字列のリスト」。AST は宣言的なので結果型で命名する。

#### `int_list` — 整数リスト (append)

```jsonc
{
  "node": "int_list",
  "name": "num",
  "shorts": ["n"],
  "aliases": [],
  "global": false,
  "value_name": "NUM",
  "filter": null,
  "variations": {}
}
```

#### `positional` — 位置引数

```jsonc
{
  "node": "positional",
  "name": "file",
  "greedy": false
}
```

#### `rest` — 残り全引数

```jsonc
{
  "node": "rest",
  "name": "args",
  "stop_before": ["--"]
}
```

#### `separator` — セパレータ (`--`)

```jsonc
{
  "node": "separator",
  "separator": "--",
  "stop_before": []
}
```

> **なぜ `dashdash` → `separator` か**: `--` はデフォルトだが、`separator` にすることで将来的に別のセパレータ文字列にも対応できる。実際 core には `separator` パラメータがある。

#### `group` — 位置引数グループ (serial)

```jsonc
{
  "node": "group",
  "greedy": false,
  "nodes": [
    { "node": "positional", "name": "src" },
    { "node": "positional", "name": "dst" }
  ]
}
```

> **なぜ `serial` → `group` か**: `serial` は実装のパース戦略名。AST では「これらを一まとめにする」という構造を表すので `group` が適切。

#### `command` — サブコマンド

```jsonc
{
  "node": "command",
  "name": "serve",
  "aliases": ["s"],
  "scope": {
    "description": "Start the server",
    "nodes": [
      { "node": "string", "name": "host", "default": "localhost" },
      { "node": "int", "name": "port", "default": 8080 }
    ],
    "constraints": {}
  }
}
```

サブコマンドは子スコープを持つ。再帰的にネスト可能。

---

### Filter (プリセット後処理)

JSON 表現可能なフィルタのみ。ホスト言語の任意クロージャは AST に含めない（DR-035 の方針通り）。

```jsonc
// 単一フィルタ
"filter": "trim"
"filter": "non_empty"
"filter": "to_lower"

// パラメータ付きフィルタ
"filter": { "in_range": [0, 65535] }
"filter": { "one_of": ["debug", "info", "warn", "error"] }

// フィルタチェーン (順序付き合成)
"filter": [
  "trim",
  "to_lower",
  "non_empty"
]

// null / 省略 = フィルタなし
"filter": null
```

フィルタチェーンは `FilterChain.then()` の AST 表現。配列で順序付き合成を表す。

---

### Variations

variations は各ノードの optional フィールド。省略時はバリエーションなし。

```jsonc
"variations": {
  "false": "no",          // False(prefix) → --no-{name}
  "toggle": "toggle",     // Toggle(prefix) → --toggle-{name}
  "true": "with",         // True(prefix) → --with-{name}
  "reset": "reset",       // Reset(prefix) → --reset-{name}
  "unset": "unset"        // Unset(prefix) → --unset-{name}
}
```

各キーは Variation enum のバリアント名（小文字）に対応。値は prefix 文字列。

---

### Environment Variable (DR-041 への布石)

将来の env combinator を見据えたフィールド。v2 では metadata only（ヘルプ表示用）。

```jsonc
{
  "node": "string",
  "name": "port",
  "default": "8080",
  "env": "PORT",
  // 将来: env_priority, env_prefix 等
}
```

`"env"` フィールドは全 value 系ノードで使用可能。

---

### v1 → v2 マイグレーション対応表

| v1 | v2 | 変更理由 |
|---|---|---|
| `"kind"` | `"node"` | kuu 固有語彙、他スキーマとの衝突回避 |
| `"append_string"` | `"string_list"` | セマンティクス命名 (動作 → 結果型) |
| `"append_int"` | `"int_list"` | 同上 |
| `"dashdash"` | `"separator"` | 汎用化 |
| `"serial"` | `"group"` | 構造名 (実装戦略名 → 宣言的名前) |
| `"post"` | `"filter"` | 機能の正確な表現 + チェーン対応 |
| `"variation_false": "no"` | `"variations": { "false": "no" }` | 構造化 |
| `"shorts": "vo"` | `"shorts": ["v", "o"]` | 配列で明示的 |
| トップレベル `"opts"` + `"args"` | `"scope"` のみ (args 分離) | 定義と実行の分離 |

---

### 完全な例: git-like CLI

```json
{
  "$schema": "https://kuu.dev/schema/v2.json",
  "version": 2,
  "scope": {
    "name": "git",
    "description": "The stupid content tracker",
    "nodes": [
      {
        "node": "flag",
        "name": "version",
        "description": "Print version",
        "shorts": ["v"]
      },
      {
        "node": "string",
        "name": "git-dir",
        "default": "",
        "description": "Set the path to the repository",
        "value_name": "PATH",
        "global": true
      },
      {
        "node": "command",
        "name": "clone",
        "scope": {
          "description": "Clone a repository into a new directory",
          "nodes": [
            {
              "node": "string",
              "name": "branch",
              "default": "",
              "shorts": ["b"],
              "description": "Checkout branch instead of HEAD",
              "value_name": "BRANCH"
            },
            {
              "node": "int",
              "name": "depth",
              "default": 0,
              "description": "Create a shallow clone",
              "filter": { "in_range": [0, 2147483647] }
            },
            {
              "node": "flag",
              "name": "bare",
              "description": "Make a bare repository"
            },
            {
              "node": "group",
              "nodes": [
                { "node": "positional", "name": "repository" },
                { "node": "positional", "name": "directory" }
              ]
            }
          ],
          "constraints": {
            "required": ["repository"]
          }
        }
      },
      {
        "node": "command",
        "name": "commit",
        "aliases": ["ci"],
        "scope": {
          "description": "Record changes to the repository",
          "nodes": [
            {
              "node": "string",
              "name": "message",
              "default": "",
              "shorts": ["m"],
              "description": "Use the given message as the commit message",
              "value_name": "MSG"
            },
            {
              "node": "flag",
              "name": "all",
              "shorts": ["a"],
              "description": "Stage all modified files"
            },
            {
              "node": "flag",
              "name": "amend",
              "description": "Amend the previous commit"
            }
          ]
        }
      },
      {
        "node": "command",
        "name": "log",
        "scope": {
          "description": "Show commit logs",
          "nodes": [
            {
              "node": "int",
              "name": "max-count",
              "default": -1,
              "shorts": ["n"],
              "description": "Limit the number of commits",
              "value_name": "NUMBER"
            },
            {
              "node": "flag",
              "name": "oneline",
              "description": "Condense each commit to a single line"
            },
            {
              "node": "string",
              "name": "format",
              "default": "",
              "description": "Pretty-print in given format",
              "choices": ["oneline", "short", "medium", "full", "fuller", "email", "raw"],
              "implicit_value": "medium"
            },
            {
              "node": "separator"
            },
            {
              "node": "rest",
              "name": "paths"
            }
          ]
        }
      }
    ],
    "constraints": {
      "require_cmd": true
    }
  }
}
```

---

### WASM Bridge 統合: 実行時 JSON

AST (定義) と実行 (パース) は分離する。WASM bridge の入力は以下の形式:

```jsonc
{
  "ast": { /* OptAST (version 2) */ },
  "args": ["clone", "--depth", "1", "https://github.com/user/repo"]
}
```

あるいは AST を事前にロードし、args のみを渡す 2-call パターン:

```
1. kuu_load(ast_json) → schema_id
2. kuu_parse(schema_id, args_json) → result_json
```

v2 bridge は v1 との後方互換を維持する。`"version": 1` は従来通り処理し、`"version": 2` で新形式を使う。

---

### ParseResult JSON (出力側)

出力形式は v1 から変更なし。入力 AST の構造変更は出力には影響しない。

```jsonc
// 成功
{
  "ok": true,
  "values": {
    "version": false,
    "git-dir": ""
  },
  "command": {
    "name": "clone",
    "values": {
      "branch": "main",
      "depth": 1,
      "bare": false,
      "repository": "https://github.com/user/repo",
      "directory": ""
    }
  }
}

// エラー
{
  "ok": false,
  "error": "required option missing: --repository",
  "help": "..."
}

// ヘルプ
{
  "ok": false,
  "help_requested": true,
  "help": "..."
}
```

---

### デフォルト値の規則

各ノード種別のデフォルト:

| node | default の型 | 省略時 |
|---|---|---|
| `flag` | `boolean` | `false` |
| `string` | `string` | `""` |
| `int` | `number` | `0` |
| `count` | — (常に 0 開始) | — |
| `string_list` | — (常に `[]` 開始) | — |
| `int_list` | — (常に `[]` 開始) | — |
| `positional` | — | — |
| `rest` | — | — |

`default` フィールドが省略された場合、上記の値を使用する。

---

### Optional フィールドの規則

**省略可能**: description, hidden, deprecated, shorts, aliases, global, variations, env, filter, value_name, choices, implicit_value, greedy, stop_before, separator

**必須**: `node`, `name` (separator, group を除く)

省略時のデフォルト:
- `description`: `""`
- `hidden`: `false`
- `global`: `false`
- `shorts`: `[]`
- `aliases`: `[]`
- `variations`: `{}` (なし)
- `greedy`: `false`
- `separator`: `"--"`
- `stop_before`: `[]`

---

### 拡張ポイント

#### Custom ノード (ホスト言語連携)

```jsonc
{
  "node": "custom",
  "name": "port",
  "type_hint": "int",         // ホスト言語へのヒント
  "default": "8080",          // 文字列で保持 (parse はホスト側)
  "value_name": "PORT",
  "description": "Server port number"
}
```

`custom` ノードは AST 上は `string` として扱われ、KuuCore (DR-036) のコールバック中継でホスト言語のパーサに委譲される。`type_hint` はホスト言語の DX レイヤーがどの型に変換すべきかのヒント。

#### 将来の拡張候補

| フィールド | 対象 | DR |
|---|---|---|
| `env_source` | value 系ノード | DR-041 |
| `env_prefix` | scope | DR-041 |
| `link_to` | alias の AST 表現 | DR-037 |
| `adjust` | フィルタ挿入の AST 表現 | DR-037 |
| `conflicts_with` | constraints | — |
| `depends_on` | constraints | — |
| `section` | ヘルプのセクション分け | — |

これらは v2 schema に optional フィールドとして段階的に追加可能。`version: 2` の範囲で後方互換に拡張する。

---

## 設計判断の記録

### なぜ `"node"` discriminator か

**選択肢**:
1. `"kind"` — v1 互換、一般的
2. `"type"` — 型を表す一般語
3. `"node"` — kuu 固有

**選択**: `"node"`。理由:
- `"kind"` は JSON Schema, GraphQL, protobuf 等で多用され衝突リスク高
- `"type"` も同様 (TypeScript の `type` フィールド等)
- kuu の内部モデルは ExactNode ベース。`"node"` はそのまま対応
- AST の各要素が「ノード」であるという語彙が自然

### なぜ append → list 命名か

**v1**: `append_string`, `append_int` — 動作名 (「値を追加する」)
**v2**: `string_list`, `int_list` — 結果型名 (「文字列のリスト」)

AST は宣言的定義。「何をするか」ではなく「何であるか」を表す。`--tag a --tag b` の結果は `["a", "b"]` という文字列リスト。ユーザーが AST を手書きするとき `"node": "string_list"` の方が意図が明確。

### なぜ shorts を配列に変更か

**v1**: `"shorts": "vo"` — 文字列 (各文字がショートオプション)
**v2**: `"shorts": ["v", "o"]` — 配列

理由:
- 文字列は「1文字ずつ分割」という暗黙のルールに依存
- 配列は要素が明示的。JSON としても自然
- 将来マルチバイト short (非 ASCII) に対応する余地が生まれる
- 実装上の変換コストは微小

### なぜ定義と実行を分離するか

v1 では `"opts"` と `"args"` が同一 JSON に混在していた。これは WASM bridge の「1回の呼び出しで完結」という実装都合。

AST としては定義と入力を分離すべき:
- **再利用性**: 同一 AST を異なる args で複数回パースできる
- **export/import**: AST だけを JSON ファイルとして保存・共有
- **テスト**: AST 固定 + args を変えてテストケースを量産
- **ドキュメント生成**: args 不要で AST からヘルプ/man page を生成

WASM bridge は v1 互換の 1-call (`{ opts, args }`) と v2 の 2-call (`load` + `parse`) の両方をサポートする。

## 関連 DR

- DR-027: core 純粋関数主義 + 多言語 DX レイヤー
- DR-029: Serialize/Deserialize 設計構想 (本 DR で具体化)
- DR-030: opt AST の言語間ポータビリティ (本 DR で仕様化)
- DR-035: WASM bridge 全機能対応 (v1 schema の出典)
- DR-036: KuuCore 統一 API (本 AST を消費する層)
- DR-037: clone/link/adjust primitive (将来の AST 拡張)
- DR-041: 環境変数 combinator (将来の AST 拡張)
