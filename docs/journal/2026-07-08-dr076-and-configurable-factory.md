# DR-076 (bool = 値型) と configurable factory の実装サイクル

kawaz 裁定 (bool の `:set` = 型不変の値形 / 裸発火は `:set:true` / eq + space form 両対応、
および definitions.types への int_round 適用) を spec 反映 → 実装 → 統合した記録。
main は `e8edb7c` → `840da56` (CI green、conformance 全一致 mismatches=0・skip 5)。

## 成果

- **DR-076 実装** (`510d4d4d`, sonnet5): Node::BoolArg 新設 (spine 対称アーム + complete Pending 込み)、
  inst_long の TBool を値形化 (空間形衛星 + eq-split、variant ガード撤去)、`:set:true` 裸縮退形。
  **colon-DSL 分類器 `classify_long_spelling` を harness から production へ移設** — 解釈器が
  テストハーネスにしか無かったことが alias `long_override` の DSL 未解釈ギャップ (既存バグ) の根本で、
  移設 + dec_variant 薄型化で 2 実装 drift の根を断った
- **configurable factory substrate** (`2fcc86c5`, opus47): definitions.types decode (TypeShadow、
  kuu_int_parser)、IntArg(String, RoundMode) + LongEntry/ShortEntry の int_round carry。
  **eq-split 経路の TInt が値空間判定を素通りしていた潜在バグの修正込み** (委譲時の事前指摘が的中)。
  int-round-modes 6 case 解消、decoded 110 / skip 6→5
- spec 側: DR-076 §4 追記、fixture 4 本改訂 (variant.json 新期待値 / bool-canonical +3 case /
  alias-parse 2 本の `:set:true` 移行)。bool の全 fixture を機械走査して移行漏れゼロを確認

## 相互検証の成果 (このサイクルで 3 件)

1. 実装が variant.json の旧意味論 fixture と衝突 → 裁定で仕様確定 → fixture 改訂
2. 実装の conformance 波及検出 → alias-parse 2 本の移行漏れを全数走査で特定・是正
3. DR-076 の新語彙 `:set:true` が alias long_override の **既存 DSL 未解釈バグを初めて露出** → 分類器移設で根治

## 並行運用の教訓 (メモリにも記録)

- **メッセージ交錯での誤断**: worker の正確な報告 → 古い指示への忠実な追従 (revert) → その状態を監査して
  「虚偽報告」と誤断、という連鎖が発生。撤回済み。教訓: 監査での乖離はまず**交錯で説明できないか**を
  確認してから帰責を判断する。指示には「どの報告まで見たか」を明示する
- 同一ファイル群を触る 2 タスクの並行は、先着コミット → 後発が rebase 統合、の直列化で吸収できた
  (BoolArg × IntArg(_,RoundMode) の衝突解決は後発 worker が正しく合成)
- 「完了報告の直前に fresh なテスト実行 + 実出力の貼付 (再構成禁止)」を委譲プロンプト標準に追加

## 次

- number-base-prefix-optin (残 skip 1 件): hex integer + hex float lexer (`parse_number_ext` +
  NumArg の allow_base_prefix carry)。見積 ~1.5h、batch2 の Phase 1 調査に実装プラン記載済み
- MDR-004 実装 (skip 4 件解消): codex レビュー反映済みの設計 (`docs/decisions/MDR-004-elemdef-body-grammar.md`)
- issue 追加候補: short_val の細粒 reason (Binding? → Result 拡張、batch2 指摘)
