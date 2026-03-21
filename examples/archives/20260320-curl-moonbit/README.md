# mycurl — curl CLI mock built with kuu

curl コマンドの引数パースを kuu で再現するデモ。
curl の機能自体は実装せず、パース結果をダンプする。

## 検証ポイント

- **70+ オプション**: flag / string / int / float / append_string を網羅
- **exclusive**: 認証方式 (basic/digest/ntlm/anyauth) と HTTP バージョン (1.0/1.1/2/3) の排他制御
- **append_string**: -H, -d, -F, -b など複数指定可能なオプション
- **choices**: --cert-type (DER/PEM/ENG/P12)
- **deprecated**: --sslv3 → --tlsv1.2
- **env**: HTTP_PROXY → --proxy
- **variation_false**: --no-keepalive
- **requires**: --proxy-user は --proxy を必要とする
- **post filter**: --max-redirs に in_range(-1, 999)
- **visibility**: --trace, --trace-ascii は Advanced
- **short combining**: -sSLo file URL のような短オプション結合

## ビルド・実行

```bash
just check    # moon check --deny-warn
just test     # moon test
just run      # moon run examples/20260320-curl-moonbit
```

## テストシナリオ

1. 基本 GET (`curl URL`)
2. POST with data (`-d key=value URL`)
3. 複数ヘッダ (`-H "..." -H "..." URL`)
4. 認証排他エラー (`--basic --digest`)
5. HTTP バージョン排他 (`--http2 --http3`)
6. ファイルダウンロード (`-o file URL`, `-O URL`)
7. deprecated 警告 (`--sslv3`)
8. env 経由プロキシ (`HTTP_PROXY=...`)
9. requires 違反 (`--proxy-user user:pass` without --proxy)
10. choices バリデーション (`--cert-type invalid`)
11. range バリデーション (`--max-redirs -2`)
12. short combining (`-sSLo file URL`)
13. help 表示 (`--help`)
14. 複合実践例
