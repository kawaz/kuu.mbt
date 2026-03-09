# DR-036: KuuCore — 各言語向け統一低レベル API 設計

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

## 実装優先度

1. TypeScript KuuCore（V8 で WASM 直接実行、最もシンプル）
2. Go / Python KuuCore（Node.js サブプロセス経由）
3. Swift KuuCore（bun サブプロセス経由）
4. 各言語の DX API（KuuCore 安定後）

## 関連 DR

- DR-027: core 純粋関数主義 + 多言語 DX レイヤー構想（本 DR の出発点）
- DR-030: opt AST の言語間ポータビリティ（KuuCore が活用する基盤）
- DR-035: WASM bridge 全機能対応（Layer 2 の完成）
