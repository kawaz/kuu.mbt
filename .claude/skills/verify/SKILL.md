---
name: verify
description: kuu.mbt の公開 package API を外部 MoonBit consumer から実行検証する
---

# kuu.mbt public API verification

公開 API の変更は、リポ内 test ではなく scratchpad の別 MoonBit module から package 境界越しに実行する。

1. scratchpad に `moon.mod.json` を作り、`deps["kawaz/kuu"].path` をこのリポの root に向ける。
2. `moon.pkg.json` で `kawaz/kuu/kuu` と、戻り値の match に必要な `kawaz/kuu/engine` を import する。
3. `main.mbt` から `@kuu.parse_definition` → `@kuu.parse` → 必要なら `@kuu.resolve` → 対象 API を呼ぶ。
4. scratch module で `moon run --target native .` を実行し、公開型の field 読み取り・結果値を stdout で観測する。
5. happy path に加え、内部 marker、同名別 scope、空/未発火など変更に隣接する境界を 1 つ以上実行する。

scratchpad の consumer は一時検証物であり、リポへ commit しない。
