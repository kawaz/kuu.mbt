# W2-4 差異表: 効果適用 fold 2 本を 1 本化したとき、どちらが規範に合っていたか

> 対象段: `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §2 の W2-4 行 /
> §4 リスク 3。実測日: 2026-08-02。
> ベースライン `just test` = 644 tests / conformance `decoded=394 ran_cases=885 skipped=0
> mismatches=0`、両台帳空。本段適用後 = **646 tests** (新規 2 本) / conformance は **同値のまま**。

## 0. 何を 1 本にしたか

一本化の対象は「効果列から **座 (cell) に今何が座っているか** を求める計算」である。従来これを
2 箇所が独立に持っていた:

| 実装 | 位相 | 状態の持ち方 | 何のために畳んでいたか |
|---|---|---|---|
| `src/kuu/front_door.mbt` `projected_effect` | parse 相の effects 射影 | `Map[String, @abi.Value]` (座 key → 値) | `Invoke` の `ctx.old` を供給し、cell fn を呼んで effect の op/operand を決める |
| `src/kuu/resolve.mbt` `resolve_entity_raw` の scalar 分岐 | resolve 相の CLI seat | `current : @abi.Binding?` + `committed_now` | 値源ラダー最上段の値を決め、下流へ返す binding を作る |

共通部分を `src/kuu/cell_fold.mbt` へ抜き出した。持たせたのは **値状態だけ**である:

- `SeatState` — 座の値状態 3 値 (`Seated(v)` / `Opened` / `Emptied`)
- `SeatTransition` + `fold_seat_effect` — 効果 1 件 → 値状態の遷移。**cell fn 呼び出しの唯一の実施点**
- `seat_after` — 遷移後の状態 (`ToDefault` の落ち先だけ呼び手のラダーが決める)
- `CellSeats` — 座の集合。読み書きの口は `value_at` / `set_at` の 2 つで、**座そのものは
  空 segment 列という特例**。値空間 (DR-127 §2.2) への部分更新は同じ口に segment 列を渡す形

**呼び手に残したもの**と、その理由:

- effects の op/operand の綴り (観測面の責務。`Invoke` だけが cell fn 結果で op が決まる、DR-114 §2)
- 解決済み binding の carrier 構築 (下流の `build_result` / `proj_sources` が op と source を
  そのまま読むための実装不変条件。規範ではない — DR-045 は効果を `{op, operand?}` の純データと
  定めるだけで、host 側がどの binding を運ぶかは規定していない)
- 値源ラダー (`resolve_ladder_below_cli`) の照会。effects 射影は resolve 相を持たないので引けない (§4)

### 0.1 値状態と carrier を分けたのが本段の設計上の核

旧 `resolve_entity_raw` は 1 個の `current : Binding?` に「セルの値」と「下流へ返す binding」を
兼ねさせていた。`Default` の binding の `value` は **op で解釈される placeholder であって値では
ない** (DR-045 が効果を `{op, operand?}` の純データと定めた帰結) ため、これを `old` として読むと
placeholder が漏れる。分離したことで F-4 (下表) が構造的に閉じた。

値の無い座を 2 状態に割ったのも同じ理由である。DR-114 §7 は old を「発火直前の cell 値、無ければ
absent」と定めるが、**「値が無い」には落ち先の違う 2 種類がある**:

- `Opened` — `unset` (null Value fn、DR-131 §2b) で席が開いた。ラダーが下段まで開くので old は
  宣言 default へ落ちる (fixture `multiple-parse/unset-opens-ladder-to-declared-default.json`)
- `Emptied` — `empty` Sentinel (DR-131 §7) で committed に空。セルは「空である」ことが確定して
  いるので old は absent

## 1. 差異表 — 発見した 4 件と、採った側の規範根拠

3 件とも **effects 側 (front_door) が規範から外れていた**。判定は `incr` (`ctx.old` を読む唯一の
builtin cell fn、`src/extension/cell_fns.mbt`) を使った実測で、一本化の前後を同じ定義・同じ args で
比べている。「effects の operand」と「result の値」が食い違えば差異である。

| # | 効果列 | 一本化前 effects | 一本化前 result | 一本化後 (両者一致) | 採った側 | 規範根拠 |
|---|---|---|---|---|---|---|
| **F-1** | subcommand scope 配下の `default: 5` セルへ `:incr` | `set(1)` | `6` | `set(6)` | resolve | DR-114 §7「effect mode では**発火直前の cell 値**が old」。effects 射影は root scope の entity しか引けず (`root_entity` が `binding.scope.length() > 0` で即 `None`)、scope 配下では宣言 default を見失って `old` が absent → `incr` が 0 起点になっていた |
| **F-2** | `:incr` → `clear:unset` → `:incr` | `set(6) set(null) invoke(-)` | `6` | `set(6) set(null) set(6)` | resolve | DR-131 §2b「`set(null)` = unset、席を開ける」。effects 射影は座に `null` を書き込んでいたため、次の `incr` が `Some(Null)` を受けて `invalid-range` で落ち、effect が operand なしの生 `invoke` に化けていた。席が開いた座の old は宣言 default (DR-114 §7) |
| **F-4** | `:incr` → `reset:default` → `:incr` | `set(6) default(-) set(7)` | `6` | `set(6) default(-) set(6)` | resolve | DR-081 §2「op=default は**その時点の書き換え済み default** をセルへ書く」。effects 射影は `Default` で座を更新しなかったため、次の `incr` が直前の 6 を old にしていた |

### 1.1 `empty` は scalar セルの fold へ合法には届かない (差異ではない)

REFERENCE の `cell_fns` 表の `empty` 行は「`Sentinel(Empty)` を返し、**array / map / record を**
committed=true で空にする。**scalar 等は definition-error `invalid-range`**」と規定する。collection
セルの値解決は accumulator resident (`resolve_cli`) が持ち本 fold を通らないので、**scalar seat の
fold に `ToEmpty` が届く合法な経路は無い**。したがって scalar fold はここで空セルの意味論を発明せず
`abort` する (W2-3 の `value_str` と同じ precedent — 不変条件違反を silent に通さない)。

ただし **`empty` の target 型検査を lowering が持っていない**ため、`{"type": "number", "long":
[":incr", "clear:empty"]}` のような不正定義が現状 definition-error にならず parse を通ってしまう。
これは本段が作った gap ではなく既存の未実装であり、`docs/issue/2026-08-02-cell-fn-empty-target-type-check-missing.md`
へ起票した (W2-5 / W2-6 の value_type 整備で閉じる想定。spec 側にも
`fixtures/definition-error/` の case が要る)。

effects 射影側 (`projected_effect`) は collection セルの `empty` も通るので `ToEmpty` を扱い続ける。
その座の `old` は本来「型別の空値」(`[]` / `{}`) だが、供給する consumer がまだ居ない
(accumulator セルへ `ctx.old` を読む fn を置く定義 = `multiple` × `update` は `parse_definition`
時点の definition-error) ため、store は absent を返す。consumer が入る段で差し替える。

### 1.2 差異が既存 885 cases に 1 件も出なかった理由

4 件とも「`ctx.old` を読む cell fn が、`default` / `empty` / `unset` / scope 配下の非ゼロ宣言
default と組み合わさる」形でしか露出しない。fixture 側の `incr` 利用は `count` preset
(`count-parse/basic.json` / `env-coexistence.json` / `final-filter-range.json`) だけで、count preset の
宣言 default は **0 固定**である。`incr` は `ctx.old()` の absent を 0 として扱う
(`incr_fn` の `None => 0.0`) ので、**old が absent か `Number(0)` かを区別できない** —
F-1 の scope 差はここに吸われて観測不能だった。F-2 / F-4 は count preset に `unset`/`default`
variant が無いので組合せ自体が現れない。

したがって本段は「conformance 上は不可視だった 3 件の乖離を、可視化せずに閉じた」ことになる。
可視化 (fixture 化) は複合値の産出者が入る W2-5 以降と同じウィンドウでよい (§5)。

## 2. 差異ではなかったもの (照合して同値を確認した全件)

「網羅性の主張が価値を持つ」表なので、**差異が無かった軸も明示する**。

| 軸 | front_door | resolve | 判定 |
|---|---|---|---|
| `Set` の座更新 | `current.set(key, value)` | `current = Some(b)`、committed | 同値 (`ToValue(binding.value)`) |
| `Invoke` → `Value(v)` (非 null) | 座へ `v`、effect は `set(v)` | carrier `{..b, op: Set, value: v}`、committed | 同値 |
| `Invoke` → `Value(Null)` の **committed** | (committed の概念なし) | `committed_now = false` | 一本化後も `false` (DR-045 の `is_committed` が「`Set` かつ値 null は committed でない」とするのと同じ規則) |
| `Invoke` → Sentinel の effect op | `UseDefault`→`default` / `Empty`→`empty`、operand なし | (effect を作らない) | 変更なし |
| cell fn 未登録 / 失敗時の effect | 生の `Invoke` op、operand なし、座は不変 | `unknown-vocab` / 当該 reason で **Err** | **両立させた** — 遷移 `FnMissing`/`FnFailed` を返し、失敗時に座を触らないのは共通、Err にするかは呼び手の方針として残す (effects 射影は parse 相の観測なので解決失敗で止まれない) |
| 同一セルの複数発火 / 複数セルの交互発火 | 座 key ごとに独立 | entity ごとに独立 | 同値 (実測: `--n --m --n` が `set(6) set(8) set(7)` / result `{m:8, n:7}` で前後不変) |
| `Remove` / `Splice` | `Remove` は座を更新、`Splice` は不変 | 両方 `abort` (scalar seat には届かない、DR-080 §1) | 差異なし。共有 fold は `Remove`→`ToValue` / `Splice`→`NoChange` に写し、resolve 側は呼び出し**前**に防御 abort を置いて到達しないことを保つ |
| `empty` (scalar target) | `ToEmpty` を扱う (座を空へ) | 旧: carrier `Some(b)` で placeholder が old へ漏れる | **差異ではなく不正定義** (§1.1)。scalar fold は `abort` へ倒し、effects 射影側は collection セルのために `ToEmpty` を扱い続ける |
| accum セル (`e.accum is Some`) | 座 key は同じだが `old` を読む住人が居ない | 専用分岐 (`resident.resolve_cli`) で本 fold を通らない | 対象外。`multiple` × `update` は `parse_definition` 時点の definition-error なので、accum セルで `ctx.old` を読む経路が構造的に無い |

## 3. 一本化前後で意図的に変えなかったもの (残差)

### 3.1 carrier 構築の非対称は resolve 内に残る

`Default` op が発火してラダーが値を返したときの carrier は
`@abi.Binding::new(e.name, value, b.source)` で、`Invoke` → `Sentinel(use_default)` の同じ状況では
`{..b, op: @abi.Set, value}` である。前者は `scope` / `link_selections` / `observation` / `at_pos` を
落とし、後者は保つ。**同じ「default 席へ戻す」意味に 2 通りの carrier があるのは非対称**だが、
carrier 構築は本段の対象 (値状態の fold) ではなく、揃えると DR-121 §4 の link 経路保存に影響が
出るため触っていない。W2-9 (sources の座 re-tag) が同じ場所を触るので、そこで判断するのが自然。

### 3.2 effects 射影の `ToDefault` は宣言 default までしか引けない

`project_effects` は parse 相の射影で env / config を受け取らない (`ParsedBindings::effects(ast)` は
parse だけで完結する公開 API)。したがって `default` 効果の落ち先として引けるのは**宣言 default
だけ**で、resolve 側の `resolve_ladder_below_cli` (env > config > 宣言 default) と一致しない。

- **env / config が当該セルへ供給していない場合は一致する** (F-4 の実測がこの形)
- 供給がある場合、`default` 効果の**後続**の `ctx.old` 依存 fn で effects と result がずれうる

この残差を閉じるには `project_effects` へ env / config を渡す = 公開 API のシグネチャ変更が要り、
本段の「挙動完全不変」と噛み合わない。**未検証のまま残す部分ではなく、構造的に閉じられないと
分かっている残差**として記録する。W2-9 の観測面仕上げで公開 API ごと判断するのが妥当。

### 3.3 3 つ目の fold が `internal/engine` に居る

`src/internal/engine/eval.mbt` の `is_committed` / `is_committed_in_subtree` /
`element_value` / `element_value_in_subtree` も効果列を畳んで「セルが committed か / 値は何か」を
答える (constraint 評価、DR-055 / DR-047)。規則は `Set if value is Null => committed = false; _ => true` で、
**`Invoke` は cell fn を呼ばずに committed 扱いする** (呼べない — parse 相で、まだ発火していない)。
`has_pending_invoke` が「まだ確定していない `Invoke`」を別枠で見るのはこの構造への手当てである。

本段で 1 本化できなかったのは **package 依存の向き**による: `internal/engine` は
`kawaz/kuu/kuu-node` (cell fn registry を持つ `Registry`) を import しておらず、共有 fold は
`Registry` を要る。engine から呼べる形にするには registry の置き場から動かす必要があり、
W2-4 の射程を超える。DR-127 §4.2 の枝ローカル fold (W2-8) は **まさに `eval.mbt` に置く**段なので、
そこで「engine 側から共有 fold を呼べるようにするか、eval.mbt の committed 判定を parse 相専用の
別概念として明示分離するか」を決める必要がある。**W2-8 の設計入力。**

## 4. 座への部分更新 API (`CellSeats::value_at` / `set_at`)

DR-127 §2.2 の値空間降下と §3 の vivify が使う唯一の入口。本段では**器を作らない** — vivify は
W2-7 の責務なので、未 vivify の座は失敗を返す。

| 入力 | 結果 |
|---|---|
| 空 segment 列 | 座そのもの (read は座の値、write は座への set。`CellSeats::put` の `Seated` 書き込みもこの口を通る) |
| 値の無い座へ segment 列 | `SeatAbsent` (器を作らない) |
| スカラ座へ segment 列 | `SeatNotContainer` |
| `Object` 座 × 不在フィールド | `SeatMissingField(name)` |
| `Array` 座 × 非負 index | 当該要素 |
| `Array` 座 × 負 index | 長さで正規化 (DR-127 §6 の「解決済み非負 index」の解決側)。`-1` = 末尾 |
| `Array` 座 × 正規化後も範囲外 | `SeatIndexOutOfRange(index)` — **字面の index** を載せる (診断は利用者が書いた綴りを指す) |
| 入れ子 (record → array → record) | 途中の段で外れたら **その段の** 失敗が返る (先頭段の診断へ潰さない) |

write は元の値を変えず差し替え済みの新しい値を作る (`value_with_at`)。兄弟フィールド / 兄弟要素は
保たれることを wbtest で pin 済み (`src/kuu/cell_fold_wbtest.mbt`)。

## 5. 後続段への申し送り

1. **W2-8 は §3.3 を先に決める。** `eval.mbt` の committed fold を共有側へ寄せるか、parse 相専用の
   別概念として分離するか。3 つ目の fold を足す段そのものなので、ここを曖昧にしたまま実装すると
   本段が閉じた乖離が別の形で復活する。
2. **F-1 / F-2 / F-4 は conformance に 1 件も出ていない。** wbtest (`cell_fold_wbtest.mbt`) が唯一の網で
   あり、他実装が読む規範ではない。`ctx.old` × `default`/`unset` の組合せは
   fixture 語彙として存在しうる (count preset に variant を足すだけで書ける) ので、
   W2-5 / W2-9 で複合値の fixture を起こすウィンドウで一緒に落とすのが安い。
3. **§3.2 の残差は `project_effects` の公開 API 形と一体**。W2-9 が effects の `path` を触るので、
   同じ段で env/config 供給の要否を判断する。
4. **W2-7 (vivify) は `CellSeats::set_at` の signature と契約を拡張する段**になる。現在の
   `set_at` は「segment 列を辿って既存の座を差し替える」だけで、DR-127 §3 が vivify の条件と
   する 2 つの情報を**受け取っていない**:

   - **ValueType** — 「器 `{}` を record 段まで auto-vivify、`map` / `value` / 宣言なしは枝
     Reject」は、その座の宣言型を知らないと判定できない。今の `set_at` は実行時の `Value` の
     形しか見ない (`SeatNotContainer` は「今スカラが座っている」であって「型が primitive」ではない)
   - **op gate** — vivify は `set` 専用 (DR-127 §3)。今の `set_at` は呼び出し元の op を知らない

   したがって W2-7 は「`SeatAbsent` / `SeatMissingField` を器生成へ倒す」だけの差分にはならず、
   `set_at(key, path, value)` → `set_at(key, path, value, value_type~, op~)` 相当の契約拡張が要る。
   本表の 7 行はその拡張後にどの入力がどちらへ分岐するかの一覧として使う。

## 関連

- `docs/research/2026-08-02-dr127-wave2-implementation-plan.md` §1.4 / §2 W2-4 行 / §4 リスク 3
- `docs/findings/2026-08-02-w2-3-value-composite-inventory.md` (複合 `Value` の consumer 全数表)
- spec `docs/decisions/DR-114-universal-fn-integration.md` §7 (`ctx.old` の規範)
- spec `docs/decisions/DR-131-sentinel-reduction.md` §2b / §7 (`unset` = null Value / `empty` Sentinel)
- spec `docs/decisions/DR-081-default-seat-rewrite-and-source.md` §2 (op=default の落ち先)
- spec `docs/decisions/DR-045-effect-descriptors.md` (効果語彙と committed)
- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §2.2 / §3 / §6 (値空間降下・vivify・index 正規化)
- spec `docs/REFERENCE.md` の `cell_fns` 表 (`empty` の target 型規定)
- `docs/issue/2026-08-02-cell-fn-empty-target-type-check-missing.md` (§1.1 で起票した既存 gap)
