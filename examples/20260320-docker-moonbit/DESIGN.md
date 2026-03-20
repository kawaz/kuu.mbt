# Docker CLI 引数パースデモ — 設計書

Docker CLI のサブコマンド体系を kuu でパースするデモ。
引数パースの検証用サンプルであり、Docker の機能自体の実装は不要。

## 目的

kuu の以下の機能をリファレンス品質で検証:

1. **多層サブコマンドネスト**: `docker container run`, `docker compose up` 等
2. **グローバルオプション**: `--host`, `--log-level` 等が全サブコマンドで利用可能
3. **append_string**: `-p`, `-e`, `-v` 等の複数回指定オプション
4. **short flag combining**: `-it` = `-i -t`
5. **サブコマンドエイリアス**: `ls` / `list`
6. **choices**: `--log-level`, `--restart`, `--progress` の値制限
7. **exclusive**: `--force-recreate` vs `--no-recreate`
8. **required / positional / rest / serial**: IMAGE, COMMAND, ARG... の位置引数
9. **implicit_value**: `--rmi` (値省略時 "all")
10. **variation_false**: `--no-cache`, `--no-deps` 等
11. **env**: `DOCKER_HOST` 等の環境変数
12. **require_cmd**: 中間サブコマンドは子コマンド必須

## プロジェクト構成

```
examples/20260320-docker-moonbit/
  README.md           # 概要・検証ポイント
  DESIGN.md           # 本文書
  docs/
    decision-records/
      DR-001-*.md     # 設計判断記録
  src/
    moon.pkg          # パッケージ定義
    main.mbt          # fn main + デモシナリオ + run_test ヘルパー
    docker.mbt        # build_and_parse — 全パーサ定義
    docker_wbtest.mbt # テスト
  justfile            # ビルド・テスト・実行
```

## コマンド構造

```
docker [GLOBAL OPTIONS] COMMAND [OPTIONS] [ARGS...]

Global Options:
  --config <DIR>       クライアント設定ディレクトリ [default: ~/.docker]
  --context <NAME>     接続先コンテキスト名
  --host <HOST>        デーモンソケット [env: DOCKER_HOST]
  --log-level <LEVEL>  ログレベル [choices: debug,info,warn,error,fatal]
  --tls                TLS有効化
  --tlsverify          TLS検証有効化
  --debug              デバッグモード

Management Commands:
  container  コンテナ管理
    run      コンテナ作成・起動 ★最多オプション
    ls       コンテナ一覧 (alias: list, ps)
    exec     コンテナ内コマンド実行
    stop     コンテナ停止
    rm       コンテナ削除
    logs     ログ表示
  image      イメージ管理
    build    イメージビルド
    ls       イメージ一覧 (alias: list)
    pull     イメージ取得
    push     イメージ送信
    rm       イメージ削除
  compose    Compose管理
    up       サービス起動
    down     サービス停止
  network    ネットワーク管理
    create   ネットワーク作成
    ls       ネットワーク一覧
    rm       ネットワーク削除
  volume     ボリューム管理
    create   ボリューム作成
    ls       ボリューム一覧
    rm       ボリューム削除

Top-level Shortcuts:
  run    → container run
  ps     → container ls
  build  → image build
  exec   → container exec
  pull   → image pull
  push   → image push
  images → image ls
  rm     → container rm
  rmi    → image rm
```

## 実装方針

### ショートカット実装

`docker run` = `docker container run` のように同一コマンドが2箇所に存在する。
共通のオプション定義関数を作り、両パーサに適用する:

```
fn setup_run_options(p: Parser) -> RunOpts { ... }
container_run = container.sub(name="run")
setup_run_options(container_run)
top_run = p.sub(name="run")
setup_run_options(top_run)
```

### パース結果の表示

tar example と同様、パース結果を文字列として整形して返す。
各デモシナリオで入力 args と結果を対比表示。

### テスト戦略

- 各サブコマンドの基本パース
- short flag combining (-it, -itd)
- append オプション (-p 8080:80 -p 3000:3000)
- exclusive 制約エラー
- required 制約エラー
- choices 制約エラー
- help 表示
- 環境変数フォールバック
- ショートカットと管理コマンドが同一結果になること
