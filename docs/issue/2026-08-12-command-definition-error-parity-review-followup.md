---
title: command 担体の definition-error パリティ + 残余レビュー指摘 (DR-133/134 実装レビュー 2026-08-12)
status: open
category: task
created: 2026-08-12T12:38:27+09:00
last_read: 2026-08-12T14:41:50+09:00
open_entered: 2026-08-12T12:38:27+09:00
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

# command 担体の definition-error パリティ + 残余レビュー指摘 (DR-133/134 実装レビュー 2026-08-12)

## 概要

DR-133/134 実装 (commit 61715d3c) のレビューで見つかった 3 件の指摘をまとめて記録する。

1. **M1 = command 担体の definition-error 検査未合流**
   command 担体 (value/default/default_fn) が element 系 definition-error 検査を素通しする。
   `lowering.mbt` の `collect_default_fn_errors` (:4016) / `collect_scalar_array_default` (:5473)
   は options/positionals しか歩かず、command の default+default_fn 併用・default_fn 名の
   UnknownVocab・sentinel 戻り検査・observes cycle graph 不参加が全部素通しになっている。
   DR-134 §5「値供給は既存 node 意味論のまま」から導出可能なので裁定不要。command 担体を
   疑似 ElementDef として既存検査群に合流させるか、専用検査を足す。spec 側 fixture
   (`definition-error/` に command 版) も要る。
   配列 value と透過 value command は spec の CVQ-Q1/Q2 裁定待ちで本 issue のスコープ外。

   **進捗 (2026-08-12)**: 実装完了。commit af7a1a3c、Release v0.0.28 で push 済み、737 tests green。
   配列 value 系 (collect_scalar_array_default への合流) は CVQ-Q1/Q2 裁定待ちのまま未着手で残る。

2. **m1 = committed 判定から Link 由来供給が漏れる**
   `resolve.mbt:4817` の committed 判定 (`source is Cli|Env`) から Link 由来の供給が漏れている。

   **実測結果 (2026-08-12): 再現、Q 化が必要。** `config_file` 要素 `config` と、CLI 入口
   `config-link` (`link: "config"`) を同一 definition に置いた。一時 fixture の要点は次のとおり:

   ```json
   {
     "definition": {"options": [
       {"name":"config","type":"config_file","long":true},
       {"name":"config-link","type":"string","long":true,"link":"config"},
       {"name":"port","type":"number","long":true,"config_key":["port"],"default":7}
     ]},
     "cases": [
       {"args":["--config-link","/linked.toml"],
        "config_files":{"/linked.toml":{"port":41}},
        "expect":{"outcome":"success","effects":[],"result":{"port":41},"sources":{"port":"config"}}},
       {"args":["--config-link","/missing.toml"],
        "config_files":{"/other.toml":{"port":99}},
        "expect":{"outcome":"success","effects":[],"result":{"port":7},"sources":{"port":"default"}}}
     ]
   }
   ```

   リポ外の `$PROBE_FIXTURES` に上記 fixture を置き、公開 API を通す conformance runner を実行した:

   ```console
   $ KUU_FIXTURES="$PROBE_FIXTURES" moon test --target native \
       src/kuu/json_conformance_test.mbt -f 'conformance: fixtures*'
   [json-conformance] decoded=1 ran_cases=2 skipped=0 mismatches=0
   [json-conformance] decoded: config-link-target.json
   Total tests: 1, passed: 1, failed: 0.
   ```

   これにより wire decode、definition lint、parse、resolve の全経路を通って
   `config_file` セルを Link target にできること、readable path は provider に渡されて
   `port=41@config` として効くこと、同じ CLI 入口からの unreadable path は Error にならず
   `port=7@default` へ黙認されることを観測した。

   `config_file` の内部セルは公開 `effects` / `result` / `sources` から除外されるため、通常出力では
   path binding 自身の source を表示できない。そこでリポ本体を変更せず `$PROBE_COPY` に作業ツリーを複製し、
   同 package の一時 wbtest から `ParsedBindings.raw` を直接検査した:

   ```console
   $ moon test --target native src/kuu/link_config_source_probe_wbtest.mbt
   key=config
   value=/linked.toml
   source=Link
   Total tests: 1, passed: 1, failed: 0.
   ```

   probe は `binding.key == "config"`、`binding.value == String("/linked.toml")`、
   `binding.source == Link` も assertion している。したがって CLI で明示した値でも Link 越しの最終 source は
   `Link` であり、現行の `source is (Cli | Env)` から実際に漏れる。その結果、provider の読込失敗が
   committed Error にならず黙認される。

   DR-031 §「各順位の根拠」は CLI/link をともに「今この実行で明示的に言った」同順位の値源とし、
   §「source の確定ルール」は Link 越しの効果を `link` とする。DR-121 §4 も `link` を CLI 直下の
   独立した値源タグとして維持する。一方、DR-133 §3 の committed 規定は `cli / env 明示` とだけ書く。
   Link が config path を供給できる実態に対し、この列挙へ `link` を含めるかを明文化する Q 化が必要である。

3. **m3 = 内部セル negative list の (path,name) 同定不備**
   内部セルの negative list が (path,name) で同定されているため、config_file と同名の
   通常要素が同スコープに並ぶと、実セルの binding/[] が巻き添えで落ちる (既存欠陥)。
   `resolve.mbt:1055` / `resolve.mbt:1329` 参照。

レビュー出典: fable5-high 2026-08-12。レビュー担当の指摘は実物照合済み。

## 背景

DR-133/134 (config_file 担体・command 担体まわり) の実装レビューで見つかった残余指摘。
M1 は definition-error 検査のパリティ欠如、m1/m3 は既存の細部欠陥。

## 受け入れ条件

- [x] M1: command 担体の default+default_fn 併用・default_fn 名 UnknownVocab・sentinel 戻り検査・
      observes cycle graph が element 系検査と同等にカバーされる (spec fixture 込み)
      (commit af7a1a3c、v0.0.28。配列 value 系は CVQ-Q1/Q2 裁定待ちで未着手)
- [ ] m1: Link 由来供給が committed 判定に含まれるべきか実測 + 必要なら Q 化
- [ ] m3: config_file と同名の通常要素が同スコープに並んでも実セルの binding/[] が巻き添えで
      落ちないよう negative list の同定方法を修正

## TODO

<!-- wip 時のみ -->
