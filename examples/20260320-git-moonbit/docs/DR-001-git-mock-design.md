# DR-001: git CLI モック設計判断

## 概要

kuu ライブラリの git CLI モック example を作成する過程で発生した設計判断の記録。

## 判断1: core API vs DX層

- **選択**: core API 直接使用
- **理由**: git CLI は15+サブコマンドを持ち、各サブコマンドが独立したオプション群を持つ。DX層の struct-first パターンでは全サブコマンドのフィールドを1つの struct に持つ必要があり、巨大 struct になる。core API なら各サブコマンドが独立した Parser (sub) として構築でき、Opt 変数でスコープが閉じる。

## 判断2: string() vs custom() の使い分け

- **問題**: kuu の値プリミティブ（string/int/float/boolean/append_*）は shorts/global/aliases パラメータを持たない（DR-053 の純化設計）
- **解決**: shorts/global が必要なオプションには `custom()` + `pre=@core.Filter::map(fn(s) { s })` を使用
- **該当箇所**: git-dir/work-tree/-C (global)、-m/-n/-b/-c/-s (shorts) 等の11箇所
- **教訓**: example の初回使用箇所に identity filter のコメントを追加して可読性を確保

## 判断3: checkout の dashdash 処理

- **問題**: `sub()` はデフォルトで dashdash を自動登録する。checkout で明示的に `dashdash()` を追加すると重複エラー
- **解決**: `dashdash=false` で自動登録を抑制し、`checkout.dashdash()` で手動登録
- **理由**: checkout では branch positional と file pathspec を `--` で明示的に分離する必要があるため

## 判断4: branch -D/-M の表現

- **問題**: 当初 `name="D"` → `--D` として実装。git のリアリティとして `-D` (short) が正しい
- **解決**: `name="force-delete"` + `shorts="D"` に変更。flag は shorts をサポートするため問題なし

## 判断5: serial の Opt[T]? パターン

- **問題**: serial のクロージャ内で作成した Opt をクロージャ外で参照するため、`Opt[String]?` + `mut` の二重ラッピングが必要
- **解決**: write_serial ヘルパーで二重 match パターンを隠蔽。初回使用箇所にコメントで説明
- **教訓**: kuu の serial API はクロージャベースのため、外部参照パターンが冗長になる。将来の DX 改善候補

## 判断6: 独立 moon.mod.json

- **問題**: 親プロジェクトの `source: "src"` 設定により、examples/ がビルド対象外
- **解決**: example ディレクトリに独立した `moon.mod.json` を配置し、kuu を path 依存として参照
- **影響**: import パスが `kawaz/kuu/src/core` → `kawaz/kuu/core` に変更（source 設定による自動マッピング）

## 判断7: write_positional の is_set() ガード

- **問題**: serial positional が未指定のとき、`opt.get()` が `Some("")` を返し空文字列が出力される
- **解決**: `is_set()` チェックを追加し、CLI で明示的に指定された場合のみ出力

## 検証結果

- 15サブコマンド（うち2つはネスト）
- グローバルオプション7種
- kuu 機能カバー: flag, count, custom(string), custom(int), append_string, positional, rest, serial, dashdash, exclusive, required, require_cmd, aliases, choices, implicit_value, variation_false, variation_reset, deprecated(未使用)
- テスト: 78件（正常系 + エラー系 + エッジケース）
