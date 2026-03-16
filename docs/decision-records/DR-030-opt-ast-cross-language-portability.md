# DR-030: opt AST の言語間ポータビリティ

type: research

## 背景

DR-027 で「core は純粋関数ベースの薄いパースエンジン」「各言語で DX レイヤーを提供」という方針が決まった。ここで opt コンビネータの定義を AST として JSON export/import できれば、言語を跨いだパース定義の再利用が可能になるのではないかという着想が生まれた。

## 着想

Go の DX ライブラリで構築した opt AST を JSON export し、別言語（例: Node.js）でそのまま import してパースできる:

```bash
# Go アプリが自身の opt 定義を export
myapp opt-export > git.json

# その JSON だけで Node.js から即パース
node -e 'console.log(JSON.stringify(kuu.parse(process.args, kuu.importOpt("git.json")), null, 2))' -- worktree list --help
```

## 決定

### opt コンビネータ定義は JSON で完全に表現可能

opt の定義は本質的に純粋なデータ記述であり、実行時ロジックを含まない:

- 名前（long / short / aliases）
- 型（string / int / bool / count）
- デフォルト値
- 制約（required, choices, conflicts_with, depends_on）
- サブコマンド構造のツリー
- ヘルプテキスト（description, section）

### パースエンジンは言語非依存

kuu core は MoonBit → WASM にコンパイルされるため、JSON in → JSON out の純粋関数として動作できる:

```
opt AST (JSON) + args (string[])
        ↓
   kuu core (WASM)
        ↓
   ParseResult (JSON)
```

### 動的部分は型システムがガイドする

`default_fn` や `post` フィルタなどのクロージャは JSON で表現できないが、これは制約ではなく **型システムによるガイド付き組み立て** として機能する:

```typescript
// JSON import → 静的部分はすべて復元済み
const opt = importOpt<GitOpts>("git.json");

// 動的部分は undefined → 型エラーで「ここを埋めて」と伝わる
opt.username.default_fn = () => process.getuid().toString();
opt.log_level.post = (v) => v.toUpperCase();
```

- T がサポート対象型（プリミティブ + Map/List 等）であれば、型情報まで完全に再現される
- クロージャのスロットは `undefined` として残り、型システムが実装を要求する
- CLI 引数定義の大半はプリミティブ型 + ビルトイン制約で完結し、動的部分の後付けは少数

## ユースケース

1. **言語間ポータビリティ**: Go で定義 → TS / Py / Swift で即パース
2. **シェル補完の自動生成**: opt AST JSON からどの言語の補完スクリプトも生成可能
3. **ドキュメント生成**: opt AST → man page / markdown を自動生成
4. **言語非依存 E2E テスト**: opt AST + テストケース JSON でパーサのテストが言語を問わない
5. **既存 CLI の模倣**: 誰かが `git.json` を書けば、全言語で git 互換パースが手に入る

## 選択理由

- DR-027 の「core は純粋関数」方針の自然な帰結
- opt 定義にクロージャや実行時ロジックが混入しない現設計だからこそ実現可能
- WASM ベースの core が JSON in → JSON out で動作する設計と整合
- 既存の設計に阻害要因がなく、将来自然に拡張可能

## 発見経緯

DR-027（多言語 DX 戦略）の議論から、opt AST を JSON export すれば定義言語とパース実行言語を完全に分離できることに気づいた。
