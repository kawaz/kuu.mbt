# MDR-003: 予約語衝突の命名規約

Status: Accepted

MDR-001 §4 の未決「MoonBit 予約語との衝突 (`alias` / `export` / `inherit`) を避ける命名規約」を確定する。

slice の現状: これらの単語は関数名 (`fn alias(...)`)・ラベル付き引数 (`inherit? : Bool`, `export? : ExportKey`) としてそのまま使われており、`moon check` が `reserved_keyword` 警告を出し続けている。参照実装の公開 API でこれを引き継ぐと自分のコードベースが常に警告を出す状態になり、将来 MoonBit がこれらを本当の予約語に格上げした場合の破壊的変更リスクも抱える。

## 決定

### 1. 規約 = 末尾アンダースコア + wire rename

MoonBit 予約語と衝突する識別子は **末尾アンダースコア** を付ける: `alias` → `alias_`、`export` → `export_`、`inherit` → `inherit_`。

slice 自身に `default_` という前例がある (`lower_runner_wbtest.mbt:521` 相当の struct フィールド、`default` という MoonBit 組込み識別子との衝突回避)。機械的で一貫し、意味は変えず綴りだけ変える。Rust の raw identifier 文化に近く MoonBit ユーザにも違和感が少ない。

### 2. 適用範囲 = 公開 API の識別子全般

規約は公開 API の識別子全般 (struct フィールド名・関数名・ラベル付き引数名) に適用する。`src/core` 着手の最初のコミットで固定し、以後の全 installer / node 型がそれに従う。

### 3. wire (JSON) を読み書きする型は rename を必須にする

`derive` で wire (JSON) を読み書きする型は `fields(<name>_(rename="<spec語>"))` を**必須で付ける**。wire 上の名前は常に spec 語彙 (`alias` / `export` / `inherit` 等) と一致させる。MoonBit 識別子は末尾アンダースコア (`alias_`) だが、JSON のキーは spec 語彙そのもの (`alias`) にする。

```moonbit
struct Foo {
  alias_ : String
} derive(ToJson(fields(alias_(rename="alias"))), FromJson(fields(alias_(rename="alias"))))
```

手書き decoder 経路は元々キー文字列を直読みしている (`json["alias"]` 等) ため非問題 — rename が要るのは `derive` 経路のみ。

### 4. 複合語はセーフ

`export_key` / `ExportKey` のような複合語は元々 `reserved_keyword` 警告の対象外であり、そのまま使える。素の `export` / `alias` / `inherit` 単独のみが対象。slice も `is_inherit` のような形容詞形・`export_key` のような複合語は既に使っており、これらは変更不要。

## 実機検証記録

本規約は机上判断ではなく実機で確認済み。

- **moon バージョン**: 0.1.20260629
- **derive 構文**: `derive(ToJson(fields(alias_(rename="alias"))))` と対称の `FromJson(fields(alias_(rename="alias")))` の両方が動作。JSON の読み書きで wire 上のキーが `alias` (spec 語彙) になり、MoonBit 側フィールドは `alias_` のまま両方向で解決することを確認。
- **警告消滅**: 末尾アンダースコアにすることで `reserved_keyword` 警告が消えることを確認。
- **FromJson 対称**: ToJson で書いた JSON を FromJson で読み戻す往復が成立 (rename が両 derive で対称に効く)。
- **複合語の警告対象外**: `export_key` 等の複合語は元々警告が出ないことを確認。

## 却下案

### 却下: ドメイン語での言い換え

`alias` → `alt_name` / `aka`、`inherit` → `inherited` / `inherit_from`、`export` → `exported` / `is_exported` のように意味に即した別名にする案。

却下理由:
- 各箇所ごとに適切な言い換えを個別に考える必要があり、「なぜこの単語だけこう変則的に呼ぶか」を知らない読者に一貫性が見えにくい (機械的な規則ではない)。
- wire 語彙 (spec) との対応が命名からは読み取れず、rename マッピングとの二重管理になる。

末尾アンダースコア規約は機械的一貫性を持ち、rename で wire 語彙を spec に固定できるため、言い換え案より優れる。

## 関連

- [MDR-001](MDR-001-bootstrap-policy.md): 立ち上げ方針 (本 DR が未決 2「予約語命名規約」を決着)。§4 で `alias`/`export`/`inherit` を予約語衝突として挙げている
- [MDR-002](MDR-002-evaluator-core-design.md): 評価器コア設計 (node.mbt / installer.mbt 等の各型が本規約に従う)
