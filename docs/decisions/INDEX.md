# MDR Index

kuu.mbt (kuu 仕様の MoonBit 参照実装) の Design Record 一覧。各 MDR の Status / 未決事項は本体ファイルを参照。

DR 番号空間は **MDR-NNN** (MoonBit DR、3 桁)。仕様側 DR (kawaz/kuu の DR-NNN) とは別系統で、仕様 DR は複製せず「kawaz/kuu の DR-NNN」形式で参照する (MDR-001 §3)。

## 立ち上げ

- [MDR-001](MDR-001-bootstrap-policy.md): 参照実装の立ち上げ方針 — 責務境界の明示分離 (評価器コアはゼロから再設計、葉/installer は移植)、破れ 2 件が評価器設計の入力、MDR 空間 + 仕様 DR 参照方針、moon 最小開始、CI fixtures 供給 (並置 checkout + SHA pin)、台帳ゼロ開始。未決 2 件 (破れ 2 の Pending 表現 / 予約語命名規約)
