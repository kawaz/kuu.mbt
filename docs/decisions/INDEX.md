# MDR Index

kuu.mbt (kuu 仕様の MoonBit 参照実装) の Design Record 一覧。各 MDR の Status / 未決事項は本体ファイルを参照。

DR 番号空間は **MDR-NNN** (MoonBit DR、3 桁)。仕様側 DR (kawaz/kuu の DR-NNN) とは別系統で、仕様 DR は複製せず「kawaz/kuu の DR-NNN」形式で参照する (MDR-001 §3)。

## 立ち上げ

- [MDR-001](MDR-001-bootstrap-policy.md): 参照実装の立ち上げ方針 — 責務境界の明示分離 (評価器コアはゼロから再設計、葉/installer は移植)、破れ 2 件が評価器設計の入力、MDR 空間 + 仕様 DR 参照方針、moon 最小開始、CI fixtures 供給 (並置 checkout + SHA pin)、台帳ゼロ開始。派生決定 2 件は MDR-002 / MDR-003 に確定

## 評価器コア

- [MDR-002](MDR-002-evaluator-core-design.md): 評価器コア設計 — 破れ 1 = CPS 化 (継続 `Cont` の defunctionalize + 完成判定メモ化、has_full を動的問いに変える) で解消、破れ 2 = 案 B (Branch に Pending 追加、parse と補完を 1 走査に統一、complete 専用走査は持たない)、モジュール分割 (node/value/matcher/cont/eval/resolve/outcome/installer の 8 ファイルで ROADMAP 4 フェーズをファイル境界に写像)。DR-060 (kawaz/kuu) との非矛盾を明記。却下案: スコープローカル境界 (原理的不可) / 全列挙後段フィルタ / 案 A (分離恒久化 + walk_scope)
- [MDR-003](MDR-003-reserved-word-naming.md): 予約語衝突の命名規約 — 末尾アンダースコア (`alias_`/`export_`/`inherit_`) + derive 型は `fields(rename=...)` で wire を spec 語彙に固定。実機検証済み (moon 0.1.20260629)。複合語 (`export_key` 等) はセーフ。却下案: ドメイン語言い換え

## 正面玄関 API

- [MDR-005](MDR-005-front-door-api.md): kuu-core 正面玄関 API — `AtomicAST` ハンドル (`root`+`registry` を束ねる不透明型) で `parse_definition`/`parse`/`complete` の 3 契約を spec 語彙に一致させる。wire JSON decode を `json_conformance_wbtest.mbt` から `wire_decode.mbt` へ昇格、conformance runner はこの production decoder をドッグフーディング。公開面は MoonBit の `pub` (フィールド非公開) による同一パッケージ内キュレーションで達成 (再輸出パッケージ分割は不採用)。既存低レベル `parse`/`complete` (Node 直渡し) は `parse_tree`/`complete_tree` に改名し単体テストが継続利用。却下案: 別名で正面玄関を実装 / Node を素で公開 / パッケージ分割 / Cand 専用公開型の分離
