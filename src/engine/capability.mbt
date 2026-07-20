// capability.mbt — DR-113 §1 の help_query に代表される、installer 3 役の「能力提供」面を
// registry に載せるための最小 trait と登録経路。
//
// DR-113 §1 は installer 3 役 (回収 / 植え付け / 能力提供) を help 機構に当てはめ、
// help_installer が「宣言層寄与適用後の断面から help model を組む help_query capability」を
// 提供すると規定した。同型の能力 (例: 将来の complete_query / diagnose_query) も同じ registry
// スロットで宣言・lookup できるように、capability を独立枠として persistent に持つ。
//
// このファイルは器のみ。invoke シグネチャは capability ごとに異なる (help_query は
// (ast, path, depth, category_mode) → Result[HelpModel, HelpQueryError] の形) ため、trait 側で
// generic な invoke を強制しない — Registry で name → &CapabilityExt を lookup し、呼び出し側は
// 具体型に downcast (or 具体的な singleton を経由) して invoke する形。M3c 段階では登録経路
// だけを整え、fixture runner の invoke 経路への統合は M4 で差し替える。

///|
/// Capability の最小契約。`name()` は名前空間内で一意な discriminator (fixture の `query`
/// フィールドと対応する。help_query は `"help_query"`)。同名 capability の重複登録は
/// register 側で false を返して黙って弾く (installers の overlap 検査とは違う運用 — capability
/// は 1 名前 1 実体を想定)。
pub(open) trait CapabilityExt {
  fn name(Self) -> String
}
