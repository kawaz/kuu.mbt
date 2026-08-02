# 84.9% coverage 時点の未到達分析

> 対象: GitHub Actions artifact `30728489791` の coverage 集計。
> 集計時点: `v0.0.13` 相当、全体 coverage **84.9%**。
> 本文中の行番号はすべてこの時点の座標である。W2-8 / W2-9 / DR-132 の実装後は行が移動しているため、補強時は識別子・分岐・既存 test を grep で再特定する。

## 判明した事実

未到達行数は `eval.mbt`、`lowering.mbt`、`resolve.mbt` の順に多い。ただし、行数だけでは優先度を決められない。公開 API の契約、共有 fold の状態遷移、result と sources の独立射影のように、少数の未到達分岐でも複数の観測面へ波及する箇所を先に wbtest で固定する必要がある。

高リスクの wbtest gap は次の 3 系統に集中していた。

1. 共有 cell fold の `unset`、未知 cell fn、invoke 失敗、`UseDefault`、`Empty` の状態遷移
2. source projection の clear / abort 系と、result と sources が独立に乖離しうる経路
3. 同一 export cell に集まる default candidate の equal / unequal 分岐

fixture gap は別層の観測を担う。wbtest が局所分岐を固定しても、effects / result / sources の 3 面や config_file の committedness を利用者契約として固定する fixture が不足している。

## 実用的な示唆 / ベストプラクティス

- coverage の未到達行数をそのまま test 優先順位にしない。共有意味論、公開玄関、独立射影、definition-error 境界を優先する。
- 行番号は調査時点の座標として扱い、追加実装では関数名・enum variant・既存 test 名から再探索する。
- 現行挙動をそのまま pin せず、対応する DR の読み意味論と照合する。到達不能化された分岐や規範と食い違う分岐は test で延命しない。
- wbtest と fixture は代替関係ではない。wbtest は局所の状態遷移と失敗 class、fixture は公開観測面の組を固定する。

## 検証の詳細

### 未到達行数の上位 10 ファイル

| 順位 | ファイル | 到達行 | 対象行 | 未到達行 |
|---:|---|---:|---:|---:|
| 1 | `eval.mbt` | 1,191 | 1,718 | 527 |
| 2 | `lowering.mbt` | 2,125 | 2,402 | 277 |
| 3 | `resolve.mbt` | 1,421 | 1,586 | 165 |
| 4 | `wire_decode.mbt` | 1,043 | 1,168 | 125 |
| 5 | `lexicon.mbt` | 425 | 516 | 91 |
| 6 | `node.mbt` | 110 | 186 | 76 |
| 7 | `installer_residents.mbt` | 306 | 371 | 65 |
| 8 | `accumulator_residents.mbt` | 340 | 399 | 59 |
| 9 | `node_residents.mbt` | 328 | 364 | 36 |
| 10 | `completion_query.mbt` | 166 | 201 | 35 |

### wbtest gap

| 優先度 | 当時の座標 | 未固定だった仕様輪郭 |
|---|---|---|
| 高 | `cell_fold.mbt:71,76,84,86,88` | 共有 fold の `unset`、未知 cell fn、invoke 失敗、`UseDefault`、`Empty`。値状態を変える遷移と、失敗時に座を変えない遷移を全列挙する必要がある。 |
| 高 | `resolve.mbt:1598-1702` | source projection の `Unset → Default`、accumulator の `Empty` / `Unset` / `Default` clear、accumulator filter 失敗 abort、scalar seat の空 binding abort。result と sources が別々に同じ意味論を実装するため、片面だけでは乖離を検出できない。 |
| 高 | `resolve.mbt:3956-3970,4096-` | 同じ export cell へ集まる default candidates の equal / unequal 分岐。候補値が等しい場合と異なる場合を別々に固定する必要がある。 |
| 中 | `lowering.mbt:3620-3744` | canonical long と alias `long_override` の invalid DSL 経路。definition-error の分類と帰属を固定する必要がある。 |
| 中 | `front_door.mbt:103,137,324,464,501,508` | 公開玄関の malformed 契約。内部 helper の失敗ではなく、公開 API が返すエラー形を固定する必要がある。 |
| 中 | `cell_fold.mbt:258,279,287,289` | `value_with_at` の再帰 fault 全 class。入れ子のどの段で失敗したかを握りつぶさないことを固定する必要がある。 |

### fixture gap

この分析窓では不足をリスト化し、fixture 自体は後続の spec lockstep 窓で追加する。

| gap | fixture で固定する観測面 |
|---|---|
| scalar fold の invoke → default / empty | effects / result / sources の 3 面を同時に pin する。 |
| `config_file` path の committedness | 値の有無と committed / uncommitted の 4 象限を pin する。 |
| ambiguous 投影 | result と sources の組を同時に pin し、片面だけ成立する乖離を許さない。 |
| alias `long_override` の invalid DSL | definition-error として公開契約を pin する。 |

### 到達不能の代表例

coverage の未到達には、test 不足ではなく構造的に到達しない防御分岐も含まれる。代表座標は次のとおり。

- `front_door.mbt:378`
- `cell_fold.mbt:162-166`
- `resolve.mbt:1675,1694-1696,1731-1733`

到達不能分岐は coverage 数値のために人工的に呼ばない。現在の規範で必要な防御か、上流の検査によって恒久的に不要になった dead code かを先に判定する。

### 現行実装で再特定した際の注意

`v0.0.18` 相当の現行実装と DR を照合すると、当時の高リスク座標には意味論が変わった箇所がある。

- 共有 fold は `src/internal/fold/cell_fold.mbt` の `fold_seat_effect` にあり、直接操作と `Invoke` 後の `SeatTransition` を一箇所で分類する。lowering を通る公開経路では先に正規化される variant があるため、fold 単体 test では手組み binding と test cell fn で遷移表そのものを固定する。
- source projection の旧 `@abi.Unset → Source::Default` 分岐は、DR-131 §2b / §6 の「unset は null Value fn、effect op 語彙から削除」と一致しない旧 op の防御 armになっている。現行の `front_door_wbtest.mbt` には sources を default と説明するコメントと、sources を cli とする assert の不一致もある。規範裁定なしに旧分岐を pin しない。
- accumulator の clear は result 構築と sources 射影に複製されている。公開 API 経由で result と sources を同時に assert し、片面の test だけでは検出できない乖離を固定する価値がある。
- accumulator filter failure と scalar seat 空 binding は source projection 内で `abort` する。`abort` を test から捕捉できないため、到達経路の再現と `Err` 化の設計を別の修正単位として扱う。
- 同一 export cell の default candidates equal / unequal 分岐は、DR-120 §7 / §10 の export-key collision definition-error 化後は合法な定義から到達しない。違法定義を wbtest で生かすのではなく、dead code としての整理対象かを判断する。

## 関連

- spec `docs/decisions/DR-045-effect-descriptors.md`
- spec `docs/decisions/DR-114-universal-fn-integration.md` §2 / §7
- spec `docs/decisions/DR-120-export-key-collision.md` §7 / §10
- spec `docs/decisions/DR-122-sources-shadow-tree.md` §1 / §2
- spec `docs/decisions/DR-127-link-fixed-path-dsl.md` §3 / §4.2
- spec `docs/decisions/DR-130-null-projection.md` §5
- spec `docs/decisions/DR-131-sentinel-reduction.md` §2b / §6 / §7
