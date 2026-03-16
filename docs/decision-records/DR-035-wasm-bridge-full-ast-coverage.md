# DR-035: WASM bridge 拡張 — JSON 表現可能な全機能の対応

type: decision

日付: 2026-03-09
ステータス: **完了**

## 背景

DR-033 で WASM bridge の制限事項を整理し、一部の機能を「ホスト言語側で対処が自然」と分類した。しかし DR-030 の opt AST ポータビリティの思想に基づけば、JSON で表現可能なものは全て bridge 側で対応すべき。

「ホスト言語側の方が柔軟」は事実だが、bridge 側で対応すれば定義の移植性が上がり、各言語での再実装コストが消える。

## 決定

**custom[T] と任意クロージャ（post, pre）以外の全機能を WASM bridge で対応する。**

### JSON 表現可能 → bridge 側で対応

| 機能 | JSON 表現 | コア対応 | bridge 対応 |
|---|---|---|---|
| variations | `"variation_false": "no"` 等 | 済 | 要追加 |
| command aliases | `"aliases": ["b"]` | 要追加 | 要追加 |
| exclusive | `"exclusive": [["opt1", "opt2"]]` | 済 | 要追加 |
| required | `"required": ["opt1"]` | 済 | 要追加 |
| require_cmd | `"require_cmd": true` | 済 | 要追加 |
| implicit_value | `"implicit_value": "always"` | 済 | 要追加 |
| dashdash | `"kind": "dashdash"` | 済 | 要追加 |
| serial | positional 配列を serial で消費 | 済 | 要追加 |
| プリセット post | `"post": {"in_range": [0, 9]}` 等 | 済 | 要追加 |

### JSON 表現不可 → ホスト側 DX ラッパーで解決

| 機能 | bridge での扱い | DX ラッパーでの解決 |
|---|---|---|
| custom[T] | string_opt として載せる | パース結果を受け取り、ホスト側の parse 関数で T に変換 |
| 任意 post/pre フィルタ | プリセット以外は省略 | パース結果を受け取り、ホスト側の関数で後処理 |

これらは「bridge の制約」ではなく「DX ラッパーの責務」。ホスト言語のDXラッパーが「パースは WASM、変換/検証はホスト」の2段階パイプラインを組むことで、ユーザーからはシームレスに見える。プリセット post（trim, non_empty, in_range 等）は bridge 側で処理し、任意クロージャはホスト側で処理する自然な分担となる（DR-027 の多言語DX戦略の具体的実現形態）。

### 設計方針

- schema version は 1 のまま後方互換で拡張（新フィールドは全て optional）
- プリセット post は名前ベース: `"trim"`, `"non_empty"`, `{"in_range": [min, max]}`, `{"one_of": [values]}`
- exclusive/required はトップレベル配列で宣言。opt name で参照し、bridge 内部で OptRef マップから解決
- command aliases はコア側の cmd/sub に aliases パラメータ追加が必要（options と同じパターン）

## JSON schema 拡張

### variations（各 opt 定義内）

```json
{
  "kind": "flag",
  "name": "wall",
  "variation_false": "no",
  "variation_toggle": "toggle",
  "variation_true": "force",
  "variation_reset": "reset",
  "variation_unset": "unset"
}
```

### command aliases（command 定義内）

```json
{
  "kind": "command",
  "name": "build",
  "aliases": ["b"]
}
```

### exclusive / required（トップレベルまたは command 内）

```json
{
  "opts": [...],
  "exclusive": [["shared", "static"], ["m32", "m64"]],
  "required": ["filename"]
}
```

### implicit_value（string/int 定義内）

```json
{
  "kind": "string",
  "name": "color",
  "default": "auto",
  "implicit_value": "always"
}
```

### dashdash（kind として）

```json
{ "kind": "dashdash" }
```

### serial（positional のグルーピング）

```json
{
  "kind": "serial",
  "opts": [
    { "kind": "positional", "name": "src" },
    { "kind": "positional", "name": "dst" }
  ]
}
```

### プリセット post フィルタ

```json
{ "kind": "int", "name": "verbosity", "default": 0, "post": { "in_range": [0, 9] } }
{ "kind": "string", "name": "name", "default": "", "post": "trim" }
{ "kind": "string", "name": "name", "default": "", "post": "non_empty" }
```

## 実装フェーズ

### Phase 1: パラメータ透過（bridge のみ）
- variations (flag, string_opt, int_opt, count, append_string, append_int)
- implicit_value (string_opt, int_opt)
- dashdash kind
- require_cmd

### Phase 2: 制約サポート（bridge のみ）
- exclusive (OptRef マップで name → is_set を解決)
- required (同上)

### Phase 3: コア拡張 + bridge
- command aliases (core の cmd/sub に aliases 追加 → bridge 透過)

### Phase 4: 高度な機能（bridge のみ）
- serial (positional のグルーピング)
- プリセット post フィルタ (in_range, trim, non_empty)

## 関連 DR

- DR-027: core 純粋関数主義 + 多言語 DX レイヤー構想
- DR-030: opt AST の言語間ポータビリティ
- DR-033: WASM bridge 制限事項（この DR で方針を更新）
