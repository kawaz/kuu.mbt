# ワークスペース別ワークフロー自動読み込み

セッション開始時（最初のユーザー入力時）に以下を実行:

1. ワークスペース名を特定:
   ```bash
   jj workspace root   # パス確認
   jj log --no-graph -r @  # review@ や main@ 等からワークスペース名を確認
   ```
2. `.claude/_workflows/{wsname}-*.md` に該当ファイルがあれば読み、その運用に従う
