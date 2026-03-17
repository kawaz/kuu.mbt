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
- **env**: `TAR_ARCHIVE` 環境変数による `-f` オプションのデフォルト値
- **deprecated**: 廃止予定オプションの警告表示
- **alias**: `--extract`/`--get`, `--catenate`/`--concatenate` 等の同義オプション
- **variation_false**: `--wildcards`/`--no-wildcards`, `--acls`/`--no-acls` 等の対称フラグ
- **append_string**: `--exclude` や `-C` の累積的使用
- **int_opt + post filter**: `--strip-components` の非負整数バリデーション
- **string_opt + choices**: `--format` のフォーマット選択 (gnu/pax/ustar 等)
- **rest**: 残りの引数をファイルリストとして収集
- **dashdash**: `--` セパレータ以降を位置引数として扱う

## テストシナリオ

以下の 20 件のシナリオでパース結果を検証する。

1. create -- アーカイブ作成 (`-cvzf archive.tar.gz --exclude '*.o' src/`)
2. extract -- アーカイブ展開 (`-xvf archive.tar --strip-components 1 -C /tmp/out`)
3. list -- アーカイブ内容一覧 (`-tvf archive.tar`)
4. help -- ヘルプ表示 (`--help`)
5. 排他エラー -- 操作モードの同時指定 (`-cx`)
6. 圧縮排他エラー -- 圧縮方式の同時指定 (`-czJ`)
7. モード未指定エラー -- 操作モードなし (`-f archive.tar`)
8. variation -- 対称フラグ (`--no-wildcards`)
9. dashdash -- `--` セパレータ (`-- --weird-filename`)
10. short bundling -- ショートオプション結合 (`-cvzf`)
11. append モード -- ファイル追加 (`-rvf archive.tar newfile`)
12. update モード -- 新しいファイルのみ追加 (`-uvf archive.tar src/`)
13. diff モード -- アーカイブとファイルシステムの差分 (`-dvf archive.tar`)
14. verbose 重ね掛け -- 詳細度増加 (`-vvv`)
15. env 環境変数 -- `TAR_ARCHIVE` による `-f` のデフォルト値
16. deprecated -- 廃止予定オプションの警告
17. format choices -- `--format` の不正値エラー
18. alias -- `--get` で extract が発動
19. variation false -- `--no-acls --no-selinux` の明示的無効化
20. 複合シナリオ -- 複数機能の組み合わせ

## 注意事項

- **Bundled flags 非対応**: `tar cvf` のようなハイフンなしのオールドスタイルオプション束は kuu の標準パースでは対応しない。前処理で展開すれば対応可能だが、本デモのスコープ外である
- **`-C` の位置依存セマンティクス非対応**: 実際の tar では `-C dir1 file1 -C dir2 file2` のように `-C` の位置が意味を持つが、kuu の宣言的モデルでは直接表現できない。`append_string` で収集しアプリ側で処理する方式で代替する

## 関連ドキュメント

- [DR-001: tar デモ設計](docs/decision-records/DR-001-tar-demo-design.md)
