---
title: W2-2 実装の据え置きハイジーン 3 件 (F4/F6/F8)
status: open
category: task
created: 2026-08-02T10:00:21+09:00
last_read:
open_entered: 2026-08-02T10:00:21+09:00
wip_entered:
blocked_entered:
pending_entered:
discarded_entered:
resolved_entered:
discard_reason:
pending_reason:
close_reason:
blocked_by:
origin: 依頼元プロジェクト (kuu spec リポ, W2-2 レビュー)
---

# W2-2 実装の据え置きハイジーン 3 件 (F4/F6/F8)

## 概要

W2-2 (value_type 体系、`docs/research/2026-08-02-w2-2-value-type-model-design.md`) のレビューで指摘され、据え置いた実装内部品質の 3 件。conformance 挙動には影響しない。

1. **F4**: Union の `uniqueItems` 等価検査が `ValueType` 構造 Eq ベースになっており、Record のフィールド順違いを意味的同一と見なさない。順序違いの同型 union member が重複検査をすり抜ける。
2. **F6**: `builtin/` prefix の正規化が `Registry::resolve_type_reference` と engine 側の 2 箇所に二重実装されており、片側だけ変更すると drift する。
3. **F8**: `ValueType::declaration_violations` は違反を全件返すが、`DefError` の message には `violations[0]` しか載らず、複数違反時の可視性が低い。

## 背景

W2-2 実装レビュー時にこれらの問題を発見したが、いずれも conformance テストの合否には影響せず、実装内部の保守性・可視性の課題にとどまるため、W2-2 本体の完了を優先して据え置いた。W2-5/W2-6 等の周辺作業時に併せて解消するのが妥当と判断。

## 受け入れ条件

- [ ] F4: Union の uniqueItems 等価検査が Record フィールド順の違いを正しく意味的同一として扱う (または順序正規化してから比較する)
- [ ] F6: `builtin/` prefix 正規化ロジックを 1 箇所に集約し、Registry と engine の双方がそこを参照する
- [ ] F8: `DefError` の message が `declaration_violations` の全件 (または件数を示すサマリ) を含む
