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

### 3. main 側から review をマージ

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

## 反映しないもの

- コード変更（review はドキュメント専用）
- テスト追加（main 側の作業）
