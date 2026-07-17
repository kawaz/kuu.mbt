# package 分離 M1〜M4 の実施記録

DR-110 (spec 側の規範) と MDR-006 (`docs/decisions/MDR-006-package-separation.md`、実装設計・
里程標 M1〜M5) を正本に、`src/core` を `src/{engine,builtins,kuu}` へ分離する作業を M1〜M4 まで
進めた記録。全実装は codex-sol worker への委譲、統括セッションは監査・lockstep push に専念する
体制で回した。

## M1: 物理骨組み (`78d63a09`)

`src/core` を `src/{engine,builtins,kuu}` へ物理分離。21 mbt ファイルを byte-identical のまま
移設し、conformance runner を kuu package 内の wbtest として持たせた。kuu-cli 側は
`@core` → `@kuu` の import 116 箇所を機械 rename して lockstep 追随 (kuu-cli main `59161ad6`)。

## M2: NodeExt/Resume/Ext(&NodeExt) 契約完成 (`af62c9634149`)

Node を open 化し、`NodeExt` / `Resume` / `Ext(&NodeExt)` の契約を完成させた。値の住人 7 種 +
マーカー 3 種を Ext 化し、Eq は手書き実装に切り替えた。物理移動 (実ファイルの package 跨ぎ) は
Ty 連鎖への依存があるため M3 に持ち越し、M2 では契約完成のみで縮退承認とした。

codex-sol-reviewer によるレビューで重大な指摘 2 件が実機再現された: downstream の Pending が
誤って別状態に変換される経路、および zero-token の反復 (Many 系) が SIGSEGV を起こす経路。
いずれも修正 + 回帰テストの pin まで同一 commit に含めている。

## M3: 依存矛盾による順序入れ替え (M3c → M3a → M3b)

計画時点の順序 (M3a → M3b → M3c) では `Entity.ty` / `Cand.ty` が `Ty` を運ぶ依存が解けず、
`TypeExt` 契約を先に完成させないと evaluator / matcher の物理移動が進まないことが判明したため、
M3c → M3a → M3b の順に入れ替えて実施した。

- **M3c** (`c469aac6538a`): `TypeExt` 住人 8 種を新設して `Ty` enum を除去、`Cand.ty` を String
  化した
- **M3a** (`d9fb287287f6`): evaluator 骨格を engine package へ移動し、Registry を配線した。
  複数回の監査指摘を受け、Registry の役割を「組成表のみ」から「lowering 時の型名解決」へ広げ、
  未知型は definition-error として扱うよう修正。`canonical_registry` は非 pub 化、`TypeExt` の
  encode は identity 変換に統一した
- **M3b** (`e13627a40511`): `MatcherExt` (candidates 契約の拡張を含む) を新設し、eq-split /
  short-combine の住人化を完了した

M3 全体は spec fixture pin bump commit (`09af10c38963`) まで進み、kuu-cli 側は `Cand.ty` の
String 直用 + engine import への追随で lockstep した (kuu-cli main `81add8d9aa2b`)。

### 並行裁定 2 件の同乗

M3 の lockstep push に、別スレッドで進めていた裁定 2 件を同乗させた:

- **EXP-Q1**: 異なる default 値を持つ経路の共露出を ambiguous と扱う裁定 (kawaz 裁定 c+b)。
  実装は `04220fb9741b`
- **TY-Q1**: candidate wire キーを `ty` → `type` にリネームする裁定 (kawaz 裁定「言語制約由来で
  spec を制限しない」)。pin bump は `576bdc255afb`

## M4: builtins への機能分散 (`d34807259e03`)

- **M4a**: canonical lexicon / filter pipeline / config_to_value を builtins package へ移動し、
  engine が parser を直接参照しない構成にした。`FilterArg` は `NodeExt` に置き換え
- **M4b**: `InstallerExt` trait + 住人 13 種を新設し、閉じた enum `Installer` と
  `full_installers` を廃止した
- **M4c**: 定義時検査 20 本を各住人へ分散し、汎用の 2 本のみ engine に残した。`DefsView` は
  全体を read-only で見る構成にした
- **M4d**: `InstallerExt::decode` と `allowed_keys` を、登録済み住人の vocabulary の和として
  再構成した

M4 完遂時点の検証値: conformance 273/665/0/0 (decoded/ran_cases/skipped/mismatches)、
moon test 380/380。

## 運用知見: worker の context 死とその対策

M1〜M4 の期間中、codex-sol worker の context 死が 4 回発生した (codex preset の実効 context は
~120k 程度で、里程標 1 個の作業量でほぼ使い切る)。これを受けて以下の運用を確立した:

- **1 worker 1 里程標 + fresh spawn**: 里程標をまたいで同一 worker を使い回さない
- **分割 commit の早期固定**: 里程標内をさらに細かく commit で固定しておくと、worker が死んでも
  引き継ぎコストが低い
- **残量の自主申告条項**: worker 自身に残り context の見積もりを申告させ、危険域で作業を止めて
  引き継ぎ資料を残させる

この対策により、後半の m3a-closer / m3b-matcher の 2 worker は自主申告と完走に成功した。

読み取り専用のはずの監査作業で `moon info` の副作用により mbti ファイル 3 本が生成される事故が
1 件発生し、当該 writer 側で掃除した。

## 残作業

M5 (sentinel の内部化、accumulator registry、Entity 最小化、front_door の assembly 化、pub
三分類の棚卸し、conformance blackbox 最終化、および mbti/justfile の CI drift gate 整備 —
`docs/issue/2026-07-17-mbti-justfile-ci-drift-gate.md` 参照) が未着手で残っている。M5 には
kuu-cli 側の破壊的変更第 3 波 (`is_sentinel` 導入 + 手元走査の置き換え) が伴う見込み。
