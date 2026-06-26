# DR コーパス クリーンナップ runbook

DESIGN.md + 多数の DR が積み上がった状態で、覆された旧仕様・「未確定」「TBD」「保留」マーカー・history narrative が蓄積したときに、現役仕様のみを残す形に整理する手順。

> **適用前提**: DR ファイル多数 (10件超〜) + DESIGN.md 等の現役仕様書がある repo。
> 単一ファイル内のゴミ除去だけならこの runbook は重い (= 手で直す)。

## トリガ (このフロー実行を検討すべきタイミング)

### 発話パターン: ドキュメントの正確さ・古さを気にしている文脈

下記の話題が口に上った時、ユーザは **ドキュメントの正確さや古さを気にしている** ことが多い。
即実行ではなく、まず Phase 1 (= grep ベース禁止語スキャン) を先に走らせて状況確認、汚れがあれば本フロー発動を提案する:

- **docs-structure 系**: 「docs-structure 準拠」「skill 通りに整える」「規約に従って」「ルール違反になってる」「naming convention」「整合性」「準拠」
- **ドキュメント整理系**: 「ドキュメント整理」「INDEX 見直し」「DR の置き場所」「リネームしたい」「ファイル構成変えたい」「再構成」
- **判断記録の見直し系**: 「DR が古い」「決定の根拠が今と違う」「実装と乖離してる」「方針変わったから書き直し」
- **ハンドオフ文書系**: 「session log」「handoff」「CONTEXT で」「以前のセッションで」
- **明示的な負債言及**: 「未確定が溜まってる」「保留が残ってる」「古い情報が残ってる」「`[[no-historical-noise]]` 違反」「`[[design-priority]]` 違反」

### 機械的検出 (= 提案ベースで発火)

下記が grep で複数ヒットした時点で「整理しませんか?」を提案候補:

- 各 DR の末尾に「未確定」「## 後続セッションへの宿題」「## 未決 (open)」「## 残る作業」が複数累積
- DESIGN.md / 仕様書に「(未確定)」「TBD」「論点 X」等の参照が散在
- 議論セッション数回後で覆された決定の旧記述が宙ぶらりんに残置

### 発火しない時 (= 静観)

- ユーザが現役の DR を読んで議論を進めている最中 (= 整理タイミングではない、思考の流れを邪魔する)
- 1〜2 ファイルの軽微な手直しで済む話 (= 手で直す、runbook 重い)
- まだ覆されてない最新の DR を書いてる最中 (= 凍結を急がない)

## 原則 (ユーザ確定方針、勝手に変えない)

- **「バッサリ綺麗に。ゴミは尊重不要。ただし取りこぼし・削り過ぎには注意」**
- **「古い記述を残すなら明示的に否定すべし」** (= 暗黙の生きてる風が最も有害)
- **「全否定だらけならファイル単位 archive」** (= `decisions/archive/` へ)
- **「部分否定なら同一ファイル内に Superseded セクションを末尾分離」** (上半分は現役、下半分は歴史)
- **DR 間の「Updated by DR-Y」訂正ノートは入れない** (= history narrative の挿入は逆行)
  - 例外: 文脈上誤読リスクが極めて高いケース (DR-028 冒頭 blockquote のような明示撤回パターン)
- **DESIGN.md = 現役仕様の単一ソース** / **各 DR = 時点記録** という分業を守る
- **journal/handoff 文書を「live agenda」として機能させない** (削除候補)

## 全体フロー (4 phase + 検証)

```
Phase 1: 棚卸し (Survey)
  ├─ 全コーパス通読 + 観点別並列スキャン
  └─ 「現役 / 部分否定 / 全否定」分類 + 検出リスト

Phase 2: クリーンナップ案生成 (Generate)
  ├─ DESIGN.md / INDEX.md 全面書き直し案
  ├─ 各 DR の新 new_content 案 (verdict 別)
  └─ adversarial verify (削り過ぎ・取りこぼし検出)

Phase 3: 案の修正 (Fix)
  └─ verify 指摘 (critical / medium) を反映した最終案
     ※ critical は 1 件でも残せば即時手当て、medium は判断

Phase 4: 適用 (Apply)
  ├─ ファイル書き込み
  ├─ journal 等の削除
  ├─ jj describe + jj new で固定
  └─ bookmark 更新

検証 (Final-verify):
  ├─ grep ベース禁止語検出 (Superseded セクション内は許容)
  └─ 削り過ぎ目視チェック (主要 DR を 2〜3 件サンプリング)
```

## Phase 1: 棚卸し

### 観点 (並列分割)

1. **DESIGN.md / 現役仕様書**: 「未確定」「TBD」「保留」「論点 X」「覆された旧仕様」「現役と乖離した記述」を全行通読
2. **DR-001〜N の前半**: 「## 採用しなかった案」「## 残る作業」「## 後続セッションへの宿題」「## 未決」セクション、覆された記述
3. **DR-N+1〜M の後半** (= 直近セッション): 同上 + 最新 DR が前段を覆している箇所
4. **journal / handoff 文書**: 削除/保持/書き直しの判定
5. **cross-ref**: DR 間の双方向リンク漏れ、INDEX 整合性、外部リポへの dead link

### 検出すべき禁止語 (grep 一覧)

```
最長一致           ← DR-038 で廃止語
serial             ← DR-027 で廃止語、seq が canonical
children でスコープ ← DR-025/033 で訂正、name 説が正
AST-SPEC / AST-SPEC.md ← DESIGN.md にリネーム済
CONTEXT.md / 論点 [A-M] ← journal 削除予定
TBD / (未確定) / 要確定 / 保留
## 後続セッションへの宿題 / ## 未決 (open) / ## 残る作業
camelCase フィールド名 (現役記述として書かれている場合)
バージョン番号付き注釈 (例: v0.X.Y で確認)
未来予告マーカー: 「実装時に確定」「別 DR で確定する」「実装段階で詰める」
```

これらは **「Superseded セクション内 = 許容」「現役記述の上半分に残存 = critical」** で判定する。

### 判定区分

| 区分 | 条件 | 処遇 |
|---|---|---|
| **active** | DR の判断が現状でも有効、削除や注記は不要 | そのまま (本文の旧用語のみ grep 補正) |
| **partial** | DR の一部が覆されたが核となる判断は今も有効 | 末尾に `## Superseded (歴史)` セクション分離 |
| **full** | DR 全体が覆された / 議論ログの体 (判断記録になっていない) | `decisions/archive/` へファイル移動 (番号維持) |

迷ったら active or partial に倒す (削り過ぎ防止)。full は本当に全否定でないと当てない。

## Phase 2: クリーンナップ案生成

### DESIGN.md / INDEX.md (high effort で1 agent)

- DESIGN.md は新最新 DR を反映した状態に **全面書き直し**
- 「未確定」「TBD」「保留」「論点 X」参照を全削除
- 旧用語を新用語へ (例: 最長一致 → 完全経路の一意性 / bounded path-search)
- INDEX.md は active/partial verdict を含めず、関係性ラベル (`updated by` / `reorganized by` 等) のみ統一フォーマットで
- 「議論経緯」「反省パターン」のような history narrative セクションは削除

### 各 DR (verdict 別、pipeline 並列)

- **active**: 旧用語の grep 補正のみ。Phase1 案が問題なければそのまま
- **partial**:
  - 本文上部は現役の核だけ残す (元の Why は判断根拠なので保持優先)
  - 末尾に `## Superseded (歴史)` セクションを設ける
  - **統一フォーマット**: `> **更新: DR-NNN により本 DR の <対象部分> が <新方針> に変更。本 DR の <現役部分> は引き続き有効。**`
  - 覆された箇所は本文から **削除でなく Superseded へ移動** (情報を保持)
- **full**: `decisions/archive/` へファイル移動 (本文編集なし)

### Superseded セクションのテンプレ

```markdown
## Superseded (歴史)

> 以下の記述は後続 DR で覆された。現役仕様の理解には不要、判断経緯としてのみ残す。

### <要点> (DR-XXX で更新)

> **更新: DR-XXX により <対象部分> が <新方針> に変更。本 DR の <現役部分> は引き続き有効。**

<元本文から移してきた覆された記述>
```

### 外部リポへの参照

`[external: <repo> DR-NNN]` でアノテートして残す (削除しない)。例:

```
- [external: kuu.mbt DR-042] struct-first DX (本リポではない、kuu.mbt main の DR)
```

### 「未来予告」「保留」の扱い

- 「実装時に確定」「別 DR で詰める」は単独残置 = 未来予告マーカー違反
- **明示否定形式**で書く: 「本 DR では <X> を確定しない。<X> の具体規則は本 DR の射程外。」
- ふわっと「TBD」「保留」と残すのは禁止 = 削除 or 明示否定形式へ

## Phase 3: 案の修正 (verify 指摘反映)

Phase 2 で adversarial verify を 3 視点並列で回す:

1. **削り過ぎ検出** (現役 Why が削られていないか)
2. **用語整合性** (snake_case / seq / name でスコープ / bounded path-search 等の一貫性)
3. **Superseded セクションの精度** (本当に覆された箇所だけを切り出しているか)

各 verify で critical / high / medium / low を分類。critical は必ず手当て、medium は判断、low は確認のみ。

### よくある verify 指摘パターン

- **未来予告マーカー残存**: 明示否定形式へ書き換え
- **camelCase が決定本文に残存**: ヘッダ案内 (= 「本 DR の JSON 例は制定時 camelCase、現役 snake_case は末尾 Superseded 参照」) または書き換え
- **外部 dead link**: `[external: repo DR-NNN]` でアノテート
- **AST-SPEC.md 等のリネーム済参照**: 現役名 (DESIGN.md) へ置換

### workflow 設計の注意 (= 過去の罠)

- **verify agent に new_content を必ず embed すること** (= refer-only にすると入力欠如で空回り、Phase1 でやらかしたバグ)
- 大量ファイルは scratchpad のファイルに保存して agent が Read できるパスを渡す方が token 効率良い

## Phase 4: 適用

```bash
# 1. 全 final new_content を scratchpad に保存しておく
# 2. ファイル書き込み (cp で一括)
cp $SCRATCH/cleanup-final/DESIGN.md docs/DESIGN.md
cp $SCRATCH/cleanup-final/INDEX.md docs/decisions/INDEX.md
cp $SCRATCH/cleanup-final/decisions/*.md docs/decisions/

# 3. journal 削除 (= live agenda として機能してしまう文書)
rm -f docs/journal/<file>.md
rmdir docs/journal/ 2>/dev/null || true   # 空なら自動削除

# 4. jj status で確認
jj status

# 5. jj describe で説明文 + jj new で固定 + bookmark 移動
jj describe -m "docs(...): クリーンナップ — ..."
jj new
jj bookmark move <name> --to '@-'

# 6. 最終 grep 検証 (Superseded セクション以外で禁止語が残ってないか)
for f in docs/DESIGN.md docs/decisions/*.md; do
  awk '/^## Superseded/{exit} {print}' "$f" \
    | grep -HnE "最長一致|TBD|未確定|要確定|AST-SPEC|CONTEXT\.md|論点 [A-M]|実装時に確定" /dev/stdin \
    | sed "s|^/dev/stdin|$f|"
done
```

## 適用判断のチェックリスト (ユーザ指示 → 実行可否)

ユーザが下記のような指示を出したらこの runbook を発動候補:

- 「クリーンに整理して」「バッサリやって」「DR を見直して」「ゴミ消して」
- 「設計書が古くなってる」「未確定が溜まってる」
- 「`[[no-historical-noise]]` 違反だらけ」

このときに確認すべきユーザ判断項目:

1. **DR 間の「Updated by DR-Y」訂正ノート挿入を許可するか?** → 基本「入れない」(= ユーザ方針)、例外は明示確認
2. **journal / handoff 文書の処遇** → 基本「削除」、稀に「ヘッダ強化で保持」
3. **DR 4桁化等の命名変更を同時にやるか?** → 別 commit / 別タスク分割推奨
4. **翻訳 (-ja ペア) の同時作成?** → リリース直前まで保留が基本

## ultracode 推奨 (大規模時)

20件以上の DR を扱う場合は ultracode opt-in 推奨。workflow パターン:

- Phase1 棚卸し: 観点別 5 並列 → adversarial 3 視点 verify
- Phase2 案生成: DESIGN/INDEX 1 件 + DR 並列 (active low effort / partial medium / DESIGN high effort)
- Phase3 修正: critical 件数次第。多ければ workflow で並列、少なければ手動編集
- Phase4 適用: 単独 commit

予想コスト: 40 DR 規模で 2 段の workflow を回すと **〜7M token / 30〜45 分**。token 予算を意識する場合は `effort: low` で active を流す等で削れる。

## このドキュメント自身の見直し

このドキュメント自身が陳腐化しないために、次回クリーンナップ実行時:

1. **このフローで実際にハマった点** を冒頭の「ハマり所」セクションに追記 (= journal 化せずここに集約)
2. **新ルール (例: 新しい禁止語パターン) が出てきた** ら「検出すべき禁止語」リストに追記
3. **判定区分** の境界事例があったら「判定区分」表に追記
4. **ultracode workflow パターン** が改善されたら反映 (例: phase 数、agent effort、token 予算)
5. **適用後 1 ヶ月** 以内に「この runbook を見ながらやった結果」を 1 サイクル分振り返り、不要な手順や曖昧な指示を削る

毎回頭から読み直すのでなく、**冒頭の「トリガ」「原則」と「Phase X の該当箇所」だけ参照する** 想定。runbook 自体が冗長化しないよう、適用後の振り返りで削れる部分は削る。

## ハマり所 (実例)

### 2026-06-26 初回適用

- **Phase2 verify への入力欠如**: verify agent に new_content (= Phase2 で生成した最終案) を embed していなかったため、用語整合性検証が空回り。Phase2 ワークフローで `final_content` を prompt に直接 embed するように修正
- **47 / 19 / 21 件の DR を並列で扱った結果**: 1 件あたり medium effort で 10 分以内に完了。`final_content` の長さ目安は 1〜4KB。これより長くなる DR は Why セクションが残りすぎている可能性 (= 削り過ぎチェック対象)
- **Superseded セクション wording のばらつき**: agent ごとに 「再編成 (DR-XXX)」「適用範囲訂正」「再定義」等バラバラに書くため、phase 3 で統一フォーマットを明示的に指示する必要があった
- **camelCase の決定本文残存**: 「原文時点記録として許容」と「現役読者の誤読リスク」のバランスで agent が揺れた。決定本文を snake_case に書き換え + 末尾 Superseded で「元は camelCase」を明示否定するパターンが安定 (= DR-003 の方式)

## 関連

- `[[no-historical-noise]]` (claude-rules-personal) — 過去仕様への跡地コメント / history narrative / バージョン番号付き注釈の禁止
- `[[design-priority]]` (claude-rules-personal) — 「動いてるから」「過去の経緯」を理由に設計の歪みを残さない
- `[[design-impl-bidirectional-check]]` (claude-rules-personal) — 設計と実装の双方向整合確認 (本 runbook は DR-DR 間も射程)
- `[[empirical-verification]]` (claude-rules-personal) — 検証はマトリクスで網羅、grep ベースの実機検証で裏取り
