---
type: implementation
---

# DR-056: WASM bridge 機能ギャップ解消

## 背景

DR-051 で指摘された WASM bridge の未対応機能4件を実装する。

## 対象機能（複雑度順）

### 1. env（環境変数 Phase 2）

JSON スキーマに `"env"` フィールドを追加し、`parser.parse(args, env~)` に渡す。

```json
{ "env": { "DEBUG": "1", "HOME": "/home/user" } }
```

実装: kuu_parse 内で `obj.get("env")` → `Map[String, String]` を構築 → `parser.parse(args, env~)` に渡すだけ。

### 2. at_least_one（最低1つ必須制約）

exclusive と同じ形式。

```json
{ "at_least_one": [["filter", "format"]] }
```

実装: exclusive のコードをコピーして `parser.at_least_one(refs)` に変更。

### 3. requires（依存制約）

```json
{ "requires": [{ "source": "key_file", "target": "output" }] }
```

実装: scope_json から配列取得 → opt_refs から OptRef 解決 → `parser.requires(target, source~)` 呼び出し。

### 4. deprecated（非推奨別名）

```json
{ "kind": "deprecated", "name": "old-flag", "target": "new_flag", "msg": "Use --new-flag" }
```

実装: opts の処理を2パス化。Pass 1 で通常 opt を登録、Pass 2 で deprecated を処理（target の OptRef が確定済み）。

## テスト

各機能について test.mjs にテストケース追加。
