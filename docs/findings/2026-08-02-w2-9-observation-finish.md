# W2-9 観測面の仕上げ — effects 値空間 index の非負化、sources の座単位 re-tag、実行一本化の設計

> 対象: spec DR-127 §6 (観測面の正本)、DR-122 §3、DR-121 §4/§5、DR-130 §4.1/§5、
> kuu.mbt 計画 `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-9 行 / §3 (6)(7)。
> 実装: `src/abi/value.mbt` (`Binding.source_shadow` field 追加) /
> `src/internal/fold/cell_fold.mbt` (`CellSeats::resolved_residual`) /
> `src/kuu/front_door.mbt` (`projected_effect` の観測 path 差し替え) /
> `src/kuu/resolve.mbt` (`reshadow_at`、CLI seat fold の shadow 併走、`source_seats` の消費)。
> pin: `src/kuu/value_seat_wbtest.mbt` (+1 本、既存 5 pin を DR-127 §6 の正形へ更新)。

## 判明した事実

- **effects の値空間 index segment は解決済みの非負値になった** (DR-127 §6 統括裁定 3)。
  `--arr 1,2,3` の後の `link: "arr[-1]"` 発火は `effects=arr,arr[2]` と観測される。解決は
  `CellSeats::resolved_residual` (共有 fold) が発火時点の座の現在長で行う — 部分書きは要素を
  増減しないので書き込み前後で長さは同じ。定義字面が既に非負の index (`arr[0]`) はそのまま通る。
  観測アドレスの差し替え対象は `observation.path` の末尾 value_residual 長ぶんに限る
  (前半はセル空間の消費済み segment で定義時静的、DR-127 §6)。
- **解決できない残余は字面のままの best-effort。** 器不在の負 index 等は勝ち枝では枝ローカル
  fold (DR-127 §4.2、W2-8) が Reject 済みの形で、届くのは fold の保守的スキップ経路 (宣言を
  特定できないセル等) だけ — parse 相の観測は失敗で停止できない (W2-8 findings と同じ姿勢)。
- **sources の座単位 re-tag が入った** (DR-127 §6 / DR-122 §3)。部分書き (link) した座だけが
  `link` タグを持ち、他の座は産出発火のタグを保つ。時系列表行 4 (`--tr 1..5 --until 9`) は
  `sources={tr={since=cli,until=link}}`、array 要素は `--arr 1,2,3 --last 9` で
  `sources={arr=[cli,cli,link]}` — W2-7 申し送り 3 の whole-cell carrier (last-winner が全座へ
  写る) と W2-8 申し送り (b) が解消した。DR-130 §5 の null 座 null は不変
  (`align_sources_to_result` が result 主導で null を強制する既存経路をそのまま通る)。
- **配達の席は resolve 相 carrier の `Binding.source_shadow : ResultValue?` (optional、既定
  None)。** 座単位の由来は「複合 carrier における `source` (単一タグ) の複合値版」であり、
  carrier binding の責務に収まる — W2-1 の `observation` field と同型の拡張。parse 相の効果
  binding は常に None なので DR-038 の効果 identity (経路 counting) には従来 field だけが参加
  する。値残余の部分書きが 1 度も起きない carrier も None のままで、`source_seats` の scalar
  枝は None なら従来どおり last-winner の `value_source_shadow` — 既存 889 cases の不変は
  この構造で担保 (実測 889/0 不変)。
- **shadow の畳み方は CLI seat fold に併走する** (`resolve.mbt` の `seat_shadow`)。全セル書き
  (parser 産出 / fn ToValue / ToDefault) は shadow を None に戻す (= last-winner へ縮退、時系列
  行 3 の丸ごと置換がタグも丸ごと置換するのと同じ意味論)。部分書きは「書き込み前の複合値 ×
  直前 carrier の source」で prior shadow を起こし、解決済み residual path の座だけを当該
  binding の source で差し替える (`reshadow_at`)。複数の部分書きは座ごとに積み上がる
  (`sources={arr=[link,cli,link]}` の wbtest pin)。
- **value_filters / final_filters は carrier を spread (`{..b, value: v}`) で書き換えるため
  shadow は素通しする。** filter が複合値の構造を変形した場合の shadow との不一致は
  `align_sources_to_result` (result 主導) が吸収する既存防御のまま。

## 実行一本化の設計 (issue `2026-08-02-cell-fn-multi-fire-unify` の設計入力)

DR-114「発火時に 1 回」に対し、現行は effects 射影 (`projected_effect`) / 枝ローカル fold
(`branch_fold`、裁定前) / resolve 相 CLI seat の 3 者が同じ発火を独立に実行する。一本化の
設計方向を本窓で確定した (実装は後続窓 — 理由は末尾):

1. **実行体は「勝ち枝確定後の 1 回の fold 実行 + FiringRecord の記録」に集約する。**
   FiringRecord = 発火 1 件 (効果列上の binding 位置で同定) ごとの
   { 遷移結果 (ToValue の解決値 / Sentinel 種別 / 失敗)、解決済み residual segment 列、
   座単位 provenance の差分 }。effects 射影と resolve 相 CLI seat はこの record の**消費者**に
   なり、cell fn を呼ばない。
2. **値残余セル分は W2-8 branch fold の枝内実行結果を勝ち枝から引き継ぐ** (再実行しない)。
   branch fold は現行どおり値残余セルだけを畳む (既存経路の走査コスト不変)。値残余の無い
   セル (素の `Invoke` = incr 等) は勝ち枝確定後の 1 回の fold が実行する — 枝選別に参加しない
   発火を全枝で実行するのは DR-114 が禁じる方向の悪化なので、per-branch には広げない。
3. **配達席は binding への optional stamp** (本窓の `source_shadow` と同じ形)。op / operand は
   不変 = DR-045 の効果の綴り (`op=invoke`) を保持し、DR-038 の経路同一性にも触れない —
   「binding の書き換え (Invoke → Set)」ではなく「解決結果の付記」。
4. **env/config 供給残差 (W2-4 findings §3.2、W2-8 申し送り (c)) は parse 入口への optional な
   Supplies (env / config provider) で閉じる。** `ToDefault` の落ち先 (DR-081 §2 の書き換え済み
   default = full ladder) が parse 相で解決できない構造問題は、供給を渡す以外に閉じ方が無い。
   未供給の呼び出し (現行の `ParsedBindings::effects(ast)`) は現行どおり宣言 default 止まりの
   観測 + resolve 相 fallback を保つ (公開 API の後方形は変えず、供給付きの形を足す)。
5. **resolve 相の残余分岐は最終防衛線として全判定を保持する** (W2-8 findings の分業のまま)。
   record の無い binding (fold の保守的スキップ / CLI 以外の供給経路) は resolve 相が従来どおり
   実行する — 一本化は「record がある発火を再実行しない」であり、防衛線の削除ではない。

**本窓で実装しなかった理由**: 1〜4 は `parse_tree` の Success payload / `ParsedBindings::effects`
/ conformance runner を跨ぐ公開 API 変更で、観測面 2 件 (非負 index / 座 re-tag) と独立に
land できる形に切れない (record の綴りが観測面の形に依存する)。観測面を先に正として固定した
本窓の成果物の上で、後続窓が FiringRecord を実装するのが順序として正しい。危険域
(value_residual × 非決定 Value fn) は現 corpus に発火例が無い (W2-8 findings) ため、遅延による
実害は第三者 resident の登録まで顕在化しない。

## 実用的な示唆 / 残余 (現在形)

- **spec fixture (6)(7) の値空間分は書ける状態になった。** sources の座 re-tag (6) と effects
  の値空間 path (7) の実装・wbtest pin が本窓で立ったので、DR-132 residents (record を名乗る
  builtin type = fixture/*) が入る #136 窓で conformance fixture へ移送できる (lockstep push)。
  観測の正形は本 findings の wbtest pin (時系列行 4 = `{since=cli,until=link}`、
  `arr[2]` / `[cli,cli,link]`) が実装側の正。
- **effects 射影の env/config 残差は未解消のまま** (W2-4 §3.2)。一本化設計 4 の Supplies が
  閉じ先で、issue `2026-08-02-cell-fn-multi-fire-unify` に統合済み。
- **cell fn の多重実行も未解消のまま** (同 issue)。本窓は設計確定まで — 受け入れ条件と設計方向
  を issue 側に反映した。

## 検証 (2026-08-02 実測)

- `just test` = 702 tests / 702 passed、conformance `decoded=396 ran_cases=889 skipped=0
  mismatches=0`。known_divergences / expected_skips 両台帳は空のまま。
- `moon check --deny-warn` green、`moon fmt` / `moon info` 適用済み (mbti 差分は `@abi.Binding`
  の `source_shadow` field と `@fold.CellSeats::resolved_residual` のみ)。
- 既存 pin メッセージの変更なし。既存 wbtest の期待値更新は 5 本 (すべて W2-7/W2-8 findings が
  「W2-9 で更新される」と予告した座): 時系列行 4 / set(null) 行 5 / incr / peeky の sources
  (link → cli の座復元) と、負 index の `effects=arr,arr[2]` + `sources={arr=[cli,cli,link]}`。
  新設 wbtest 1 本 (複数部分書きのタグ積み上げ + 非負 index 素通し)。

## 関連

- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §6 / DR-122 §3 / DR-121 §4/§5 / DR-130 §5
- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 W2-9 行 / §3 (6)(7)
- `docs/findings/2026-08-02-w2-7-vivify-and-seat-operations.md` 申し送り 3 (re-tag の出所)
- `docs/findings/2026-08-02-w2-8-branch-local-fold.md` 申し送り (a)(b)(c) (本窓の入力)
- `docs/findings/2026-08-02-w2-4-fold-unification.md` §3.2 (env/config 供給残差)
- `docs/issue/2026-08-02-cell-fn-multi-fire-unify.md` (一本化の正本 issue)
