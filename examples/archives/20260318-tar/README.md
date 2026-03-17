# 20260318-tar -- GNU tar 引数パースデモ

kuu を使って GNU tar コマンドの引数パースを再現するデモである。tar の実機能（アーカイブの作成・展開等）は一切実装しておらず、パース結果を表示するだけだ。

## ビルド・実行

```bash
# チェック
moon check --deny-warn

# テスト
moon test

# 実行
moon run examples/20260318-tar

# just を使う場合
just check
just test
just run
```

## 検証ポイント

本デモで検証する kuu の機能と、tar での使用例を以下に示す。

- **exclusive + at_least_one**: 操作モード (create/extract/list/append/update) の排他的必須選択
- **exclusive**: 圧縮方式 (gzip/bzip2/xz/compress/zstd/lzip) の排他的任意選択
- **count**: `-v` の複数指定による詳細度制御 (-v, -vv, -vvv)
- **env**: `TAPE` 環境変数による `-f` オプションのデフォルト値
- **deprecated**: 廃止予定オプションの警告表示
- **alias**: `--extract`/`--get`, `--catenate`/`--concatenate` 等の同義オプション
- **variation_false**: `--wildcards`/`--no-wildcards`, `--acls`/`--no-acls` 等の対称フラグ
- **append_string**: `--exclude` や `-C` の累積的使用
- **int_opt + post filter**: `--strip-components` の非負整数バリデーション
- **string_opt + choices**: `--format` のフォーマット選択 (gnu/pax/ustar 等)
- **rest**: 残りの引数をファイルリストとして収集
- **dashdash (kuu デフォルト)**: 明示的な `dashdash()` コンビネータは不使用だが、kuu のデフォルト `--` セパレータは有効。`--` 以降は位置引数として扱われる

## テストシナリオ

以下の 21 件のシナリオでパース結果を検証する。

1. basic create -- アーカイブ作成 (`-cf archive.tar file1 file2`)
2. basic extract -- アーカイブ展開 (`-xf archive.tar`)
3. basic list -- アーカイブ内容一覧 (`-tf archive.tar`)
4. extract with alias --get -- エイリアスで extract (`--get -f archive.tar`)
5. list with verbose count -- verbose 重ね掛け (`-tvvf archive.tar`)
6. create with gzip compression -- 圧縮付き作成 (`-czf archive.tar.gz dir/`)
7. exclusive error: create + extract -- 操作モードの同時指定 (`-cxf archive.tar`)
8. compression exclusive error: gzip + xz -- 圧縮方式の同時指定 (`-czJf archive.tar.gz .`)
9. missing mode error -- 操作モードなし (`-f archive.tar`)
10. file required error -- `-f` 未指定 (`-c file`)
11. multiple exclude -- 複数 exclude (`--exclude *.log --exclude *.tmp`)
12. strip-components -- パス先頭除去 (`--strip-components 1`)
13. format choices valid -- 正しい format (`--format pax`)
14. format choices invalid -- 不正な format (`--format zip`)
15. deprecated --compress -- 廃止予定オプションの警告
16. variation --no-recursion -- 再帰無効化
17. variation --no-verbose -- verbose リセット
18. variation --no-wildcards -- ワイルドカード無効化
19. short option combining -- ショートオプション結合 (`-czvf`)
20. env TAPE fallback for --file -- `TAPE` 環境変数による `-f` のデフォルト値
21. help display -- ヘルプ表示

## 注意事項

- **Bundled flags 非対応**: `tar cvf` のようなハイフンなしのオールドスタイルオプション束は kuu の標準パースでは対応しない。前処理で展開すれば対応可能だが、本デモのスコープ外である
- **`-C` の位置依存セマンティクス非対応**: 実際の tar では `-C dir1 file1 -C dir2 file2` のように `-C` の位置が意味を持つが、kuu の宣言的モデルでは直接表現できない。`append_string` で収集しアプリ側で処理する方式で代替する

## 関連ドキュメント

- [DR-001: tar デモ設計](docs/decision-records/DR-001-tar-demo-design.md)
