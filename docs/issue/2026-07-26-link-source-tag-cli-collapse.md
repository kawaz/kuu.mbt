---
title: link を独立した値源タグとして報告する (現状 cli に畳んでいる、DR-121 §4 未追随)
status: open
category: bug
created: 2026-07-26T18:30:24+09:00
last_read: 2026-07-26T23:04:22+09:00
open_entered: 2026-07-26T18:30:24+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 自リポ TODO
---

# link を独立した値源タグとして報告する (現状 cli に畳んでいる、DR-121 §4 未追随)

## 概要

`link` (他要素の入口から link で飛んできた効果) を独立した値源タグとして報告する必要があるが、
現状 `cli` に畳んでいる。DR-121 §4 (LINKSRC-Q1=a、2026-07-26 裁定) に未追随。

## 背景

### 現状

`src/abi/value.mbt` の `Source` enum:

```moonbit
pub(all) enum Source {
  Cli // CLI explicit / link — highest seat (DR-031 #1)
  Env
  Config
  Inherit
  Tty
  Default
}
```

`Link` という値が存在せず、コメントで明示的に畳んでいる。

さらに `link` 属性自体も parse 面で decode されない:

```
定義: {"options":[{"name":"target","type":"string","long":true},
                  {"name":"alias-entry","long":true,"link":"target","value":"linked"}]}
→ {"kind":"malformed_definition","message":"option has unsupported key 'link'"}
```

DESIGN の共通ノード形には `"link": "<name>"` が載っている。

### 期待する挙動 (DR-121 §4 / DR-031)

- 自分の入口 (long/short/alias 等) からの効果 → `cli`
- **link 越しの効果** (他要素の入口から link で飛んできた) → `link`
- 両者はラダー同順位で、区別は経路の違いのみ

### なぜ必要か (用途)

alias の deprecated ペアで、canonical 入口と deprecated 入口が link で結ばれている場合:
**どちらから入っても結果は同じだが、deprecated な入口を使ったときに警告を出したい。**
値が同じでも経路が違うので、`sources` で区別できないとアプリ側が判定できない。

`warnings[].element` (DR-058 §2) は「どの canonical を使うべきか」を指す宣言面の情報であり、
「どの経路で入ったか」を値ごとに引く軸ではないので代用にならない。

## 受け入れ条件

- [ ] `Source` enum に `Link` を追加し、link 越しの効果を `Link` として報告する
- [ ] `link` 属性が parse 面で decode される (DESIGN の共通ノード形どおり)
- [ ] canonical 入口から発火 → `cli` / link 入口から発火 → `link` / 両方発火してあと勝ちで
      source が切り替わる、の 3 通りを wbtest で pin
- [ ] `export_key` で canonical cell を rename した場合も、result / sources のアドレスが
      正しく (DR-121 §1 の structured path で) 出る
- [ ] spec 側に fixture を追加 (`link` を source 値として持つ fixture は corpus に 0 件。
      この空白のため spec と実装の乖離が長く検出されていなかった)

## 関連

- spec `docs/decisions/DR-121-sources-result-address.md` §4 (link の独立タグ規定と用途)
- spec `docs/decisions/DR-031-value-source-precedence.md` (source 確定ルール「link 越しの効果 = link」)
- spec `docs/decisions/DR-098-*.md` §6 (7 語彙)
- spec `docs/decisions/DR-058-*.md` §2 (deprecated 警告、warnings[].element)
- spec `docs/CONFORMANCE.md` §2 の sources 語彙 / `schema/fixture.schema.json` の sources enum
  (どちらも 2026-07-26 に `link` を含む形へ更新済み)
- `src/abi/value.mbt` の `Source` enum
- 同時期の断面調査: spec `docs/issue/2026-07-26-projection-verification-structural-gaps.md`
