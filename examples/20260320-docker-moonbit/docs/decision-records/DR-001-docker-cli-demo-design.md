# DR-001: Docker CLI デモの設計判断

## 概要

kuu ライブラリを使って Docker CLI の引数パースを再現するデモの設計。

## 判断 1: ショートカットコマンドの実装方式

### 問題

Docker CLI は同一コマンドが2つのパスで利用可能:
- `docker run` (ショートカット)
- `docker container run` (管理コマンド)

kuu の `sub()` は独立したパーサを返すため、同一コマンドを2箇所で定義する必要がある。

### 選択肢

A. **共有 setup 関数**: オプション定義を関数に切り出し、両パーサに適用
B. **片方のみ実装**: 管理コマンドのみ実装し、ショートカットは README で言及
C. **エイリアス方式**: kuu の aliases でトップレベルにエイリアス作成

### 決定: A. 共有 setup 関数

理由:
- Docker CLI の実際の構造を忠実に再現できる
- kuu の柔軟性（同一定義を複数パーサに適用可能）をデモできる
- コードの重複を最小化

## 判断 2: スコープ選定

### 問題

Docker CLI は100以上のサブコマンドを持つ。全て実装するのは非現実的。

### 決定

kuu の機能をバランスよくカバーする代表的なコマンドを選定:

| コマンド | 検証する kuu 機能 |
|---|---|
| container run | append_string, short combining, serial, rest, required, choices |
| container ls | append_string (filter), choices (format), flag |
| container exec | serial, rest, flag combining |
| image build | append_string (tag, build-arg), choices, flag |
| compose up/down | require_cmd, exclusive, implicit_value, variation |
| network/volume | require_cmd, 基本的なサブコマンド |

## 判断 3: ファイル構成

### 問題

Docker CLI は tar example より大幅にコード量が多い。

### 決定: 3ファイル構成

- `main.mbt`: デモシナリオ（fn main + run_test）
- `docker.mbt`: パーサ構築（build_and_parse + setup_*）
- `docker_wbtest.mbt`: テスト

理由:
- MoonBit は同一パッケージ内の全ファイルがスコープ共有
- 関心の分離（デモ / 定義 / テスト）で可読性向上
- tar の単一ファイルパターンを発展させた自然な拡張

## 判断 4: docker run の positional 引数処理

### 問題

`docker run [OPTIONS] IMAGE [COMMAND] [ARG...]` は3種の位置引数を持つ:
1. IMAGE (必須)
2. COMMAND (任意)
3. ARG... (可変長)

### 決定: serial + positional + rest

```
serial(setup=fn(sub) {
  image = sub.positional(name="image")
  command = sub.rest(name="command")
})
```

理由:
- kuu の serial API が順序保証付き位置引数を自然に表現
- IMAGE は required 制約で必須化
- COMMAND 以降は rest で可変長引数として取得
