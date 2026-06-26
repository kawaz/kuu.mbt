# DR-031: 値源の優先順位

## 決定

1つの結果セルに複数の値源がつきうる。優先順位は以下で固定する (高→低):

```
1. CLI 明示 / link    パース時の操作 (今この実行で明示指定)
2. 環境変数            実行環境の指定
3. config ファイル     永続設定
4. inherit (祖先 scope) 上位スコープからの暗黙継承
5. default / value     最終フォールバック (固定値)
```

「明示的に与えられたものほど優先」が原則。

## 各順位の根拠

- **CLI/link が最優先**: 「今この実行で明示的に言った」が最も具体的な意図。CLI と link は同列 (どちらもパース時のユーザ操作、DR-029 の「操作の時系列適用」がこの層)。
- **env > config**: 環境変数は「この実行環境で」の一時的指定、config ファイルは永続。一時 > 永続 (12-factor app 慣習)。
- **config > inherit**: 設定ファイルは明示的に書かれた値、inherit は「書かなければ親から」の暗黙継承。明示 > 暗黙。
- **default 最下位**: 何も来なかった時だけ。

## 順序は固定 (設定可能にしない)

値源優先順位には事実上の標準 (CLI > env > config > default) があり、動かしたいケースは稀。固定にして利用者の認知負荷を下げる。順序を設定可能にすると、それ自体が暗黙の罠になる (kuu の「暗黙ルールを増やさない」思想に反する)。動かしたい稀なケースは link や実体ノードの工夫で表現する。

## source の記録 (DR-016 拡張)

DR-016 の `source: cli/env/default` を、値源の増加に合わせて拡張:

```
source ∈ { cli, link, env, config, inherit, default }
```

結果オブジェクトで「この値はどこから来たか」を引ける。appconfig ストア用途 (DR-030) で、値源を隠蔽しつつ必要なら由来を確認できる。

## committed/selected との直交性 (DR-016 維持)

「その値が明示的に決まったか (committed/selected)」と「値そのもの (default で埋まっただけか)」は別軸。`required` 制約は committed を見る — default で埋まっただけでは required を満たさない。これは優先順位とは直交する別軸で、DR-016 の区別を維持する。

## 関連

- DR-013 (inherit), DR-014 (config) — 値源の機構
- DR-016 (source, committed/selected) — source 語彙を拡張、committed 区別を維持
- DR-029 (link は CLI と同列のパース時操作)
- DR-030 (実体だけノード、appconfig ストア)
