# MDR-002: 評価器コア設計 (CPS 化 / Pending 統一 / モジュール分割)

Status: Accepted

MDR-001 が「ゼロから再設計する」と定めた評価器コア (slice `poc/eval.mbt` / `poc/complete.mbt` 相当) の設計を確定する。MDR-001 の未決 2 件のうち「破れ 2 の Pending 表現」を本 DR で決着させ、あわせて破れ 1 の解消設計とモジュール分割方針を定める。

対象の破れ (MDR-001 §2 が設計入力とした 2 件):

- **破れ 1**: 取り分選好 (greedy/lazy repeat の枝刈り) の完成オラクル `has_full` が**大域入力長**を基準にしている。スコープの消費境界 (親が後で何を消費するか) を知らないと正しい境界は決まらない。slice `poc/phase16_wbtest.mbt` が凍結する具体例: `seq a b c` (`seq` は body に greedy repeat `xs`、root に末尾 positional `tail`) の正解 `{seq:{xs:[a,b]}, tail:c}` が、`xs` が大域末端 `[a,b,c]` にコミットして `tail` 未消費で fail する。
- **破れ 2**: `Branch` が `Accept`/`Held` の 2 値のみで、「トリガ消費・値 pending」の中間状態を表せない。このため補完 (`complete.mbt`) は parse (`eval.mbt`) の scope_step 構造を鏡写しにした専用走査として別実装されている (756 行)。

## 決定

### 1. 破れ 1 = CPS 化で解消

`has_full` を「`branches` の中に `pos == 大域長` のものがあるか」という静的な数値比較ではなく、「この分岐を選んだ後、**残り全部** (このスコープの残り + 親スコープの残り + … + 最終的な `pos == toks.length()` 判定) を最後まで実行してみて、Accept に到達するか」という**動的な問い**に変える。継続 (continuation) を defunctionalize した `Cont` ADT を実際に呼んで Accept 到達を見る動的判定にする。

#### 1.1 なぜ「スコープ・ローカルな境界」では解けないか (原理的不可)

「repeat のいる**そのスコープ自身**の消費境界を求めて `has_full` の基準にする」案は一般には解けない。境界は「親がこのスコープの後に何を消費するか」で決まるため、スコープ内部だけを見ても求まらない。phase16 の例で言えば、`seq` スコープの内部情報だけからは「`xs` は 2 個で止めるべき」という事実は導出できない — root に `tail` という受け皿があることを知って初めて `xs` の正しい取り分が決まる。この依存は任意深さのネストで再帰する (孫スコープの repeat は親・祖父のさらに先の消費まで知る必要がある)。つまり「ローカルな一つの数値」で境界を持たせる設計は原理的に不可能で、**呼び出し元の続き (継続) そのもの**を境界判定に使うしかない。

#### 1.2 CPS 化の型スケッチ

現在 `scope_step` / `scope_consume` が

```
fn scope_step(sc, toks, pos, pidx, acc, severed, defs) -> Array[Branch]
```

という「自分の分だけ計算して `Array[Branch]` を返し、呼び出し元がその結果を覗いて次を判断する」形になっているのを、

```
fn scope_step(sc, toks, pos, pidx, acc, severed, defs, k: Cont) -> Array[Branch]
```

のように**成功継続 `k`** を引数に足し、スコープが自分の分を終えたら (`pidx >= sc.positional.length()`) `Array[Branch]` を直接返す代わりに `k(pos, acc)` を**呼ぶ**形に変える。`k` は「このスコープが終わった後に起きること全部」— 親の `scope_step` の残りから、最上位の `pos == toks.length()` チェックまで — を表す。

`k` は素の MoonBit クロージャではなく、**defunctionalize した ADT** として持つ (1.4 のメモ化のため):

```moonbit
enum Cont {
  KTop                                      // 最上位: pos == toks.length() で Accept、それ以外は []
  KResumeScope(Scope, Int, Bool, Cont)      // 子スコープが終わったら親 scope_step を (sc, pidx, severed) から再開、その後は outer Cont
}

fn run_cont(k : Cont, pos : Int, acc : Array[Binding], defs : Map[String, Node]) -> Array[Branch] {
  match k {
    KTop => if pos == target { [Accept(pos, acc)] } else { [] }
    KResumeScope(sc, pidx, severed, outer) => scope_step(sc, toks, pos, pidx, acc, severed, defs, outer)
  }
}
```

(`toks`/`target` を `Cont` に持たせるか `run_cont` の引数に足すかは実装時の細部。要点は「`Cont` が『親スコープの残りの手続き』を値として持ち運べる」こと。)

`has_full` はこれで**引数が要らなくなる**: 「`k` を呼んだ結果に `Accept` が 1 つでもあるか」だけを見ればよい (元の `target` 比較は `KTop` の中に 1 箇所だけ埋め込まれ、以後どの深さの継続からも透過的に「本当に大域まで解決したか」を反映する)。

```moonbit
fn has_full_k(brs : Array[Branch]) -> Bool {
  for b in brs {
    match b { Accept(_, _) => return true; Held(_, _) => (); Pending(_, _) => () }
  }
  false
}
```

repeat (`Ref` / `BoundedTail`) の分岐点は、`stop` と `more` それぞれの**継続の呼び出し結果**を見て選ぶ:

```moonbit
// Ref(name) の repeat 分岐 (概略、lazy 分岐は対称なので省略)
let stop_result = run_cont(KResumeScope(sc, pidx + 1, severed, k_outer), p2, acc2, defs) // このスコープの続き = 1つ深い継続で表現
let more_result = /* 1 つ余分に消費してから同じ pidx で再帰、内部でさらに stop/more を選ぶ */
if has_full_k(more_result) { more_result }
else if has_full_k(stop_result) { stop_result }
else { cat_branches(stop_result, more_result) }
```

`stop_result` はもう「このスコープの終端位置」ではなく、**親まですべて辿った末の Accept/Held**なので、`has_full` の判定がそのまま正しい「大域まで解決するか」の判定になる。

#### 1.3 完成判定のメモ化 (defunctionalize の根拠)

`has_full` の素朴な eager 評価 (`stop`/`more` を両方フルに計算してから比較) は、直列に並んだ複数の repeat / 深いネストで再計算が積み重なり得る (深さ N の判断点それぞれが「残り全部を最後まで走らせて Accept の有無を見る」ため、共有なしでは重複探索が発生する)。

対策として `Cont` を素のクロージャでなく **1.2 の `Cont` enum (defunctionalize)** として持つ。`Scope` / `Int` / `Bool` はすべて `derive(Eq)` 可能な値なので、`Cont` 自体も構造的に比較可能にできる。これにより:

- `completes(k : Cont, pos : Int) -> Bool` (「この継続をこの位置から呼んだら Accept に到達するか」だけを覚えるキャッシュ) を `Map[(Cont, Int), Bool]` 相当のテーブルでメモ化できる。同じ `(継続の形, argv 位置)` の組が複数の判断点から問い合わせられても 1 回しか実際には評価しない。
- **メモ化キーは `(継続の形, argv 位置)` のみ。bindings (`acc`) はキーから外す。** 完成判定 (どの位置からどの継続で Accept に届くか) はどんな値を束縛したかに依存しない — path-search の CYK/Earley 系アルゴリズムで一般的な「状態 × 位置」メモ化と同型。値そのものが必要な「実際の Branch 配列」の構築 (`run_cont` のフル版) はメモ化せず素直に再計算してよい (こちらは高々 1 回、選ばれた分岐でしか呼ばれない)。

実装時に詰める課題として残るのは、`Map` のキーに `Cont` を使うための `Hash`/比較実装、あるいは `Cont` 値ごとに一意 ID を割り振るインターン化。**アーキテクチャとしては defunctionalize が「正しさ」と「メモ化可能性」を同時に満たす**。素のクロージャ (`(Int, Array[Binding]) -> Array[Branch]` を関数値として持ち回る案) でも 1.2 の正しさは同様に成立するが、メモ化の足場がないため大きな文法での性能リスクをそのまま抱えるため採らない。

#### 1.4 机上トレース (解消機序の記録)

`toks = ["seq", "a", "b", "c"]` (`target = 4`)。root `R` の positional = `[StrArg("tail")]`、greedy = `[CmdSat("seq", C)]`。子 `C` の positional = `[Ref("xs")]` (unbounded repeat, head = `StrArg("xs")`)。

1. `R` の `scope_step` (pos=0) が greedy `CmdSat("seq", C)` を発火 → `C` を継続 `k1 = KResumeScope(R, pidx=0, severed=false, KTop)` 付きで評価開始 (pos=1)。
2. `C` の `Ref("xs")` 分岐が繰り返し呼ばれ、"a"→"b"→"c" と消費しながら各レップ境界で `stop` vs `more` を選ぶ。**注目点は "ab" まで消費した時点 (pos=3) の判断**:
   - `more` (3 個目の rep を試す): pos=3 で "c" を消費 → pos=4。ここでさらに `more`(4個目)を試すと `pos>=toks.length()` で consume_head が値なし → `has_full_k(more)` = false。`stop` (pos=4 で C を終える) は `k1` を呼ぶ → `R` の `scope_step` を pos=4, pidx=0 から再開 → `tail` の StrArg が `pos>=toks.length()` で **`Held(pe_missing("tail",4))`** を返す (Accept ではない) → `has_full_k` = false。→ この深さでは `stop`/`more` どちらも false なので両方保持 (`cat_branches`)、上位に伝播。
   - **1 段上の判断 ("ab" 消費 pos=3 での stop/more 選択)**: `more` = 上で計算した「3 個目を試す」結果 (Accept なし) → `has_full_k(more)` = **false**。`stop` (pos=3 で C を終える、xs=[a,b]) は `k1` を呼ぶ → `R` の `scope_step` を **pos=3**, pidx=0 から再開 → `tail` の StrArg は `pos=3 < 4` なので "c" を消費 → pos=4 → `R` の positional 終端 → `KTop` を呼ぶ → **`pos==target(4)` で Accept**。→ `has_full_k(stop)` = **true**。
   - 判定規則 (greedy 既定 = more 優先) は「`has_full(more)` なら more、そうでなく `has_full(stop)` なら stop」なので、**この段で `stop` (xs=[a,b]) が正しく選ばれる**。

大域の生の位置一致 (`p == 4`) ではなく「継続を実際に走らせて Accept が出るか」を問うことで、`xs` を 3 個消費する分岐 (即座に pos=4 に届くが `tail` を飢えさせる) は不採用になり、`xs` を 2 個で止めて `tail` に "c" を渡す分岐が採用される。これが phase16 の凍結 fail を解消する機序である。

#### 1.5 受け入れ条件

上記 1.4 は原理的に解けることの机上証明であり、実装後の実証は別途要る。**実装後に slice `poc/phase16_wbtest.mbt` 相当の fixture (`seq a b c` → `{seq:{xs:[a,b]}, tail:c}`) を参照実装側で green にできることを本設計の受け入れ条件とする** (MDR-001 §2 が定めた受け入れテスト)。

### 2. 破れ 2 = 案 B (Branch に Pending 追加、1 走査に統一)

`Branch` を 3 値化し、parse と補完を 1 走査に統一する。complete 専用走査 (`complete.mbt`) は持たない。

```moonbit
enum Branch {
  Accept(Int, Array[Binding])
  Held(ParseError, Array[Binding])
  Pending(Array[Cand], Array[Binding])   // トリガは消費したが値スロットの分の入力がまだ無い
} derive(Show)
```

#### 2.1 Branch の 3 値化と、どこで Pending が生まれるか

現状 `eval` の `StrArg`/`NumArg`/`SepArg` などが `pos >= toks.length()` で無条件に `[]` を返している箇所が発生源。greedy entry の Seq 評価 (`eval_seq`) の途中でトークンが尽きたとき、現状は「そのアイテムの `eval` が空配列を返す → for ループが 1 回も回らず暗黙に `[]` に潰れる」という**沈黙**が起きている。これを `Pending(cands, acc)` という**明示的な値**に変える。`cands` の中身は slice `complete.mbt` の `comp_seq_value` が構築している「pending value 候補」(`cvalue(ty, name)`) と同種のものを流用できる。

Branch は次の 3 値の意味論を持つ:

- **Accept**: この経路は入力を完全消費して成立した。
- **Held**: この経路は dead end (トリガ不一致・値不正・positional 過多など、真の失敗)。
- **Pending**: トリガまでは消費できたが、値スロットに与える入力が尽きた中間状態 (parse では Held 相当のエラー、complete では補完候補の源)。

#### 2.2 全 `match Branch` サイトへの波及と網羅性検査による安全性

`scope_step` の greedy ループ、`scope_consume` の各アーム、`eval_seq`、`eval_many`、`idx_repeat_eval`、`bounded_tail_step`、`consume_head`、`scope_consume_rep`、`nest_branches`、`cat_branches`、`has_full`、`drop_optional_missing`、`parse()` のトップレベル収集ループ — 15 箇所以上に `Pending(..) => ...` の腕を足す必要がある。

**この波及は移行コストであると同時に移行の安全性でもある**。slice の既存コードは `Branch` に対する `match` を全て `Accept(..) => .. ; Held(..) => ..` の**明示 2 腕**で持ちワイルドカード (`_ =>`) を使っていないため、`Pending` を追加した瞬間 MoonBit の網羅性検査が**全サイトでコンパイルを止める**。移行漏れを機械的に (見落とし不可能な形で) 全数検出できる。

#### 2.3 parse 側の扱い (エラー可視化の改善)

`Pending` は「トリガは合っているが値が無い」という意味では実質的に `Held` (エラー) と同じ扱いでよい。`parse()` のトップレベル収集で `Pending(cands, bs)` を Held 相当として扱い、`pe_missing` 風のメッセージ (「--port の値がありません」等) を合成して errors に積む。parse の観測可能な振る舞いは変わらない — **今まで沈黙して消えていたものが正しくエラーとして可視化される点だけが違う** (これは改善)。

#### 2.4 complete 側の扱い (統一走査の意味論)

`complete()` は `toks = before` として同じ評価器を走らせ、**`pos == before.length()` に到達した時点で得られる `Pending` の `cands` と、その時点で開始可能な greedy trigger 一覧・positional 期待とを合わせて和集合にする**。これは DR-060 (kawaz/kuu) の意味論そのもの (「消費できた全生存 partial 経路の、次の消費点で読めるものの和集合」) を、`Pending` という 1 つの値の収集としてそのまま実装できることを意味する。`comp_scope`/`comp_seq_entry`/`comp_consume_*` という専用関数群は不要になり、`eval`/`scope_step` を `before` に対して走らせて `Pending` を集めるだけになる (= complete 専用走査は存在しない)。

parse と complete は「同じ Branch ストリームに対して異なる収集ポリシーをかける」関係になる (slice で既に `parse` の `FailDef` = `AcceptsOnly`/`WithHeld`/`DeepestOnly` が「同じ Branch 列に異なるポリシーをかける」実例を持つのと同型)。complete は「`Pending` と `Accept` のみ採用、`Held` のみの経路 (真の dead end) は除外」という第 4 のポリシーを足すだけでよい。

#### 2.5 DR-060 (kawaz/kuu) の 3 分離理由への回答

DR-060 は complete と parse の分離を「正しい形」として追認しているが、その 3 つの分離理由は Pending 統一で解消する:

1. 「parse は pending を枝ゼロに畳む」→ `Pending` variant がそのまま解消する。
2. 「WithHeld は dead end 込み、補完は dead end 除外で極性が逆」→ 元々「同じ生の Branch ストリームに対して異なる収集ポリシーをかける」問題であり、Branch という素材と収集ポリシーが分離されていれば両立できる (2.4 参照)。
3. 「先食い判定が違う (`greedy_reads` は完全消費要求、`comp_greedy_reads` はトリガ一致のみ)」→ `Pending` を `greedy_reads` が `Accept` と同様に「読めた」扱いにすればこの差は解消し、parse 側の潜在バグ修正にもなりうる (2.6)。

#### 2.6 先食い判定の潜在穴 (未検証の机上指摘)

これはコードを読んだ限りの推論であり、実行して確認したものではない。以下は「机上で辿れる可能性」の指摘であって確定した bug 報告ではない。

現行 `greedy_reads` (slice `eval.mbt:686` 相当) は `eval(g, ...)` の結果に `Accept(p2,_) if p2 > pos` があるかだけを見る。`--port` が入力の最後のトークンで値が無い場合、`eval` は `NumArg` 側が `[]` を返し `eval_seq` がそれを暗黙の `[]` に潰すため、`--port` という greedy entry 自体が**丸ごと消えて**返る。結果 `greedy_reads` は「読めなかった」と判定し**先食いが働かず**、もしその位置に寛容な string positional があれば `"--port"` という文字列そのものが positional に raw で食われてしまう可能性がある (「値がない --port はエラーになるべき」という直感に反する)。`Pending` を greedy_reads (相当) の判定に含めれば、トリガが合った時点で「読めた」と判定され、この取りこぼしが構造的に塞がる。

**このシナリオを突く fixture が現状あるかは未確認。参照実装側でこの挙動を明示的にテストする (fixture 化する)。** — TODO として本設計に残す。

#### 2.7 案 B を採る根拠 (案 A を採らない理由は §5 に収録)

MDR-001 は「ゼロから再設計」を明言しており slice からの移植ではなく新規実装である。この前提のもとで:

- 破れ 1 の CPS 化は必須であり、`scope_step`/`scope_consume` 等の**全シグネチャと全 Branch match サイトに手を入れる**大改修になる。
- 案 B (`Pending` 追加) が要求する改修は「同じ Branch match サイト群にもう 1 腕足す」ことであり、**CPS 化のために touch する箇所と完全に重なる**。「今 touch しているファイルにもう少し書き足す」コストであり、「後日別の改修として同じファイル群をもう一度全部触る」より低い。
- MoonBit の網羅性検査が移行漏れを全数検出する (2.2)。
- 2.6 の先食い判定の潜在穴を構造的に塞ぐ副次効果を持つ。

「ゼロから再設計」かつ「破れ 1 の CPS 化がどのみち Branch 全サイトを触る」という 2 条件が揃っている今が、案 B の追加コストが最小になるタイミングである。

### 3. モジュール分割

MDR-001 §4 は `src/core` 単一パッケージから開始し公開 API が固まってから分割する方針だが、単一パッケージ内でも ROADMAP (kawaz/kuu) の 4 フェーズ (lowering → 評価器コア → 値確定層 → 出口層) を**ファイル境界に写像**する。案 B 採択により `complete.mbt` は存在しない。

| ファイル (単一パッケージ内) | 責務 | slice 対応 | 依存方向 |
|---|---|---|---|
| `node.mbt` | AtomicAST (`Node`/`Scope`/`Entity`/`Constraint`/`Ty`/`ExportKey`) 型定義。振る舞いを持たない ADT のみ | `node.mbt` (238行) をほぼ踏襲、命名規約 (MDR-003) だけ適用 | 依存なし (葉) |
| `value.mbt` | `Value`/`Source`/`ConfigVal`、`parse_number` 等の値パーサ | `value.mbt` (236行)。DR-074/075 (kawaz/kuu) の字句追従が必要 | node に依存 |
| `matcher.mbt` | short/long matcher ランタイム (`EqSplit`/`ShortCombine` の解釈) | `matcher.mbt` (234行) をほぼ踏襲 | node, value に依存 |
| `cont.mbt` (新設) | §1 の `Cont` ADT と `run_cont` / メモ化テーブル。評価器コアが依存する「継続」の基盤部品として独立させる (eval.mbt に埋め込むと巨大化するため) | 対応なし (新設) | node に依存 (Scope を継続に含むため) |
| `eval.mbt` | path-search 評価器本体: `eval`/`scope_step`/`scope_consume`、背骨・先食い・早閉じ抑制・取り分選好 (§1 の CPS 化を適用)、`parse()` トップレベル。制約の**成立判定** (経路のフィルタリング) はここに残す | `eval.mbt` (1778行) から CPS 化 + Pending 統一で書き直し | node, value, matcher, cont に依存 |
| `resolve.mbt` (新設) | 値確定層: 値源ラダー (env/inherit/default セル充填)、config 2相解決、遅延述語 (制約) の最終評価、結果ビルダー (`build_result`/export-key 適用/衝突検出) | `result.mbt` (668行) + `installer.mbt` 内の `resolve_scope`/`resolve_scope_config` (値源ラダー部分) を統合 | node, value に依存。eval からは経路確定後の後処理として呼ばれる |
| `outcome.mbt` (新設) | 出口層: `Outcome`/`FailureData`/`AmbiguousData` の型定義、失敗時アクション選択 (`FailDef`/`argmin_action`)、help_entry/tried_triggers 材料の構築、complete (`Pending` 収集) | `eval.mbt` 末尾の top level (DR-038 path counting) 節 + slice `complete.mbt` の意味論を Pending 収集として統合 | eval, resolve に依存 |
| `installer.mbt` | lowering 本体 (UsefulAST → AtomicAST)。12 installer、`parse_definition`、def-error 列挙 | `installer.mbt` (2153行) を参照移植 | node, value, matcher, resolve (値源ラダーの宣言構造) に依存。**評価器 (eval) には依存しない** |

**依存方向の要点**: `installer.mbt` (lowering) は `eval.mbt` (評価器) に依存しない — installer は「UsefulAST から AtomicAST を組み立てる」だけで、組み立てた AST を実際に評価するのは呼び出し側 (conformance runner や CLI エントリ) の仕事。slice が既に体現している分離 (「エンジン (Node ADT の解釈) と lowering (ElemDef→Node) が別ファイル」) をそのまま踏襲する。新設 3 ファイル (`cont.mbt`/`resolve.mbt`/`outcome.mbt`) は ROADMAP の 4 フェーズをファイル境界に写像する意図で、slice の「eval.mbt 1 本に path-search + 制約評価 + top-level outcome 構築が同居」より責務が細かく割れる。

complete の意味論は `outcome.mbt` 内の `Pending` 収集関数 1 本になり (§2.4)、独立ファイルとしては存在しない。

## DR-060 (kawaz/kuu) との関係

DR-060 は complete と parse の分離を「正しい形」として追認しているが、これは **slice の制約下 (Branch が Accept/Held の 2 値のみ = Pending 表現を持たない) での判断**である。本設計は Pending 表現の有無という前提そのものを変える (Branch 3 値化) ため、DR-060 と矛盾しない。DR-060 が挙げる 3 つの分離理由は §2.5 のとおり Pending 統一で解消する。

**spec 側 DR-060 の改訂は不要**: DR-060 の「正しい形」は当時の入力 (2 値 Branch という制約) に対する判断として妥当であり、そのまま残す (MDR-001 §3 = 仕様 DR は複製せず参照する方針とも整合)。本 DR は「参照実装はゼロ設計で前提が変わったため分離を採らない」ことを記録し、読み手が DR-060 と本 DR を突き合わせて混乱しないよう相互参照する。

## 却下案

### 却下 A: スコープ・ローカルな境界で has_full を解く (破れ 1)

「repeat のいるそのスコープ自身の消費境界を求めて `has_full` の基準にする」案。**原理的に解けない** (§1.1)。境界は親がスコープの後に何を消費するかで決まり、任意深さのネストで再帰するため「ローカルな一つの数値」では表せない。

### 却下 B: 全分岐を列挙してから後段で選好フィルタ (破れ 1)

早期枝刈りをやめ、`stop`/`more` を毎回両方とも最後まで展開し、DR-038 (kawaz/kuu) のトップレベル path 集合が確定した後に同一 repeat の split 違いだけの経路をグルーピングして選好で 1 本に絞る案。

却下理由:
1. **経路同一性の再構築問題**: DR-038 の経路同一性は「観測可能な効果列」で判定するため `xs=[a,b]` と `xs=[a,b,c]` は文字通り別効果列 = 別経路であり、後段でこれらを「同一 repeat の split 違い」とグルーピングするには生の効果列からは読み取れない「どの repeat 由来か」のメタ情報を別途持ち回る必要がある。これは CPS 案が「repeat の分岐点でそのことを構造的に知っている」立場を後から再構築するようなもので素直さで劣る。
2. **性能面でさらに悪い**: 早期枝刈りを全廃すると複数の repeat が直列するケースで組合せ爆発がそのままトップレベルまで持ち越される (§1.3 のメモ化の恩恵も受けにくい — 「後で選ぶ」ため全分岐を作ってしまう)。

### 却下 C: 案 A = 分離恒久化 + walk_scope 共有 skeleton (破れ 2)

`Branch` は Accept/Held の 2 値のまま、`complete` は独立した専用走査を維持するが、「スコープを歩く順序」を葉の振る舞いだけ差し替え可能な高階関数 (`walk_scope[R]` + `WalkInterp[R]`) に抽出して drift を構造的に防ぐ案。`parse` 用に `WalkInterp[Array[Branch]]`、`complete` 用に `WalkInterp[Array[Cand]]` を実装し、「歩く規則」自体は 1 箇所に集約する。

却下理由:
1. **恒久的な鏡写しコード (756 行相当) の保守負債が残る**。walk_scope で「順序」は共有できても complete の葉ロジックは別 instantiation として作り込む工数が要り、2 つの skeleton を保守し続ける。
2. **CPS 化との相乗りが効かない**。案 A は CPS 化と独立に成立するため「いつやってもコストは変わらない」= 今 Branch 全サイトを touch する機会と重ならず、追加コスト最小化の利点を得られない。
3. **MoonBit に高階種 (HKT) がない**ため `WalkInterp[R]` をジェネリック構造体として素直に書けるかが実装時リスクとして残る (`WalkEvent` の配列を仲介させる代替に落ちる可能性)。
4. §2.6 の先食い判定の潜在穴を塞ぐ副次効果が得られない。

案 B が「1 走査に統一する設計的な整合」「CPS 化とのコスト相乗り」「先食い判定の潜在穴の構造的封鎖」で上回るため案 A を却下する。

## 実装で確定した細部 (初期実装 + 設計レビューの反映)

§1.5 の受け入れ条件と §2.6 の fixture 化はいずれも `src/core/eval_wbtest.mbt` で実証済み (phase16 相当 / 先食い穴 / DR-043 逐次 2 repeat / REVIEW-H1)。実装が本文のスケッチへ加えた確定事項:

### CPS の射程: スパイン + 継続フレーム化した選好判断点

継続 `k` が通るのは **scope walk (scope_step / scope_consume) と、そこから構造的にディスパッチされる子スコープ入口** (CmdSat greedy = `KNest`、positional の ScopeNode = `KResumeScope`、**scope 形 head を持つ repeat = `KRefChoice` / `KTailChoice`**)。最後の 1 つは設計レビューの指摘 (repeat head が ScopeNode の場合、素の `eval` = `KDone` 経由では head 内部の repeat が外側の残余消費を見られず破れ 1 が 1 段深い所で再発する) を実機で fail 再現して塞いだもの。

**残る制限**: `Or` / `Seq` / `Rooted` の内部など、plain `eval` 経由でしか到達できない位置に埋め込まれた ScopeNode は `KDone` (scope 端で無条件 Accept) で評価され、その内部の取り分選好は局所化される。この経路に repeat を埋め込む lowering を installer が生成しないこと (repeat はスパイン形 = positional の `Ref`/`BoundedTail`/`ScopeNode` に正規化して埋める) を installer 移植時の規約とする。

### KTop = 「完全解決経路」の単一定義点 (residual + 制約)

`KTop(Array[ScopedCons])` が完全性判定を一手に担う: (a) `pos != toks.length()` は residual の Held (`unexpected_token`)、(b) 全消費でも**全スコープの制約違反があれば violation ごとの Held** (DR-047 §2「制約を満たさない経路は完全解決経路でない」)。Accept は「全消費かつ制約充足」のときだけ生まれるため、取り分選好オラクル (has_full_k) と parse() の計数層が同じ完全性定義を自動共有する — 深掘りレビューで確定した「選好層が制約違反の全消費を完全と誤認して正当な取り分を刈る」欠陥の根治。

- 制約テーブルは `collect_scopes` が静的収集 (root + CmdSat 子 (Or 内含む) + inline ScopeNode + scope 形 repeat head)。制約照合は (path, name) の scope-exact (DR-055 §1 lexical) — key 名だけの照合は親子同名 key で双方向 leak した
- **制限**: repeat 透過スコープの制約は全 rep マージ後の最終状態で評価 (per-rep 述語は spec 未規定)。IdxRepeat の "#k" 付き path は対象外
- 異なる argv_pos の unexpected_token が複数 errors に乗りうる (DR-053 §2 全保持)。conformance fixture が「1 個の合成エラー」前提なら実食時に突き合わせ

### 先食いはトリガ一致意味論 (greedy_engages)

DR-041 §4「素通しはトリガ不一致 (読みゼロ) の時のみ」に合わせ、greedy_reads は entry の消費完走でなく**構造的トリガ一致** (Exact/CmdSat/DdSat の綴り、matcher は run_matcher 非空) で判定する。トリガが一致した token は「ここで読まれる」— 値不正・値飢餓・子スコープ不成立はその entry の Held/Pending が結末になり、positional への silent raw 落ちは起きない (§2.6 の Pending 形と合わせて Held 形も封鎖)。トリガレスな縮退形 (裸の値プリミティブ greedy) は消費ベース fallback で過剰 suppress を避ける。

### errors は DR-066 の reason を全構築サイトで emit

ParseError は 5 要素 (reason 付き)。slice には無かったが台帳ゼロ開始の精神で最初から emit する。

## TODO (残)

- **greedy エントリの「1 回」制約 (DR-041 §4) は未実装、要仕様裁定**: 同一 entry が無制限に再発火する
  (`-v -v` が binding 2 個の単一経路 Success、実機再現済み)。しかし DR-043 §「multiple (値の畳み)」の
  「option の複数回発火や separator 分割片が生む値列を畳む DR-034 のパイプライン…**出現回数・出現位置の
  制約は持たない**」、および DR-015「あと勝ち mutation」、conformance fixture
  `multiple-parse/last-wins-scalar.json`(`repeat`/`multiple` 無し scalar option の 2 回発火 + last-wins
  を正式仕様として固定) が、DR-041 §4 の文言と字面上矛盾する。無許可でどちらかを実装すると既存確定仕様
  (fixture 込み) を壊すため実装を保留、kawaz 裁定待ち。docs/issue/2026-07-08-greedy-once-and-idxrepeat-premises.md
  で追跡。
- **IdxRepeat は bounded-head 前提 (下流 backtrack なし)、installer 側で明文化済み**: permissive head
  (bare string primitive 等) + 後続 mandatory positional では DR-043 の字義 (regex 的後退) と乖離する
  (`IdxRepeat(head=StrArg, min=1)` + 後続 positional で greedy-max が全消費し後続を starve させる、実機
  再現済み・`eval_wbtest.mbt` の "KNOWN GAP" テストで固定)。現状 conformance fixture に BGroup+repeat
  (named-group) のケースが無く実害未確認のため、eval 側への backtrack 追加は見送り、installer.mbt の
  BGroup lowering コメントに bounded-head 前提の運用規約を明文化した (node.mbt design rationale 相当)。
  同 issue で追跡、要すれば backtrack 実装判断を後日行う。
- **tried_triggers の失敗位置対応 (解決済み)**: DR-053 §4「失敗位置で試行された綴り」を §2「primary の
  定義: argv 位置が最深の Error」と同一 DR 内で連続する節として読み、primary error (最深 argv_pos) の
  `path` (DR-066 §4) から対応する子スコープを辿って tried_triggers を返すよう修正 (`outcome.mbt`
  `tried_triggers_of` / `scope_at_path`)。`eval_wbtest.mbt` に固定テスト追加、既存の Or-wrapped greedy
  テストも無傷。

- **complete 実装 (出口層) は `EvalMode` のモード分岐で実装済み**: §2.4 の「収集ポリシーを足すだけ」は、(a) 取り分選好の刈り込みが負け枝の Pending を捨てる、(b) `drop_optional_missing` が repeat 続き候補を落とす、(c) `consume_head` の枯渇が Pending でなく Held である — の 3 点と衝突していた (設計レビューで確定)。採った形は「walk へ complete モードを通す」(別走査は採らない): `Ctx.mode : EvalMode` (ModeParse/ModeComplete) を全 walk 関数に threading し、complete モードでは (a) 3 箇所の選好判定を素通し (stop/more 両保持)、(c) spine/consume_head/matcher 内 cluster tail の枯渇 Held を `Pending` 値候補に、加えて境界トリガサイト (Exact/CmdSat/DdSat/NativeMatch の argv 末端) が沈黙 Reject でなく `Pending` exact 候補を返す。(b) は (c) により complete モードで missing_operand Held 自体が生成されなくなるため分岐不要 (dropper は素通り)。`complete(root, before, defs?, after?)` (outcome.mbt) が ModeComplete で walk を回し Pending の cands を dedup 収集、after 整合フィルタ (DR-060 §2) は WordEnd exact 候補のみ検査 (値候補・Cont 綴りはユーザ入力を発明できないため無検査で通す)。輪郭は `complete_wbtest.mbt` が固定。
- **メモ化 (§1.3) は未実装**: 現受け入れテスト規模では不要。逐次 repeat fixture のトークン長を段階的に伸ばした実測で要否閾値を決める (conformance 実食フェーズ)。Cont は defunctionalize 済みなので足場はある。

## 関連

- [MDR-001](MDR-001-bootstrap-policy.md): 立ち上げ方針 (本 DR が未決 1「破れ 2 の Pending 表現」を決着)
- [MDR-003](MDR-003-reserved-word-naming.md): 予約語命名規約 (node/installer 各型に適用)
- kawaz/kuu の DR-060: complete/parse 分離の追認 (slice 制約下の判断、本 DR で前提が変わる旨を上記「DR-060 との関係」に記載)
- kawaz/kuu の DR-038: 経路同一性 (却下 B の根拠)、DR-053: 素材とポリシーの分離 (§2.4 の同型原理)
- kawaz/kuu の ROADMAP: 4 フェーズ (§3 のファイル境界写像の根拠)
- slice `poc/phase16_wbtest.mbt`: 破れ 1 の凍結 fail (受け入れテスト)
