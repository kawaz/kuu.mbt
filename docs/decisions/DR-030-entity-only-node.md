# DR-030: 実体だけノード (入口属性を持たない値ノード)

## 決定

ノードの属性は「入口属性」と「値属性」に分かれる:

- 入口属性: short / long / positional 位置 — CLI からどう起動されるか
- 値属性: name / type / value / default — 何の値を持ち結果のどこに出るか

入口属性は全て optional。**値属性だけ持ち入口属性を持たないノード**が定義できる。CLI 引数では起動されないが、結果オブジェクトには現れる「実体だけのノード」。

```json
{name: "timeout", type: "number", value: 30}
// short も long も positional 位置も無い。CLI からは触れない。
// 結果に timeout: 30 として出る。
```

新概念ではない。入口属性を書かなければ自然にこうなる (DR-024/025 で name=値属性、入口=別属性と分離した帰結)。

## 用途 (kawaz)

| 用途 | 書き方の例 | 値の供給源 |
|---|---|---|
| link のプレースホルダ実体 | `{name:"logLevel", type:number, value:0}` を実体に、-v/--log-level が link | link 経由 |
| 環境変数専用 | `{name:"apiKey", type:string, env:"API_KEY"}` (入口なし、env だけ) | 環境変数 |
| ハードコード設定/マジックナンバー | `{name:"timeout", type:number, value:30}` | 固定値 |
| 設定ファイル由来 | `{name:"dbUrl", type:string, config:...}` | 設定ファイル (DR-014) |

> 単に設定ファイルとかアプリ内で使うほぼハードコードのタイムアウト値とかマジックナンバーとかを単にアプリ設定みたいな塊として管理したい、元一式全部詰め込んでパースリザルトを appconfig 的なストアにしたいみたいな用途 (kawaz)

## appconfig ストアとしての結果オブジェクト

この用途は、結果オブジェクトを「CLI 引数の解析結果」から「アプリ設定の統合ストア」に昇格させる。CLI 引数・環境変数・設定ファイル・ハードコード値を全部同じ結果オブジェクトに合流させ、アプリは result.timeout / result.apiKey / result.logLevel を一様に読む。値源 (CLI か env か固定か) はアプリから見えない = 値源の隠蔽。12-factor app の config 統合に近い。

## 配置による役割の違い

DR-007 の「definitions に値プレースホルダ」と、この「options に実体だけノード」は似ているが置き場所で役割が違う (DR-018 と一貫):

- definitions に置く → def name (参照専用、result 非露出)
- options/positionals に置く → result に出る実体

## export 制御

実体だけノードは基本 result に出す (それが目的)。ただし link 専用の中間セル (内部計算用の一時セル) は result に出したくない場合がある。`export: false` で「値は持つが result に出さない、link 元としてだけ存在」を表現 (DR-024)。

## 関連

- DR-007 (definitions 値プレースホルダ)
- DR-013 (inherit), DR-014 (config) — 値源
- DR-018 (配置で役割が決まる)
- DR-024 (name=値属性、export 制御)
- DR-031 (値源優先順位)
