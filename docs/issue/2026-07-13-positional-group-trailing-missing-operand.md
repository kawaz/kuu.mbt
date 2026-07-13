---
title: positional group の直後の positional がトークンを取れず missing_operand になる
status: open
category: bug
created: 2026-07-13T09:33:53+09:00
last_read:
open_entered: 2026-07-13T09:33:53+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: kuu (spec リポ)
---

# positional group の直後の positional がトークンを取れず missing_operand になる

## 概要

positional group (`repeat: {min:1, max:1}`) の後ろに通常の positional が続く定義で、
group が 1 row 消費して閉じた後に背骨が次の positional へ進まず、後続 positional への
トークン割当てが行われないまま `missing_operand` failure になる。

## 背景

spec fixture 作成中の worker が、型シャドウ調査とは無関係の最小構成で再現 (2026-07-13、
plain string のみ)。

再現定義:

```json
{
  "positionals": [
    {
      "name": "grp",
      "repeat": { "min": 1, "max": 1 },
      "positionals": [
        { "name": "gflag", "type": "string" }
      ]
    },
    { "name": "ctrl", "type": "string" }
  ]
}
```

argv `["a", "b"]` を与えると:

- 期待: `grp=[{gflag:"a"}]`, `ctrl="b"` の success
- 実際: `ctrl` に対する `missing_operand` failure

切り分け:

- group を単独 (後続 positional なし) にすると正常
- group を後ろ・`ctrl` を前に置くと正常
- つまり「group の後ろに positional が続く」構成だけで壊れる

spec 導出上は group は `repeat.max: 1` で 1 row 消費後に閉じ、背骨が次の positional へ
進むべき (DESIGN §6.1 / §15)。関連シンボル: `dec_positional_group` / 背骨進行
(`src/core/eval.mbt`)。

回避策として、後続 positional を group の前に置く配置を採用している箇所がある
(`fixtures/value-typing/positional-group-factory-config.json` 系、why コメント明記の上)。

## 受け入れ条件

- [ ] spec 側に輪郭 fixture (group + 後続 positional の組合せ) を追加して現象を pin する
- [ ] 実装側 (`src/core/eval.mbt` の背骨進行 / `dec_positional_group`) を修正する
- [ ] 上記修正後、回避配置 (group を末尾に置く workaround) を解除する
