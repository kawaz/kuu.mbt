# review ワークスペース運用

## 概要

review ワークスペースは main の進捗を観察し、課題や知見を発見したらドキュメントとして main に反映する役割を持つ。

## 基本動作

### 1. main@ への追従

```bash
jj edit -r main@
```

- セッション開始時、および「進捗みて」等の指示時に実行
- 差分があれば内容を確認し感想・分析を報告

### 2. 課題・知見の発見 → ドキュメント反映

観察で得た知見をコミットとして作成:

```bash
# review ワークスペース上で空コミットを作り作業
jj new -m "docs: xxx"

# ファイルを追加・編集
# (例: docs/decision-records/DR-xxx.md, docs/DESIGN.md への追記)
```

### 3. main 側から review をマージ

main ワークスペースから review の変更を取り込む:

```bash
jj -R "$(jj workspace root --name main)" new @ review@
```

### 4. 再び main@ に追従

```bash
jj edit -r main@
```

## 反映対象

- 設計課題の発見・記録（DR の追加）
- DESIGN.md への知見追記
- example から得られた制限事項・改善点
- WASM bridge の制限整理

## 反映しないもの

- コード変更（review はドキュメント専用）
- テスト追加（main 側の作業）
