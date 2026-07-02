# DR-042: installer アーキテクチャ — 特殊語彙は装置が持ち込み、5 つの不変則で合成する

> 由来: 本セッションの議論で確定。DR-041 (トークン読みの意味論) と対。findings `2026-06-29-ast-missing-pieces.md` の F-002 / F-003 / F-007 (方向) / F-029 (方向) / F-031 (方向) / F-035 / F-041 (受け皿) に関係する。

## 決定

### installer とは

`long` / `short` / `env` / dd のような**特殊語彙 (属性名・type 値) は、コア文法ではなく installer の所有語彙**とする。installer は registry に登録される装置で、1 単位で次の 3 役を担う:

1. **所有語彙の回収**: UsefulAST から自分の語彙を読み取り、元定義から除去する
2. **展開の植え付け**: 糖衣展開 (衛星構造の追加・再スコープ化) を行う
3. **実行時能力の提供**: 必要なら再解釈 matcher (トークン読み、DR-041) や値源 lookup を評価器に登録する

parse_definition (UsefulAST → AtomicAST) は installer 適用の連鎖として構成される。コア文法は atomic (exact / or / seq / primitive + multiple) と name / ref / link 等の骨格のみに縮む。

### 先行例: このパターンは既に中心原理

`type` (types registry) / `filters` (filters registry) / `multiple` (multiple registry) は「フィールド名で registry が暗黙決定」(§13.2) されており、**属性語彙と registry 実装のペアは kuu の既定路線**である。`long` / `short` / `env` は registry の後ろ盾なしにハードコードされた取り残しであり、本 DR はこの非対称を解消する。シュガーが増えるたびにコア属性が増殖する問題も、installer の追加 (= 語彙の所有者の追加) に置き換わる。

### 5 つの不変則 (合成契約)

installer の合成を順序非依存・冪等に保つ。組み込み installer はこれを厳守し、外部 installer にも遵守を求める (破る実装が悪い、という責任分界):

1. **消費即除去**: installer は所有語彙を回収したら元定義から除去する。再適用は no-op (= 冪等が定義から出る)。全 installer 適用後に**残った**特殊語彙は「担当 installer 不在の未知語彙」としてエラー + 次の手 hint (§13.5 の型) — 完全性検査が構造から出る。
2. **追加的寄与**: 既存要素への操作は「所有語彙の除去」と「値源席への宣言」まで。構造は衛星 (新要素) として追加し、**他 installer の産物を書き換えない**。
3. **所有語彙の交差禁止**: 同一語彙を 2 つの installer が所有したら registry 登録時にエラー。
4. **値源はラダー席への宣言**: 値源系 installer (env 等) は default_fn を直接ラップせず、**エンジンが所有する DR-031 の優先順位ラダー**の席 (env / config / inherit / default) に lookup を宣言する。lookup は (value, source) を返し、ParserContext の source タグ (DR-016 / DR-031) を保存する。ラダーの順序自体は installer から動かせない。
5. **greedy 面の断ちは構造で表現する**: 入れ子 command は自スコープの面宣言が (`git --git-dir X commit` の後で git 側 options は効かない)、dd は発火後の内部消費 (greedy 内部は一体、DR-041 §4) が、それぞれ greedy の割り込みを断つ。評価器の大域 mode は導入しない。`global: true` (findings F-007) はスコープ境界の断ちに**例外を作る側**の installer として将来定義する。

順序依存が要ると感じたら不変則違反の徴候として設計を見直す (priority フィールドや配列順への依存は持ち込まない)。

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

元要素はマッチ能力を衛星に移譲し、**値だけを持つ実体だけノード (DR-030) に降格**する。衛星は ref (構造継承) + link (値同期) で実体に接続する。使う語彙は既存プリミティブのみであり、DR-041 §1 の「AtomicAST スキーマ不変」をこの形が支える。

### canonical installer セット

registry の 3 層構造 (DR-010 / DR-040) に従い、標準として同梱する:

| installer | 所有語彙 | 植え付けるもの |
|---|---|---|
| `long` | `long` 属性 (variant DSL の値語彙 DR-011 を含む) | greedy 衛星 + eq-split 再解釈 matcher。config `long_prefix` / `allow_equal_separator` がパラメータ |
| `short` | `short` 属性 | greedy 衛星 + cluster / 値付着の再解釈 matcher。config `short_prefix` / `short_combine` がパラメータ |
| `dd` | `type: "dd"` | greedy 面の exact 衛星 (matcher は素の exact 一致)。発火後は継続を内部消費として引き継ぐ |
| `env` | `env` 属性 | env 席への lookup 宣言 |

方言 (Go 風単ダッシュ long 等) は拡張 installer または canonical installer のパラメータ差しで提供する。将来の候補: `config_key` (findings F-029、config ファイル席)、`global` (F-007)、inheritable の prefix 生成 (DR-013 後継)。

**所有権の粒度は属性単位**。variant DSL (`long: ["no:set:false"]`) は long 属性の値の中の語彙なので long installer の内部に閉じる。内部表現 (文字列 DSL / オブジェクト形式 / 両対応) をどこまで凝るかは installer 実装の自由度であり、プロダクトとしては全体バランスで決める — 影響スコープが installer 単体に閉じることが本質。

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

順序依存を残す設計は不変則の放棄。順序が必要に見えるのは不変則違反の徴候。

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
