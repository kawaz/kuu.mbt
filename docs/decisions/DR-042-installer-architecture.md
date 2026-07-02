# DR-042: installer アーキテクチャ — 特殊語彙は装置が持ち込み、5 つの不変則で合成する

> 由来: 本セッションの議論で確定。DR-041 (トークン読みの意味論) と対。findings `2026-06-29-ast-missing-pieces.md` の F-002 / F-003 / F-007 (方向) / F-029 (方向) / F-031 (方向) / F-035 / F-041 (受け皿) に関係する。

## 決定

### installer とは

`long` / `short` / `env` / dd のような**特殊語彙 (属性名・type 値) は、コア文法ではなく installer の所有語彙**とする。installer は registry に登録される装置で、1 単位で次の 3 役を担う:

1. **所有語彙の回収**: UsefulAST から自分の語彙を読み取る (削除はしない — 不変則①)
2. **展開の植え付け**: 糖衣展開 (衛星構造の追加・再スコープ化) を行う
3. **実行時能力の提供**: 必要なら再解釈 matcher (トークン読み、DR-041) や値源 lookup を評価器に登録する

parse_definition (UsefulAST → AtomicAST) は installer 適用の連鎖として構成される。コア文法は atomic (exact / or / seq / primitive + multiple) と name / ref / link 等の骨格のみに縮む。

### 先行例: このパターンは既に中心原理

`type` (types registry) / `filters` (filters registry) / `multiple` (multiple registry) は「フィールド名で registry が暗黙決定」(§13.2) されており、**属性語彙と registry 実装のペアは kuu の既定路線**である。`long` / `short` / `env` は registry の後ろ盾なしにハードコードされた取り残しであり、本 DR はこの非対称を解消する。シュガーが増えるたびにコア属性が増殖する問題も、installer の追加 (= 語彙の所有者の追加) に置き換わる。

### 5 つの不変則 (合成契約)

installer の合成を順序非依存・冪等に保つ。組み込み installer はこれを厳守し、外部 installer にも遵守を求める (破る実装が悪い、という責任分界):

1. **宣言層は読み取り専用、寄与は追加**: installer は所有語彙を読むだけで、削除も書き換えもしない (意味論的削除 — 評価ループは installer 所有語彙をそもそも見ないので、残っていても「ないのと同じ」)。寄与は lowered 層への**決定的な追加**であり、同一寄与の再追加は no-op (add-if-absent) — 冪等はここから出る。未知語彙の完全性検査は「registry の所有語彙集合に載らない特殊語彙の検出」で行い、エラー + 次の手 hint (§13.5 の型) を出す。宣言属性が inert に残ることで help 生成・diagnose・再シリアライズが元の宣言情報を保持できる。
2. **追加的寄与**: 既存要素への in-place 操作は値源席への宣言まで。構造の寄与は衛星 (新要素) の追加で行い、**他 installer の lowered 産物 (衛星・matcher・席) を書き換えない・読んで反応しない**。宣言層への追加 (global の宣言的コピー等) だけが後続の回収対象になる。
3. **所有語彙の交差禁止**: 同一語彙を 2 つの installer が所有したら registry 登録時にエラー。
4. **値源はラダー席への宣言**: 値源系 installer (env 等) は default_fn を直接ラップせず、**エンジンが所有する DR-031 の優先順位ラダー**の席 (env / config / inherit / default) に lookup を宣言する。lookup は (value, source) を返し、ParserContext の source タグ (DR-016 / DR-031) を保存する。ラダーの順序自体は installer から動かせない。
5. **背骨 (spine) の切替は構造で表現する**: greedy が発火できるのは**宣言スコープの背骨** (そのスコープの positional 進行の消費点列) に復帰した箇所のみ。command 部分木は新しい背骨を宣言し (祖先の greedy は届かない)、greedy の内部消費と dd の継続には背骨がない (何も発火しない)。スコープ越えの可用性は評価器の例外ではなく global installer の**構造コピー**で表現する (祖先背骨を重ねる評価器実装は、観測等価な encoding としてなら自由)。

順序依存が要ると感じたら不変則違反の徴候として設計を見直す (priority フィールドや配列順への依存は持ち込まない)。installer 間の見かけの依存 (例: global が置いた宣言的コピーを long が展開する) は、**寄与が増えなくなるまで全 installer を繰り返す不動点反復**で解消する。停止性は「寄与は要素 × スコープで有限、コピーのコピーは同一実体への ref なので add-if-absent が止める」から、合流性は不変則①②から出る。

### 展開の標準パターン: ref/link 衛星 + 実体だけノード

```json
{
  "type": "command",
  "options": [
    {"name": "port", "type": "number", "long": [], "short": "p", "env": "PORT"},
    {"name": "version", "type": "flag", "short": "v"}
  ],
  "positionals": [
    {"name": "--", "type": "dd", "optional": true},
    {"name": "dir", "type": "dir"}
  ]
}
```

- **long installer**: `long` を回収し、greedy 面に衛星 `{or: [{seq: [{exact: "--port"}, {ref: "port", link: "port"}]}, ...]}` を追加
- **short installer**: `short` を回収し、greedy 面に再解釈 matcher (cluster / 値付着の読み生成、DR-041 §3-4) を追加。回収したエントリ表 `{p: port, v: version}` が matcher の構成データ
- **env installer**: `env` を回収し、port の env 席に lookup を宣言 (不変則④)
- **dd installer**: `type: "dd"` を回収し、greedy 面に exact 衛星 (トリガ兼消費者、matcher は素の exact 一致) を追加。発火後は positional 継続を内部消費として引き継ぐ (sever は DR-041 §4 の内部一体則から導出、不変則⑤)

元要素は評価ループから見て、マッチ能力を衛星に移譲した**実体だけノード (DR-030)** として振る舞う (宣言属性は inert に残る、不変則①)。衛星は ref (構造継承) + link (値同期) で実体に接続する。使う語彙は既存プリミティブのみであり、DR-041 §1 の「AtomicAST スキーマ不変」をこの形が支える。

### canonical installer セット

registry の 3 層構造 (DR-010 / DR-040) に従い、標準として同梱する:

| installer | 所有語彙 | 植え付けるもの |
|---|---|---|
| `long` | `long` 属性 (variant DSL の値語彙 DR-011 を含む) | greedy 衛星 + eq-split 再解釈 matcher。config `long_prefix` / `allow_equal_separator` がパラメータ |
| `short` | `short` 属性 | greedy 衛星 + cluster / 値付着の再解釈 matcher。config `short_prefix` / `short_combine` がパラメータ |
| `dd` | `type: "dd"` | greedy 面の exact 衛星 (matcher は素の exact 一致)。発火後は継続を内部消費として引き継ぐ |
| `env` | `env` 属性 | env 席への lookup 宣言 |
| `command` | `commands[]` / `type: "command"` | DR-018 の or 式で positional 面へ展開。トリガは greedy マーク付き exact 衛星、部分木は新しい背骨を宣言する |
| `global` | `global` 属性 | 子孫 command スコープへ ref/link 衛星の宣言的コピーを追加。同名トリガを自前宣言するスコープへはコピーしない (= shadowing、最小スコープ優先 = lexical 解決 DR-032/033 のパース時適用)。findings F-007 の受け皿 |
| `inherit` | `inherit` 属性 | inherit 席 (DR-031) に「最近祖先の同名実体の値セル参照」lookup を宣言 |

方言 (Go 風単ダッシュ long 等) は拡張 installer または canonical installer のパラメータ差しで提供する。将来の候補: `config_key` (findings F-029、config ファイル席)、`repeat` / `multiple` (DR-043)、inheritable の prefix 生成 (DR-013 後継)。

**所有権の粒度は属性単位**。variant DSL (`long: ["no:set:false"]`) は long 属性の値の中の語彙なので long installer の内部に閉じる。内部表現 (文字列 DSL / オブジェクト形式 / 両対応) をどこまで凝るかは installer 実装の自由度であり、プロダクトとしては全体バランスで決める — 影響スコープが installer 単体に閉じることが本質。

**所有語彙は要素の形を問わず付きうる**: inline 型でも構造でも **ref 要素**でも、installer は同じ規則で寄与する (例: `{"name": "hlcolors", "ref": "color", "repeat": {"min": 1}}` — DR-043 参照)。

### matcher の座席と表現 (垂直スライス PoC で確定)

- **座席**: 再解釈 matcher も **greedy 面のエントリ**であり、exact 衛星と同列の住人 (どちらもトークンを読む matcher であることに変わりはない)。filter 席でも専用席でもない。先食い判定 (DR-041 §4) が両者を一様に扱えることがこの座席を正当化する
- **表現**: 再解釈 matcher はクロージャではなく**名前付きデータ** (種別 + 回収エントリ表)。lowering 後の全体が比較・直列化可能になり、installer 順列テストの構造比較と AtomicAST のシリアライズ可能性の両方をこれが支える
- **installer の類型は「何を植えるか」の違い**: long / short は exact 衛星 + 再解釈 matcher、dd は exact 衛星のみ、env は席宣言のみ。いずれも同じ 3 役 (回収・植え付け・能力提供) の部分集合

### config 上の表現 (方向)

installer インスタンスの選択・パラメータ化は config (DR-014) の階層継承に乗せる。不変則により適用順は非意味なので、順序を運ぶ表現は不要。フィールド語彙の具体形は本 DR では確定しない (射程外、垂直スライスと DR-014 拡張で確定する)。

### 検証マトリクス (垂直スライスへの持ち込み)

canonical 4 installer のサンプル適用では合成の交換可能性を確認済み (サンプル数 1)。次に壊しに行くべき組:

| ケース | 試される不変則 |
|---|---|
| global × dd (スコープ横断複製 × greedy 断ち) | ⑤の例外規則と②の両立 |
| 1 要素全部盛り (long + short + env + count + required) | 衛星の link 合流、DR-015 あと勝ちと accumulator の合成 |
| inheritable prefix 生成 × long | 衛星の exact 語彙生成の交差 (③) |
| env × config_key (値源 2 つ) | ④のラダー宣言の順序非依存、source タグ |
| dd を options 側に置く歪み定義 | 語彙の配置制約のエラー報告 |

canonical 4 installer の全 24 順列一致・1 要素全部盛り・dd 再スコープ・冪等 (①) は slice PoC で確認済み (21/21 pass)。global × dd / inheritable × long / env × config_key は未実施。

## 採用しなかった案

### long / short をコア文法として固定 (現状維持)

シュガー追加のたびにコア属性が増殖し、type / filters / multiple との非対称が残る。方言の差し替え点も作れない。

### 中央集権の gather-then-build プロトコル

各 installer の寄与を中央で収集してから一括組み立てする案。5 不変則で順序非依存が出るため、重い中央プロトコルは不要と判断。

### 値源の直接ラップ (`env_default_fn("PORT", original_default_fn)` 型)

ラップの巻き順が DR-031 ラダーの再実装になり (config_key が来た瞬間に破綻)、素通しラップは source タグを失う。席宣言型 (不変則④) に置換。

### priority フィールド / 配列順による適用順制御

順序依存を残す設計は不変則の放棄。順序が必要に見えるのは不変則違反の徴候 (見かけの依存は不動点反復で解消する)。

### 消費即除去 (installer が所有語彙を元定義から削除する)

当初案。削除すると後続 installer から宣言情報が見えなくなり、global × command のような組で適用順の制約が生まれる。読み取り専用の宣言層 + add-if-absent の方が、冪等・完全性検査を保ったまま順序自由度と宣言情報の保全 (help / diagnose / 再シリアライズ) を得られる。

### 評価器の多重背骨 (greedy の子孫スコープ到達を組み込み規則にする)

祖先スコープの背骨を子コマンド内でも第 2・第 3 の背骨として重ねる案。評価器に多重背骨と dd の相互作用の定義が増え、定義の局所性 (スコープの言語がそのスコープの宣言で閉じる) が崩れる。構造コピー (global installer) の観測等価な encoding としてなら実装が選んでよい。

### 統一名の候補で却下したもの

- **reader**: 読む = 受動的で、展開を植え付ける「操作の意図」が足りない
- **expander**: 糖衣展開は覆うが env / config の値源提供を覆えない
- **device**: 能動的に処理する processor 感がなく受動的な印象でズレる

**installer** は「展開ルール・実行時能力を植え付ける装置」との意味的一致で採用 (ボトムアップ実装の `install_*` 語彙との連続性は結果であって決め手ではない)。

## 射程外

- installer インターフェースの関数シグネチャの正規形は本 DR では確定しない (PoC の実測形は「(定義, 寄与先) を受けて回収と寄与を行う手続き」。垂直スライス DR-039 で実装と共設計する)。
- config 上のインスタンス表現のフィールド語彙は本 DR では確定しない (上述)。

## 関連

- DR-041 (トークン読みの意味論 — installer が植え付ける matcher の実行時契約、対で確定)
- DR-030 (実体だけノード — 展開の標準パターンの受け皿)
- DR-031 (値源の優先順位ラダー — エンジン所有、installer は席宣言のみ)
- DR-016 (ParserContext の source タグ — 不変則④が保存を保証)
- DR-014 (config — installer パラメータの供給源、階層継承)
- DR-010 / DR-040 (registry 3 層 — canonical installer の同梱区分)
- DR-035 (definitions / registry の一様性)
- DR-011 (variant DSL — long installer の内部語彙)
- DR-013 (inheritable — prefix 生成は将来の installer 候補)
- DR-039 (垂直スライス共設計 — シグネチャ確定の場)
- journal `2026-06-29-arggen-phase0-alignment.md`
- findings `2026-06-29-ast-missing-pieces.md` F-002 / F-003 / F-007 / F-029 / F-031 / F-035 / F-041
- 垂直スライス PoC (slice 枝 `poc/`、journal `2026-07-02-slice-poc.md`) — 24 順列一致・matcher 座席・2 類型の実測根拠
