// Public warning ABI.

///|
/// One `warnings[]` entry (spec CONFORMANCE §2 warnings 面: kuu-cli の JSON wire は
/// `{"element": <name>, "kind": <kind>}` のオブジェクト配列で返す)。`kind` は現状 `"deprecated"`
/// のみ (spec DR-058)、将来の warning 語彙 (`lint` 等の DR-021 系譜、DR-047 §7 診断モード)
/// が増えたときに variant を拡張しやすいよう、名前ペアを型として運ぶ (kuu-cli PoC codex レビュー
/// 2026-07-15 の M-1 解消 — 素の element name 配列だと kind 情報が落ちるため、下流の JSON
/// 射影に kind を持たせられない)。
pub(all) struct Warning {
  element : String
  kind : WarningKind
} derive(Eq, Debug)

///|
/// The warning vocabulary (spec DR-058: `deprecated` only for now; the enum leaves room for
/// the DR-021/DR-047 §7 lint lineage without stringly-typed kinds on the public face).
pub(all) enum WarningKind {
  Deprecated
} derive(Eq, Debug)
