# review ワークスペース運用

## 概要

review ワークスペースは main の進捗を観察し、課題や知見を発見したらドキュメントとして main に反映する役割を持つ。

## 基本動作

### 1. main@ への追従

```bash
jj new main@
```

- `jj new main@` で main@ の子コミットを作る（`jj edit` ではなく `jj new`）
- `jj edit -r main@` だと review の変更が main のコミットに直接混入するため NG
- セッション開始時、および「進捗みて」等の指示時に実行
- 差分があれば内容を確認し感想・分析を報告

### 2. 課題・知見の発見 → ドキュメント反映

追従した子コミットにそのまま作業するか、describe で説明を付ける:

```bash
# 追従コミットに説明を付けて作業
jj describe -m "docs: xxx"

# ファイルを追加・編集
# (例: docs/decision-records/DR-xxx.md, docs/DESIGN.md への追記)

# 複数の知見がある場合は更にコミットを分ける
jj new -m "docs: yyy"
```

### 3. main 側から review をマージ（即実行）

**ドキュメント変更は完了次第すぐ main にマージする。「次のセッションで」は忘れるリスクがある。**

マージ直前に main@ が動いていないか確認。動いていたら `jj new @ main@` で取り込む。

main ワークスペースから review の変更を取り込む:

```bash
jj -R "$(jj workspace root --name main)" new @ review@
```

### 4. 再び main@ に追従

```bash
jj new main@
```

## 反映対象

- 設計課題の発見・記録（DR の追加）
- DESIGN.md への知見追記
- example から得られた制限事項・改善点
- WASM bridge の制限整理

## 進捗確認のパターン

### `jj log` → 追従 → 調査 の順序

`jj log` はリポジトリメタデータを読むため、追従（`jj new main@`）なしで実行できる。
しかしファイル内容の読み込み（Read, サブエージェント等）は working copy が必要。

**正しい順序:**

```
1. jj log で差分の概要を把握（追従不要）
2. jj new main@ で working copy を更新
3. サブエージェント起動 or ファイル読み込み
```

**アンチパターン:**

```
1. jj log で差分を見る
2. サブエージェントを起動してファイルを読ませる ← 失敗（working copy が古い）
3. jj new main@ で追従
```

log で全体像を掴んでから追従し、追従後に詳細調査を並列で走らせるのが効率的。

## 反映しないもの

- コード変更（review はドキュメント専用）
- テスト追加（main 側の作業）
