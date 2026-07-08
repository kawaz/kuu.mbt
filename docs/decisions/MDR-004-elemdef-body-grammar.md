# MDR-004: ElemDef に消費文法 body を持たせる — structural-or / nested-group の decode と lowering

Status: Accepted (実装済み — conformance skip 全解消、コミット ba39207c)

> 由来: issue `2026-07-08-structural-or-builder-or-branch-id-followup` (installer 移植時の意図的 skip 凍結) と conformance skip 4 件。kawaz 裁定 2026-07-08 (自動 id `#{seq}` 系 / provenance 表示、docs/issue 同 issue の裁定節) を設計条件として組み込む。

## 対象の skip 4 件と wire form (fixture が既に固定している事実)

wire form は spec 側の fixture が既に使用しており (期待値の権威は仕様、DR-070 §1b)、**新規 spec DR は不要** — 必要なのは参照実装の decode + lowering 経路のみ:

| fixture | wire form | 期待挙動の要点 |
|---|---|---|
| `path-search/variable-arity-ambiguous` | option に `"or": [{"seq":[{type,name}×3]}, {type,name}]` (トリガは `long` に factor out) | 枝ごとに**別の named cell** (r,g,b / name) を束縛。**result は flat** ({r,g,b,rest}) = 枝のセルは親スコープ直下の entity。構造の異なる完全経路は ambiguous 保存 (DR-038 / DESIGN §15.4) |
| `path-search/held-errors-distinct-depth` / `-same-depth` | positional に匿名 `{"or":[branch, branch]}` | 各枝の躓きを held Error 全保持 (DR-053 §2)、最深 primary / 同深タイ |
| `export-key/transparent-seq` | positional に `{"name":"xs", "repeat":{min:0}, "positionals":[{name:"k", export_key:null}]}` (named group) | 反復グループ (DR-044): 発火ごとに配列要素、inner element は自名で effects (`entity=k`)、export_key null で裸値化 |

## 決定 (設計)

### 1. ElemDef に `body` 軸を追加 (flat セルはその縮退形)

```moonbit
// ElemDef に追加するフィールド
body : ElemBody

enum ElemBody {
  BCell                       // 従来の単一値セル (ty フィールドが型) — 既存全経路の縮退形
  BOr(Array[OrBranch])        // 構造 or: 枝 = 消費文法、枝ごとに別セルを束縛
  BGroup(Array[ElemDef])      // named group: 入れ子 positionals (repeat と組んで反復グループ)
}

struct OrBranch {
  id : String                 // ユーザ指定 id、無指定は自動 "#{seq}" (kawaz 裁定: # は user ns 外)
  items : Array[ElemDef]      // 1 個 = 単一セル枝、複数 = seq 枝。再帰可 (枝の中の group/or)
}
```

- 既存コードへの波及を最小化するため **flat 経路 (BCell) の観測挙動は不変**。`ty` フィールドは BCell の型として残す (BOr/BGroup の要素では未使用、leaf の ElemDef 各自が持つ)
- `value_requires` (CRequiresIf の素材) は現行のまま — 値 enum 枝 (exact 照合) は BOr とは別物 (§5.3 values 正規形)。BOr は**消費文法の枝** (typed cell を束縛する) で、制約は枝 items の各 leaf が自分の requires を持つ

### 2. decoder (json_conformance harness / 将来の wire decoder 共通の形)

- `dec_option` / `dec_positional`: `"or"` キー → BOr (枝は `{"seq":[...]}` = items 複数 / 単一 cell obj = items 1 個。枝の `"id"` 無指定は `#{seq}` 採番)。`"positionals"` キー (element 内) → BGroup
- 採番 seq は decode 1 回のパーサ全体で単調増加 (kawaz 裁定: 一意なら何でもよい)。ユーザ id "xx" からの派生ノードが要る場合は "xx#{seq}"
- capability gate 2 件 (structural or-positional / variable-arity or-option) と nested-group gate を撤去

### 3. lowering (installer.mbt)

- **BOr (option, トリガ付き)**: greedy 衛星 `Seq([Exact(trigger), Or([branch_node...])])`。branch_node = items を順に value_prim で並べた `Seq` (1 個なら素のノード)。**leaf cell は親スコープ直下の entity として登録** (fixture の flat result に一致)。eq-split matcher は単一値セル枝のみ対象 (3 セル枝に `--color=v` は成立しない — `=` 形は値 1 個の綴り)
- **BOr (positional, 匿名)**: spine に `Or([branch_node...])` を直接積む。枝の held Error は評価器の既存 Or 意味論 (全枝評価 + Held 保持) がそのまま DR-053 §2 を満たす
- **BGroup + repeat**: `IdxRepeat(label = 要素名, head = Seq(inner cells...), min)` に lower (skip メッセージの「IdxRepeat with a distinct inner-element name/export_key」がこの経路)。inner の export_key null は既存の DR-052 §2 処理 (resolve の裸値化) に接続。**スコープ限定: 本 MDR の BGroup は unbounded repeat (max:null) のみ対象** — `IdxRepeat(String, Node, Int)` は budget を持たず bounded を表現できないため、bounded named-group の fixture が来た時点で IdxRepeat の budget 拡張を別途行う (codex REVIEW-M3)
- engine 側 (Node ADT / eval) は Or/Seq/IdxRepeat を既にサポート — **本 MDR で評価器は触らない** (lowering と decode のみ。既存意味論で held 全保持・最深 primary・反復グループ整形・裸値化が出ることは eval.mbt / resolve.mbt の実地照合で確認済み — codex レビュー)

### 3b. lowering 周辺の非再帰関数群への波及 (codex Critical ×2 + Medium ×1)

Node の組み方 (§3) だけでは足りず、**ElemDef 直下しか見ていない既存の収集関数群を ElemBody 再帰に拡張する**。忘れると「値は評価されるが entity/export が無くて resolve できない」という気づきにくい失敗になる:

- **`collect_export` / `build_export_map`**: BGroup 内 leaf (transparent-seq の `k` export_key:null) と BOr 枝内 leaf の export_key を map に載せるため、body を再帰的に辿る。transparent-seq はまさにこの経路が本体 (裸値化は export map 経由)
- **`ensure_entities` / `ensure_entity`**: BOr 枝 leaf (r/g/b/name) と BGroup 内 leaf (k) を親スコープ直下の entity として登録する再帰拡張。評価器の Or/Seq/IdxRepeat は entity 登録を関知しないので、ここが唯一の登録点
- **`inst_long` の eq_entries 既定 push**: 現行は TFlag/TBool 以外の全 option に `e.ty` で無条件登録するが、BOr 要素は `ty` を使わない — **BOr 要素では無条件 push をスキップし、単一値セル枝が存在する場合のみその leaf の name/ty で entry を作る** (`--color=v` を実在しない top-level entity に束縛する誤登録の防止)

### 4. エラー・表示の帰属 (kawaz 裁定の適用)

- 枝内 leaf の失敗は leaf 自身の name で帰属 (通常の value primitive と同じ)。枝の選択そのものに帰属するエラー (該当枝なし等) は枝 id (`#{seq}` or ユーザ id) を内部照合に使い、**外向き表示は発火時の動的パス + ユーザ起源名で組む** (DR-066 2026-07-08 改訂の path/provenance)。自動 id は表示面に出さない
- 反例を探す観点 (裁定より): ユーザ起源が無い合成ノードが「最寄りのユーザ要素」に着地するか — 実装時に wbtest で確認

## 実装順 (提案)

1. decoder + ElemBody (gate 撤去、BCell 縮退の無風確認 = 既存 fixture 全 green)
2. BOr positional (held-errors 2 fixture、評価器の既存 Or 意味論で最小)
3. BOr option (variable-arity、ambiguous 保存 + flat entity + §3b の inst_long 分岐)
4. BGroup + IdxRepeat (transparent-seq、§3b の export/entity 再帰が本体)
5. **OrBranch.id の表示非露出 wbtest を 1 本追加** — 対象 4 fixture には branch id が観測面に出る case が無いため、fixture 任せにすると未検証コードになる (codex REVIEW-M5)。自動 `#{seq}` id がエラー・結果のどこにも漏れないことを wbtest で固定

各段で conformance を回し、skip が 1 つずつ VANISHED になるのを確認する。

## 採用しなかった案

### ElemDef を丸ごと再帰 AST に置き換える

flat フィールド群 (installer 所有軸) は宣言語彙と 1:1 で写像されており、全面再帰化は 12 installer 全部の書き換えになる。body 軸の追加なら BCell 縮退で既存経路が無風。

### 枝ごとに ElemDef でなく専用の縮小型 (name+ty のみ) を使う

枝の leaf にも export_key / requires / repeat が宣言できる余地 (fixture が将来固定しうる) を最初から閉じてしまう。ElemDef 再帰なら宣言語彙の直交性が保たれ、未対応軸は decode 時 gate で明示 skip できる。

## 関連

- issue `2026-07-08-structural-or-builder-or-branch-id-followup` (本 MDR で structural-or 側を実装へ。or-branch-id 側は CRequiresIf 4-tuple で解消済み)
- DR-038 / DESIGN §15.4 (構造の異なる完全経路 = real ambiguous)、DR-044 (反復グループ)、DR-052 §2 (export_key null)、DR-053 §2 (held 全保持)、DR-070 §1b (fixture = 期待値の権威)
- kawaz 裁定 2026-07-08 (`#{seq}` 自動 id / provenance 表示) — issue 裁定節 + DR-066 改訂
