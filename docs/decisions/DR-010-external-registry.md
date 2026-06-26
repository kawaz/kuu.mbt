# DR-010: 外部レジストリの階層化 (コア/標準/拡張) と暗黙参照

## 決定

実装の責務を AST 外の独立したレジストリで提供する:

| レジストリ | 役割 |
|---|---|
| `types` | 値型 (parse / accumulator / filters のデフォルト等) |
| `filters` | フィルタチェーン要素 |
| `accumulators` | 集約戦略 (override/append/set/map/mergeable...) |
| `handlers` | command の実行フック (run/action) |
| `envProvider` | 環境変数解決 |
| `completers` | 動的補完生成 |
| `defaultFns` | デフォルト値の動的生成 |

AST 上では **フィールド名でレジストリが暗黙決定**:

```json
{
  "type": "int",              // → types["int"]
  "filters": ["trim"],         // → filters["trim"]
  "multiple": {"onRepeat": "append"},  // → accumulators["append"]
  "env": "PORT"                // → envProvider
}
```

組み込みは3階層:
- **コア**: 言語実装に絶対必要な最小セット (常に同梱)
- **標準**: よく使う機能 (デフォルト同梱、opt-out 可)
- **拡張**: 特定ユースケース (デフォルト未登録、明示 import が必要)

## 経緯

設計の動機:

1. **クロージャを AST に持たせない**: filter/parse/handler などはクロージャだから、JSON にシリアライズ不能
2. **言語間相互運用**: 同じ AST を別言語で動かしたい
3. **bundle size の最適化**: 使わない機能は最終バイナリから外したい (tree-shake 友好)

kawaz の整理:
> kuuで粗方の想定実装は持っておいてそれらは明示的に注入せずとも使えると便利かなその辺は各言語でどうするとどう効くかの研究も必要かもだが。または取り敢えず注入なしで一度ASTパースをテストまたは実実行するとこれとこれとこれをこう注入する記述を追記しろとランタイムエラーでヒント出して人もAIも即対応出来る誘導を落とし所にするのもあり

→ **ゼロ設定で動く + 必要なら注入差し替え** という二段構え。

## 段階的な利用感

### Level 0: ゼロ設定

```typescript
const parser = kuu(astJson);
parser.parse(args);
```

組み込みレジストリ (コア + 標準) が自動で参照される。

### Level 1: ランタイムエラーで誘導

未登録の参照に対して:
```
RuntimeError: Type "my-uuid" is not registered.

Hint: Register a custom type:
  kuu(ast, { types: { "my-uuid": { parse: (s) => ... } } });
```

`kuu.diagnose(ast)` で AST 走査時に未実装を全列挙する仕組みも提案。

### Level 2: 明示的注入

```typescript
kuu(ast, {
  types: { "my-uuid": uuidType },
  filters: { custom_filter: myFilter },
  handlers: { serve: serveHandler }
});
```

### Level 3: tree-shake 重視

```typescript
import { kuu } from "kuu/core";
import { string, number } from "kuu/types";
import { trim, non_empty } from "kuu/filters";

const parser = kuu(ast, {
  types: { string, number },
  filters: { trim, non_empty }
});
```

bundler が使ってない実装を bundle に含めない。

## 拡張機能の opt-in

`mergeable` (DR-023 のマージリスト) のような大物機能は:
- デフォルトでは未登録
- 使う AST だと、エラー誘導で「`import { mergeable } from "kuu/extended/accumulators"` で登録してください」と表示
- 明示 import すれば bundle に入る、しなければ入らない

これで「**機能ごとに opt-in な組み込み**」が実現される。

## tree-shake 戦略は各言語 DX の責務

各言語で実装方法が違う:
- TS/JS: ESM tree-shake, `sideEffects: false`
- Rust: cargo features
- Go: サブパッケージ
- Python: lazy import

AST 仕様は「外部レジストリ参照を許す」「組み込みレジストリの名前リストを規定」までで、tree-shake 自体は各 DX で工夫。

## 関連

- DR-001 (UsefulAST のクロージャを JSON で `$required` に)
- DR-005 (type registry の責務)
- DR-009 (filter registry のデフォルト)
