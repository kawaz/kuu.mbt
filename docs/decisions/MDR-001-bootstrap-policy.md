# MDR-001: 参照実装の立ち上げ方針

Status: Accepted

kuu.mbt を kuu 仕様 (kawaz/kuu) の MoonBit 参照実装として再出発させるにあたっての立ち上げ方針。旧 kuu-cli 実装 (`kuu-v0` 枝にアーカイブ) と垂直スライス PoC (`slice` 枝) の資産をどう扱うかを含む。

## 決定

### 1. 立ち上げ方式 = 責務境界の明示分離、「スピードより設計の良さ」で

評価器コア (slice の `poc/eval.mbt` / `poc/complete.mbt` 相当) は、slice が抱える 2 件の破れを設計入力として**ゼロから再設計**する。速度のための移植妥協はしない。

- **破れ 1**: 完成オラクルのスコープ相対化。slice の `poc/phase16_wbtest.mbt` の凍結 fail がこの再設計の受け入れテストになる (= 新評価器はこの fail を解消して green にできなければならない)。
- **破れ 2**: pending 枝の扱い。分離恒久化案と Branch への Pending 追加案の両案がある (下記「未決」参照)。

葉 (`node` / `value` / `matcher` / `result` 相当) と installer の lowering は slice を参照して移植するが、設計的に正しい形への書き直しを厭わない。

conformance harness の設計と fixtures (kawaz/kuu 側) は継続利用する。

### 2. 破れの根治

- 破れ 1 は評価器の再設計で必ず解消する。受け入れテストは slice `poc/phase16_wbtest.mbt` の凍結 fail。解消設計 (CPS 化) は MDR-002 §1 で確定。
- 破れ 2 は評価器の設計スケッチを両案 (分離恒久化 vs Branch に Pending 追加) で描いて決める。MDR-002 §2 で案 B (Branch に Pending 追加、1 走査に統一) に確定。

### 3. DR 番号空間 = MDR-NNN

本リポの Design Record は **MDR-NNN** (MoonBit DR、文字 prefix、3 桁) を用いる。

仕様側 DR (kawaz/kuu の DR-NNN) は**複製しない**。参照が必要なときは「kawaz/kuu の DR-NNN」形式で参照のみ行う。

> 理由: slice 枝では仕様 DR を 43 本複製し、仕様の改訂に追従できず stale 化した。参照実装は仕様の正本を複製せず参照する。

### 4. moon 構成 = 最小開始

- `moon.mod`: name `kawaz/kuu` / `source = "src"` / `preferred_target = "wasm-gc"`。
- パッケージは `src/core` 単一から開始。公開 API が固まってから分割する。
- deps は最小。conformance runner (Phase B) が fs を必要とした時点で `moonbitlang/x` を追加する (= 使う時に入れる、先回りで宣言しない)。
- MoonBit 予約語との衝突 (`alias` / `export` / `inherit`) を避ける命名規約は、評価器の設計スケッチと同時に決める。MDR-003 で末尾アンダースコア + wire rename 規約に確定。

### 5. CI の fixtures 供給 = 並置 checkout + KUU_FIXTURES 注入 + SHA pin

CI では kawaz/kuu を `actions/checkout` で並置 checkout (ref = SHA pin) し、`KUU_FIXTURES` 環境変数で runner に注入する。fixtures の追従は ref bump PR で明示化する。

多言語フェーズ到達時に fixtures を配布物化へ昇格させる 2 段構え。

### 6. conformance 台帳 = ゼロ開始

conformance harness の機構 (decode-capability gate / 二重台帳 / 両方向 fail) だけを持ち込み、中身は空から積む。slice の追従 issue 10 件は実装チェックリストとして参照する。slice ワークスペースは凍結アーカイブ (削除しない)。

## 補助的な立ち上げ決定

- **VERSION = 0.0.0 (プレースホルダ)**: `moon.mod` の version は開発版として 0.1.0 を宣言するが、`VERSION` はプレースホルダ 0.0.0 とし release パイプラインを休眠させる (skeleton に配布物が無いため最初の release をまだ切らない)。最初の release を切る段階で `just bump-version` が両者を同期する。
- **CI で MOON_FEATURES 不要**: 現行 nightly は TOML 形式 `moon.mod` / `moon.pkg` を有効化する `rr_moon_mod` / `rr_moon_pkg` を default で ON にしており、明示 export は不要。

## 派生決定

立ち上げ時に評価器設計と同時に決めるとした 2 件は以下で確定:

1. **破れ 2 の Pending 表現**: MDR-002 §2 で案 B (Branch に Pending 追加、1 走査に統一) に確定。破れ 1 の解消設計 (CPS 化) も MDR-002 §1 に含む。
2. **予約語衝突の命名規約**: MDR-003 で末尾アンダースコア + wire rename 規約に確定。

## 関連

- [MDR-002](MDR-002-evaluator-core-design.md): 評価器コア設計 (破れ 1 の CPS 化 / 破れ 2 の Pending 統一 / モジュール分割)
- [MDR-003](MDR-003-reserved-word-naming.md): 予約語命名規約
- kawaz/kuu の ROADMAP (実装フェーズの正本)
- `slice` 枝: 垂直スライス PoC (凍結アーカイブ)
- `kuu-v0` 枝: 旧 kuu-cli 実装 (アーカイブ)
