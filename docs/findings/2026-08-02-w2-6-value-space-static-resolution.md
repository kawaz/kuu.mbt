# W2-6 値空間残余の静的解決 — 遷移表実装と 3 つの導出判断

> 対象: spec DR-127 §2.2 の value_type 遷移表 / §1 (負 index) / DR-126 §1 (型依存グラフ)、
> kuu.mbt 計画 `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-6 行 + §6.1。
> 実装: `src/internal/engine/lowering.mbt` の `classify_value_residual` / `classify_link_residual` /
> `collect_empty_target_errors`。pin: `src/kuu/value_type_reference_wbtest.mbt` (e3〜e7 ほか 5 test 群) +
> spec `fixtures/definition-error/empty-on-scalar-invalid-range.json`。

## 判明した事実

- DR-127 §2.2 の遷移表 6 行は、`resolve_link_path` の `Residual(leaf, from)` (葉セル + 最初の値空間
  segment 位置) を入力に、segment 1 つずつの降下で全行実装できる。record フィールドの type 参照ホップは
  必ず segment を 1 つ消費するため、**巡回型グラフでも降下はパス長で有界** (circular-ref 検査とは独立に
  停止する)。
- **union 行の判定単位は「operand を読むパーサ実体が定義時に一意か」** (§3.2 の pieceProcessor 規定から
  導出)。終端は 3 分類 — record フィールド終端 = type 参照 (canonical 綴り同一性で比較、out 形が同じでも
  別参照は不一致)、array 要素等の構造終端 = ValueType 構造 Eq、map/value に飲まれた終端 = Runtime
  (Runtime 同士のみ一致)。クラス混在は不一致 = definition-error `invalid-range`。降下中に output_type
  未宣言の型に当たった variant は「含有とも非含有とも言えない」ので union 全体を `Unsupported` に倒す。
- **accumulator セル (multiple / repeat / separator — DR-044 §1 で常に配列) への値空間パスは segment の
  種別を問わず `Unsupported`** (計画 §6.1 の統括裁定)。`tags[0]` も `tags.first` も同じ扱い。bare link は
  従来どおり。
- **`empty` の target 型検査は「宣言が非 container を静的に確定する場合のみ invalid-range」**。
  accumulator セルは常に OK、output_type が Some かつ全域 primitive (union 含む、
  `value_type_primitive_only`) のときのみ Error。None (名乗らない) / `value` / 混在 union は通す。
- **`unsupported` は conformance fixture の期待値に書けない** (CONFORMANCE §「`unsupported` は fixture の
  期待値には書けない」+ `schema/fixture.schema.json` の kind enum に不在)。したがって計画が見込んだ
  「accumulator セルへの値空間パス = Unsupported」の spec fixture は**規範上書けず**、wbtest pin のみが
  実装側の固定になる。spec 側に規範 (どの kind の definition-error か、あるいは合法か) が立った後続窓で
  fixture 化する。
- 静的に合法な値空間パス (record フィールド等) は W2-6 後、定義検査を通過するが、効果 routing は
  `link_route_fields` が `Residual` を `None` に落とすため **当該 entry は実行時に不活性** (トークンが
  マッチしない)。W2-7 (vivify + 座操作) が routing を実装するまでの過渡状態で、conformance 面には
  record を名乗る builtin が無いため観測されない。

## 実用的な示唆

- エラー kind の対応: record フィールド外れ / array への `.name` / primitive 残余 / union 含有 0 =
  `absent-ref` (第 1 相と同系、post-fixpoint の `check_element_absent_link` が発行)。opaque / accumulator =
  `unsupported`、union 型不一致 = `invalid-range` (いずれも pre-fixpoint の `collect_link_path_errors` が
  発行)。この pre/post 分担は W2-2 以前からの既存分担の踏襲。
- `empty` の検査対象は colon DSL の全入口 (要素自身の `long` は normalize 後の `variants` を、alias
  `long_override` は生宣言を分類し直して見る)。`default_fn` 側は既存の
  「Sentinel 返し fn は default 席に置けない」検査が塞いでいるため empty 固有の腕は不要。
- wire decode の乖離 (別件): kuu.mbt の decode は `multiple: true` (bool) を受けるが、spec
  `wire.schema.json` の multiple は string | object の二形のみ。fixture は schema 側が正。
  issue: `docs/issue/2026-08-02-wire-multiple-bool-decode-divergence.md`。

## 検証の詳細

### 遷移表 6 行の pin (src/kuu/value_type_reference_wbtest.mbt)

| 行 | ケース | 期待 | 結果 |
|---|---|---|---|
| record 当たり | e3 `tr.since` / e4 二ホップ `w.inner.until` | 静的成功 (parse Ok) | pass |
| record 外れ | e5 `tr.nope` / e6 `tr[0]` | absent-ref | pass |
| record → opaque フィールド | e7 `h.payload.x` | unsupported (既存文言不変) | pass |
| array | `m[0]` / `m[-1]` / `e[2].at` 静的続行、`m.first` = absent-ref、`e[2].nope` = absent-ref | 表どおり | pass |
| map / value | `l.some.deep.key` / `a.x[3]` | 静的成功 (実行時送り) | pass |
| primitive | e2 `cell.field` (string) | absent-ref (現状維持) | pass |
| union | 一致 = Ok、部分含有 (Bool variant 脱落) = Ok、参照不一致 = invalid-range、record×map 混在 = invalid-range、全 primitive (case f) = absent-ref | 表どおり | pass |

### accumulator / empty

- accumulator: `tags[0]` / `tags.first` = unsupported (メッセージに accumulator を含む)、bare `tags` = Ok。
- empty: scalar 直 = invalid-range (element=v)、multiple = Ok、record 宣言 = Ok、output_type None = Ok、
  bare link 先が scalar = invalid-range (帰属は entry 側)、alias long_override = invalid-range (帰属は alias 名)。

### 全体ゲート (2026-08-02 実測)

- `just test`: 661 tests / 661 passed、conformance `decoded=396 ran_cases=889 skipped=0 mismatches=0`
  (新 fixture で 888→889)。両台帳 (known_divergences / expected_skips) は W2 期間を通じて空のまま。
- `moon check --deny-warn` green、`moon info` 差分なし (公開面変更なし)。
- spec: `just lint-fixtures` (396 件) / `lint-descriptors` / `lint-reference` すべて OK。

## 関連

- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §1 / §2.2 / §3.2
- spec `docs/decisions/DR-126-descriptor-record-value-type.md` §1
- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-6 行 / §6.1
- `docs/issue/2026-08-02-cell-fn-empty-target-type-check-missing.md` (本段で close)
