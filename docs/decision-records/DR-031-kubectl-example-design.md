---
type: decision
---

# DR-031: kubectl example の設計

## 概要
kuu の引数パース機能を検証するため、kubectl のコマンド構造をモデルにしたデモプログラムを作成した。

## サブコマンド選定理由

### 採用したサブコマンド
6個のサブコマンド + 1個のネストサブコマンドを選定:

1. **get** — 最も使用頻度が高く、rest ポジショナル + choices + append_string + variation_false (--no-headers) を一度にデモできる
2. **apply** — required の append_string (--filename 必須) + 複数の choices (--dry-run, --validate) をデモ
3. **delete** — flag default=true (--wait/--no-wait) + choices (--cascade) + int_opt (--grace-period) の組み合わせ
4. **describe** — get のサブセットで、show-events の default=true パターンを追加検証
5. **logs** — `-f` が `--follow` にバインドされる（他のサブコマンドでは `--filename`）。同一ショートオプションのサブコマンド別バインドを実証
6. **exec** — dashdash (`-- COMMAND [args...]`) の最適なデモ。`-it` ショートフラグも検証
7. **config** (nested) — require_cmd + ネストサブコマンド (view, use-context, set-context) で階層構造をデモ

### 不採用のコマンド
- **create, patch, replace, rollout** — 機能的に apply/get と重複が大きく、新たな kuu 機能のデモにならない
- **top, drain, cordon** — 特殊用途でパース構造がシンプルすぎる
- **port-forward, proxy** — パース的には logs/exec と同等

## 設計判断

### `namespace` 変数名の回避
MoonBit で `namespace` は予約語 (reserved_keyword)。変数名を `ns` に変更した。

### `-f` のサブコマンド別バインド
kubectl の最も特徴的な設計: 同じ `-f` が get/apply/delete では `--filename`、logs では `--follow` を意味する。
kuu ではショートオプションがサブコマンドローカルなため、自然に実現できることを実証した。

### config のネスト構造
kubectl には他にも `kubectl cluster-info dump` 等のネスト例があるが、config が最も日常的で分かりやすい。
view (フラグのみ), use-context (required positional), set-context (positional + 複数 string_opt) と3パターンで構成し、ネストサブコマンドの柔軟性を示した。

## kuu 機能カバレッジ

このサンプルでカバーする kuu 機能:
- sub, require_cmd, set_description (サブコマンド)
- flag, string_opt, int_opt (基本オプション)
- append_string (繰り返しオプション)
- positional, rest (ポジショナル引数)
- dashdash (-- セパレータ)
- global=true (グローバルオプション)
- choices, implicit_value (選択肢)
- required, exclusive (制約)
- variation_false (--no-xxx)
- post filter: in_range (バリデーション)

## kubectl example で発見された kuu の設計課題

1. **get().unwrap() の嵐** — デフォルト値付きオプションでも `get()` は `Option[T]` を返すため `unwrap()` が必須。DX 層で `get_or(T) -> T` を提供する検討が必要（既知の課題）
2. **セマンティック検証レイヤーの不在** — `delete` は resources または --filename のいずれかが必要だが、kuu のパーサレベルでは「AかBのいずれか必須」を表現できない。DX 層またはユーザーコードでの検証が必要
3. **`-f` のサブコマンド別バインド** — 自然に動作することを確認。kuu のショートオプションがサブコマンドローカルである設計の正しさを実証

## 未カバー (他サンプルで検証済み)
- count (mygit の verbose で検証済み)
- serial (mygit の remote add/rename で検証済み)
- append_int (mygit で検証済み)
- variation_reset, variation_unset (mygit で検証済み)
- hidden (mygit で検証済み)
- default_fn (mygit で検証済み)
- post filter: trim, non_empty, one_of (mygit で検証済み)
