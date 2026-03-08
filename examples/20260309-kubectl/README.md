# mykubectl — kubectl-like CLI example with kuu

kubectl の引数パースを kuu で実装したデモ。
実際のコマンド機能は持たず、パース結果の表示のみ行う。

## 実行

```bash
moon run examples/20260309-kubectl
```

## カバーする kuu 機能

| kuu 機能 | kubectl での実例 |
|---|---|
| サブコマンド (`sub`) | get, apply, delete, describe, logs, exec |
| ネストサブコマンド | config view / use-context / set-context |
| グローバルオプション (`global=true`) | --kubeconfig, --context, -n/--namespace |
| 同一ショートの異なるロング | `-f`: get/apply/delete → `--filename`, logs → `--follow` |
| choices + implicit_value | --output (wide/json/yaml/name) |
| append_string (繰り返し) | --filename (複数ファイル指定) |
| dashdash (`--`) | exec の `-- COMMAND [args...]` |
| flag default=true + variation_false | --wait / --no-wait (delete) |
| variation_false | --headers / --no-headers (get) |
| required | apply の --filename、logs の pod |
| rest (可変長ポジショナル) | get TYPE [NAME...] |
| int_opt + in_range | --v (0-9)、--max-log-requests (1-100) |
| string_opt | --kubeconfig, --since, --timeout 等 |
| require_cmd | config (サブコマンド必須) |

## 注目ポイント

### `-f` のサブコマンド別バインド

```
kubectl get -f pod.yaml      # -f = --filename
kubectl logs -f nginx         # -f = --follow
```

ショートオプションがサブコマンドローカルであることの実証。

### `exec` の `--` セパレータ

```
kubectl exec nginx -it -- /bin/bash -c "echo hello"
```

`--` 以降が kuu のパーサを通らず、dashdash で丸ごとキャプチャされる。

### `--no-headers` / `--no-wait`

```
kubectl get pods --no-headers    # headers: default=true → false
kubectl delete pod nginx --no-wait  # wait: default=true → false
```

default=true のフラグを `--no-xxx` で反転するパターン。
