# 20260318-tar

GNU tar コマンドの引数パースを kuu で再現するデモ。

## 注目ポイント

tar はサブコマンドを使わず、**排他的フラグ群で操作モードを切り替える**構造を持つ。
既存 example (mygit, mydocker) が `sub()` ベースなのに対し、本 example は:

- **排他制約の多用**: 操作モード (create/extract/list/...) と圧縮方式 (gzip/bzip2/xz/...) の2グループ
- **at_least_one**: 操作モードは1つ以上の選択が必須
- **variation**: `--wildcards`/`--no-wildcards`, `--acls`/`--no-acls` 等の対称フラグ
- **aliases**: `--extract`/`--get`, `--catenate`/`--concatenate` 等の同義オプション
- **count**: `-v` の複数指定で詳細度が増す
- **append_string**: `--exclude` の累積的使用
- **int_opt + post filter**: `--strip-components` の非負整数バリデーション
- **string_opt + choices**: `--format` のフォーマット選択
- **env**: `TAR_OPTIONS` 環境変数対応
- **rest**: 残りの引数をファイルリストとして収集

## スコープ外

- **オールドスタイルオプション** (`tar cvf`): ハイフンなしの束は kuu の標準パースでは対応しない
- **`-C` の位置依存セマンティクス**: kuu の宣言的モデルでは直接表現不可。`append_string` で収集しアプリ側で処理する方式で代替
- **ロングオプション略称解決** (`--cre` = `--create`): kuu 未対応

## 実行

```bash
moon run .
```

## テストケース

main.mbt 内に複数のテストケースを定義し、各操作モード・オプション組み合わせの
パース結果を表示する。
