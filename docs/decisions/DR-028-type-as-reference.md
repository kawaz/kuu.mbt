# DR-028: type は definitions/registry への参照糖衣、解決順と前方互換

> **更新: DR-032 により本 DR の「ref → type 統合の方向性」および「後続セッションへの宿題」リストは全項目陳腐化 (ref/link が指すのは name、type が指すのは型で対象が違うため統合不成立)。本 DR の type=参照糖衣 / 解決順 / 前方互換 / value_parser=AST外 / flag等は糖衣プリセット は引き続き有効。**

## 決定

### type は参照糖衣

`type: X` は「定義済みの型 X を参照する糖衣」。組み込み型もユーザ定義型も同じ `type:` で指定する。

```
type: "number"   → 組み込み (registry の value_parser)
type: "color"    → ユーザ定義 (definitions の構造テンプレ)
type: "cssColor" → ユーザ定義型 + value_parser (両方持ちうる)
```

### 解決順: definitions → registry → warn+string

型名の解決は以下の順:

1. definitions (ユーザ/ローカル) を探す
2. なければ registry (組み込み/グローバル) を探す
3. どちらにも無ければ warn + string フォールバック (文字列として取り出せる、strict なら error)

この順序は前方互換性の保証になっている。

#### 前方互換シナリオ (kawaz)

> ユーザ定義で duration みたいなのをフィルタで書いて number 型に落としてたとする。実は組み込み型の強化で duration 型を追加しました、ってなった時に元々ユーザ定義で動いてたのがエラーになるのは無しでしょ。でもユーザ定義があればそれ使うだけなら、その定義ファイルで問題が起こることはない。

```
時点1: definitions["duration"] をユーザが自作 → 動く
時点2: registry に組み込み duration が追加される
       → definitions 優先なので、ユーザの duration がそのまま使われる (壊れない)
```

「ユーザのローカル定義 > ライブラリのグローバル定義」という shadowing。レキシカルスコープでローカルが外側を shadow するのと同じ原則。同名禁止は不要——禁止する代わりにローカルが勝つ方が柔軟かつ前方互換。

### value_parser は AST 外 (registry)

`string → T` のパース関数はクロージャで JSON シリアライズ不能 (DR-010)。AST には `type: X` と名前だけ書き、関数本体は registry に登録 (利用時注入 or 組み込み)。

```
AST 側:      {type: "cssColor", value_name: "COLOR"}   名前だけ
registry 側: types["cssColor"] = parseCssColor          関数 (#f00/oklch() → Color)
```

未登録の value_parser は warn + string フォールバック (DR-021 の精神: warn はする、reject はしない、利用者を信頼)。

### 型定義の中身 = 普通の node + value_parser

型定義 (definitions エントリ / registry エントリ) は、普通の node が持てるフィールドを持てる:

```
type definition = {
  JSON で書ける部分 (definitions): or? / seq? / default? / filters? / value_name? / multiple? ...
  関数部分 (registry、名前で紐付け): value_parser
}
```

- 組み込み型 (number/string) = value_parser 中心、構造なし
- ユーザ構造型 (color) = 構造中心
- cssColor = value_parser + 構造の両方

意味論は「参照先を土台に、ノード自身のフィールドで上書き」で一本化 (ref の継承がそのまま乗る)。number は上書きする構造が無いだけ、color は構造ごと継承。

## flag/count/command/help は糖衣プリセット (type 値ではない)

DR-005 では flag/count/command/help を type の値として扱っていたが、今回の整理で「展開される糖衣プリセット」に寄せる。各々は独立した type ではなく、値プリミティブ + default + 挙動のプリセット:

- flag = bool + default:false + 起動で true セット
- count = number + default:0 + increment
- command = name トリガ + name でスコープ (DR-018 で commands[] 配置、DR-026 で seq[exact,...] 展開)
- help = 起動時アクション

kawaz:

> 糖衣プリセットだよ。color の時と同じで definitions にデフォルトとかフィルタとかが定義されてるのを type で使うだけなイメージ。なんなら string とか bool とかも内部的には value_parser に string→T な関数が指定された definitions 登録されてるだけじゃない?

→ 組み込み型も「最初から登録済みのプリセット」。string は value_parser:string→string が登録されたエントリ、number は string→number、flag は bool+default+挙動。**type フィールドは『定義済みプリセットへの参照』** という一貫した見方。

## 関連

- DR-005 (type categories) — flag等を糖衣に再整理、本 DR で更新
- DR-010 (external registry) — value_parser の登録機構、解決順を補完
- DR-021 (warn はする reject はしない) — 未登録 type のフォールバック方針
- DR-026 (型定義 = 葉/枝のフィールドを持てる)
- DR-032 (ref/link と type は別概念) — 本 DR の ref→type 統合方向性を撤回
- DR-035 (解決順を全 registry 区分に一般化)
- DR-040 (registry 運用の精緻化)

---

## Superseded (歴史)

> 以下の記述は後続 DR で覆された。現役仕様の理解には不要、判断経緯としてのみ残す。

### ref → type 統合の方向性 (DR-032 で撤回)

本 DR では `type` と `ref` の統合方向を検討していた:

> `type` と `ref` はどちらも「定義済みの何かを参照する」点で似ており、使い分けの分かりにくさがある。`ref` を `type` に統合する方向で検討した:
>
> - 統合のメリット: ユーザの認知が「定義済みを使うなら type」1つで済む。関数か構造かを意識しない。
> - 必要な制約: 解決順 (definitions→registry、上記) で衝突は解決。型定義 = node + value_parser。意味論は土台+自ノード上書きで一本化。
> - link は別概念 (値同期であって型参照でない) なので統合対象外、据え置き。
>
> ただし ref/link の具体的な使い方 (deprecated 別名、alias、値同期の挙動) の見直しは後回しとした。**本 DR では「type=参照糖衣」「解決順」「前方互換」「flag等は糖衣」までを確定し、ref→type 統合の最終確定と DR-007 の再編成は後続セッションに回す。**
>
> > 一旦ここでまとめて、後で統合するならするで再編成で良いんじゃ (kawaz)

DR-032 で「ref/link が指すのは name、type が指すのは型。指す対象が違うため統合は成立しない」と確定。ref→type 統合は不要かつ不可能として撤回された。

### 後続セッションへの宿題 (DR-032 撤回で全項目陳腐化)

本 DR は以下を後続宿題として残していたが、DR-032 で ref→type 統合自体が不成立と確定したため、全項目が陳腐化した (= 再編成は不要):

- ref/link の使い方の棚卸し (DR-007 読み直し) — 不要 (統合しないので棚卸し不要、DR-007 はそのまま active)
- ref → type 統合の最終確定 — 撤回 (統合不成立)
- 統合する場合の definitions/registry/type/ref の再編成 — 不要 (統合しない)
- 型定義エントリの正式スキーマ (value_parser の紐付け方) — 本 DR 本文の「型定義の中身 = 普通の node + value_parser」で十分、追加スキーマ確定は不要
