# mydocker — Docker CLI Subset Example

2026-03-08 時点の kuu API (v0.1.0) で作成した Docker CLI サブセットのサンプル。
kuu の API 表現力を示すことを目的としている。

## 実装サブコマンド

| コマンド | 説明 |
|---|---|
| `run` | コンテナの実行 |
| `build` | イメージのビルド |
| `ps` | コンテナ一覧 |
| `images` | イメージ一覧 |
| `pull` / `push` | イメージの pull/push |
| `exec` | コンテナ内コマンド実行 |
| `compose up/down/logs/ps` | Compose 操作（ネスト2段） |
| `network create/ls/rm/inspect` | ネットワーク管理（ネスト2段） |
| `volume create/ls/rm/inspect` | ボリューム管理（ネスト2段） |

## 使用している API 機能

| API | 用途例 |
|---|---|
| `sub()` | サブコマンド定義。root → compose → up の3段ネスト |
| `flag()` | `--detach`, `--rm`, `--interactive`, `--tty` 等 |
| `string_opt()` | `--name`, `--format`, `--file` 等 |
| `string_opt(choices=)` | `--log-level`, `--restart`, `--driver` 等 |
| `string_opt(choices=, implicit_value=)` | `compose down --rmi` (値省略で "all") |
| `int_opt()` | `--scale`, `--last` 等 |
| `count()` | `--verbose` / `-v` / `-vv` |
| `append_string()` | `--publish`, `--volume`, `--env`, `--build-arg`, `--file` (複数指定) |
| `positional()` | イメージ名、コンテナID、ネットワーク名 等 |
| `rest()` | `docker run` のコマンド部分、`compose up` のサービス名 等 |
| `require_cmd()` | root, compose, network, volume でサブコマンド必須化 |
| `required()` | `run` のイメージ名、`pull`/`push` のイメージ名 等 |
| `exclusive()` | `ps --all` と `ps --last` の排他制御 |
| `set_description()` | 各サブコマンドのヘルプ説明 |
| `as_ref()` | `exclusive()` / `required()` へのオプション参照渡し |
| グローバルオプション | `--verbose`, `--debug`, `--log-level`, `--host` |

## 特筆すべき実装パターン

- **ネスト3段**: `mydocker` → `compose` → `up`/`down`/`logs`/`ps`
- **append による複数値**: `-f file1 -f file2` で compose ファイルを複数指定
- **choices + implicit_value**: `--rmi` (値なしで "all", 値ありで "all"/"local")
- **exclusive 制約**: `--all` と `--last` を同時指定するとエラー
- **rest によるコマンド引数**: `docker run image cmd arg1 arg2` の可変長引数
- **グローバルオプション伝搬**: `--debug` が全サブコマンドレベルで有効

## ビルド・実行

```bash
moon build
moon run examples/20260308-mydocker
```

デフォルトの実行例 (`compose -f ... up --detach --scale 3 web db`):

```
=== Global Options ===
verbose: 0
debug: true
log-level: info

=== compose ===
file: ["docker-compose.prod.yml", "docker-compose.override.yml"]
  --- up ---
  detach: true
  build: false
  force-recreate: false
  no-deps: false
  scale: 3
  services: ["web", "db"]
```
