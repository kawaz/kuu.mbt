# mycurl — curl CLI mock built with kuu

## 概要

curl コマンドの引数パースを kuu core API で再現するデモプログラム。
curl の機能自体は実装せず、引数パース結果のダンプとテストを行う。

## 目的

kuu の以下の機能を検証する:

| kuu 機能 | curl での活用 |
|---|---|
| flag | -s, -v, -L, -k, -I, -G, --compressed, -f, -O 等 |
| string (shorts, value_name) | -X, -o, -u, -A, -e, -w, -D 等 |
| int (default, post filter) | --max-redirs (default=50, in_range) |
| float | --connect-timeout, --max-time |
| append_string | -H, -d, -F, -b, --resolve 等 |
| exclusive | 認証方式 (basic/digest/ntlm/anyauth)、HTTP バージョン |
| rest (positional) | URL 引数 |
| choices | --cert-type (DER/PEM/ENG/P12) |
| deprecated | --sslv3 → --tlsv1.2 |
| env | HTTP_PROXY → --proxy |
| variation_false | --no-keepalive |
| post filter | --max-redirs in_range(-1, 999) |
| visibility (Advanced) | --trace, --trace-ascii |
| requires | --proxy-user requires --proxy |

## アーキテクチャ

- **単一ファイル**: `main.mbt` にパーサ構築・デモ実行・テストを全て配置
- **kuu core API 直接使用** (DX 層は使わない)
- **パターン**: tar example と同じ `build_and_parse()` + `run_test()` + snapshot test

## オプション設計（カテゴリ別）

### HTTP メソッド
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -X, --request | String | string | value_name="METHOD" |
| -I, --head | flag | flag | |
| -G, --get | flag | flag | |

### データ送信
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -d, --data | String[] | append_string | value_name="DATA" |
| --data-raw | String[] | append_string | |
| --data-urlencode | String[] | append_string | |
| --json | String[] | append_string | |
| -F, --form | String[] | append_string | value_name="CONTENT" |
| --url-query | String[] | append_string | |

### ヘッダ
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -H, --header | String[] | append_string | value_name="HEADER" |
| -A, --user-agent | String | string | |
| -e, --referer | String | string | |
| --compressed | flag | flag | |

### 認証（exclusive グループ）
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -u, --user | String | string | value_name="USER:PASSWORD" |
| --basic | flag | flag | exclusive |
| --digest | flag | flag | exclusive |
| --ntlm | flag | flag | exclusive |
| --anyauth | flag | flag | exclusive |
| --oauth2-bearer | String | string | value_name="TOKEN" |

### 出力制御
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -o, --output | String | string | value_name="FILE" |
| -O, --remote-name | flag | flag | |
| --output-dir | String | string | value_name="DIR" |
| --create-dirs | flag | flag | |
| -s, --silent | flag | flag | |
| -S, --show-error | flag | flag | |
| -v, --verbose | flag | flag | |
| -i, --show-headers | flag | flag | |
| -D, --dump-header | String | string | value_name="FILE" |
| -w, --write-out | String | string | value_name="FORMAT" |
| -f, --fail | flag | flag | |
| --fail-with-body | flag | flag | |
| --no-progress-meter | flag | flag | |
| -#, --progress-bar | flag | flag | |
| --trace | String | string | visibility=Advanced |
| --trace-ascii | String | string | visibility=Advanced |

### TLS/SSL
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -k, --insecure | flag | flag | |
| --cacert | String | string | value_name="FILE" |
| -E, --cert | String | string | value_name="CERT[:PASSWD]" |
| --cert-type | String | string | choices=["DER","PEM","ENG","P12"] |
| --key | String | string | value_name="KEY" |
| --sslv3 | — | deprecated | → --tlsv1.2 |
| --tlsv1.2 | flag | flag | |
| --tlsv1.3 | flag | flag | |

### プロキシ
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -x, --proxy | String | string | env="HTTP_PROXY" |
| -U, --proxy-user | String | string | requires --proxy |
| --noproxy | String | string | value_name="HOSTS" |

### リダイレクト
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -L, --location | flag | flag | |
| --max-redirs | Int | int | default=50, post=in_range(-1,999) |

### タイムアウト・リトライ
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| --connect-timeout | Double | float | value_name="SECONDS" |
| -m, --max-time | Double | float | value_name="SECONDS" |
| --retry | Int | int | default=0 |
| --retry-delay | Int | int | default=0 |
| --retry-max-time | Int | int | default=0 |
| --retry-all-errors | flag | flag | |

### Cookie
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| -b, --cookie | String[] | append_string | value_name="DATA\|FILE" |
| -c, --cookie-jar | String | string | value_name="FILE" |

### HTTP バージョン（exclusive グループ）
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| --http1.0 | flag | flag | shorts="0" |
| --http1.1 | flag | flag | |
| --http2 | flag | flag | |
| --http3 | flag | flag | |

### その他
| オプション | 型 | kuu コンビネータ | 備考 |
|---|---|---|---|
| --limit-rate | String | string | value_name="SPEED" |
| --resolve | String[] | append_string | value_name="HOST:PORT:ADDR" |
| --connect-to | String[] | append_string | value_name="HOST1:PORT1:HOST2:PORT2" |
| -4, --ipv4 | flag | flag | |
| -6, --ipv6 | flag | flag | |
| -Z, --parallel | flag | flag | |
| --parallel-max | Int | int | default=50 |
| -C, --continue-at | String | string | value_name="OFFSET" |
| -T, --upload-file | String | string | value_name="FILE" |
| -R, --remote-time | flag | flag | |
| -n, --netrc | flag | flag | |
| --no-keepalive | — | variation | variation_false on keepalive |
| --url | String[] | append_string | |

### 位置引数
| 引数 | 型 | kuu コンビネータ |
|---|---|---|
| URL... | String[] | rest |

## テスト計画

tar example に倣い、snapshot test (`inspect`) で以下を検証:
1. 基本的な GET リクエスト
2. POST with data (-d)
3. 複数ヘッダ (-H -H)
4. 認証排他エラー (--basic --digest)
5. HTTP バージョン排他エラー
6. ファイルダウンロード (-o, -O)
7. deprecated --sslv3 の警告
8. --proxy with env HTTP_PROXY
9. --proxy-user requires --proxy エラー
10. --cert-type choices バリデーション
11. --max-redirs range バリデーション
12. short option combining (-sSLo file URL)
13. --help 表示
14. 複合的な実践例 (多数のオプション同時指定)

## ディレクトリ構成

```
examples/20260320-curl-moonbit/
  main.mbt          # パーサ構築・デモ・テスト
  moon.pkg           # パッケージ定義
  justfile           # ビルド・テスト用
  README.md          # デモの説明
  DESIGN.md          # 本ファイル
  docs/
    decision-records/  # 設計判断の記録
```
