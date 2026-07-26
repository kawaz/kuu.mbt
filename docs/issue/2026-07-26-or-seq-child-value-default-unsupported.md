---
title: or/seq の structural child が value/default 等を持てない (schema と DR-067 に未追随)
status: open
category: bug
created: 2026-07-26T14:35:34+09:00
last_read: 2026-07-26T21:23:04+09:00
open_entered: 2026-07-26T14:35:34+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec) プロジェクトからの起票
---

# or/seq の structural child が value/default 等を持てない (schema と DR-067 に未追随)

## 概要

`or` / `seq` の子ノードに `value` や `default` を書くと decoder が
`or branch leaf has unsupported key 'value'` で弾く。しかし spec 上これは合法。

`src/kuu/wire_decode.mbt` の `dec_or_leaf` が structural child を
`type` / `name` / `value_name` のみに制限しているため。

## 背景

### spec 上は合法である根拠

- **`schema/wire.schema.json` の `node`**: 「root (= root command node) も **or/seq の子も**
  command 部分木も同型 (DR-017、DESIGN §4.3)」と明記。node は `value` / `default` を持つ
- **DESIGN §5.2**: `value:` / `default:` は「**消費しない literal**」
  (`{"type":"number","value":30}` は消費 0 の実体だけノード)
- **DR-067 §2**: child 内の `multiple` / `repeat` を合法とし、構造属性の直交を明記。
  structural child が持てるキーを型/名前だけに絞る規定はない

### 再現

```json
{"options":[{"name":"pair","long":true,"seq":[
  {"type":"string"},
  {"type":"string","value":"fallback"}]}]}
```

```
$bin parse def.json --no-env --no-config -- --pair x
→ {"ok":false,"errors":[{"kind":"malformed_definition",
    "message":"or branch leaf has unsupported key 'value'"}]}
```

spec どおりなら `result={"pair":["x","fallback"]}` になるはず
(DESIGN §5.1 が seq を「子の値の配列」と規定、`value` の子は消費 0 で literal を産出)。

### なぜ重要か (spec 側の裁定に効く)

この定義が書けると、**nameless child が異なる値源から値を得て共存する**構成になる
(`x` は cli 席、`fallback` は default 席 — DR-031 が別席として固定)。

spec 側で「配列要素ごとの provenance を公開するか」を裁定中
(`kuu (spec)` の `docs/QUESTIONS.md` の SRCADDR-Q2-β、および
`docs/issue/2026-07-26-array-element-provenance-sources-addressing.md`) で、
**この到達可能性が裁定の分岐条件**になっている。

decoder が弾いていることを「到達不能だから cell 単位の provenance で閉じてよい」の
根拠にしてはいけない — 実装追随 gap であって仕様の制約ではない。

## 受け入れ条件

- [ ] `or` / `seq` の structural child が schema の `node` 定義どおりのキーを受け付ける
      (最低限 `value` / `default`。他に落としているキーがないか `dec_or_leaf` と schema を突き合わせる)
- [ ] 上記の再現定義が `result={"pair":["x","fallback"]}` を返す
- [ ] 落としていたキーの一覧と、それぞれが通るようになったことを wbtest で pin
- [ ] spec 側に fixture を足すか判断する (要素 provenance の裁定と連動するので、
      裁定後に spec 側で fixture 設計する方が筋かもしれない)

## 関連

- `src/kuu/wire_decode.mbt` の `dec_or_leaf`
- spec `schema/wire.schema.json` の `$defs.node` (同型規定)
- spec `docs/DESIGN.md` §5.1 (seq は子の値の配列) / §5.2 (消費しない literal)
- spec `docs/decisions/DR-067-wire-well-formedness.md` §2 (構造属性の直交)
- spec `docs/decisions/DR-031-value-source-precedence.md` (cli と default/value は別席)
- spec `docs/issue/2026-07-26-array-element-provenance-sources-addressing.md`
