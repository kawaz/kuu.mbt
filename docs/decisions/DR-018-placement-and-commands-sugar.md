# DR-018: 配置で区別、commands は positionals 内 or への糖衣

## 決定

定義時の3概念 (command / option / positional) の区別は **配置 (所属配列)** で行う:

- **options[]**: ハイフン起動・順不同の要素群。
- **positionals[]**: 位置消費される要素群。
- **commands[]**: サブコマンド群を簡潔に書くための糖衣 (下記)。

`option` / `positional` は **type を書かない** (所属配列が役割を決める)。`command` は配置だけでは表現しきれない (トップにも positionals 内にも現れ、スコープを切る) ため `type: "command"` で名乗る。

### commands 糖衣の展開

`commands: [...]` は以下に展開される:

```json
"positionals": [
  {"type": "or", "children": [ ...commands, ...original_positionals ]}
]
```

- commands と元の positionals 全体が **or で排他**。
- **commands が先**、original_positionals が後 (完全経路として command 名にマッチすればそちら、しなければ素の positional として消費)。
- **commands 不在時は or で包まない** (positionals はそのまま)。

これにより `git`（path を取らずサブコマンドだけ）も `git foo.txt`（command 名にマッチせず positional 消費）も一意に解ける。

## 経緯

### 表記パターンの比較

3案を比較した:

- **案A (純 type 区別)**: flat children に全部 type で名乗らせる。option/positional の順序性がフィールドから見えず、or 構造が flat に埋もれる。DR-004 で却下した「matchBy で flat」と同欠点。
- **案B (純 配置区別)**: command を `{"command": {...}}` でラップ。配置区別なのに command だけ表記が割れ、トップが command である事実も定義に現れない。
- **案C (ハイブリッド)**: option/positional は配置・無 type、command/構造要素のみ type。← 採用方向。

kawaz の指摘で案 C の例 (path の後にサブコマンド) が不自然と判明し、`commands` 専用配列の復活へ:

> C は path の後にサブコマンドが配置されて変では? ポジショナルから type:command だけ先に抜くくらいなら commands: [...] では?

`commands` は DR-004 で一度却下したが、却下理由は「定義語彙を同型に潰す」前提だった。DR-017 でその前提が覆ったため、**糖衣としての commands 復活は今回の方針と整合**する。

### 展開位置

当初「positionals 末尾に or 挿入」案が出たが、kawaz の展開イメージ:

> commands はこう展開されるイメージ
> positionals:[{type:or, children:[ ...commands, original_positionals ]}]

これは「サブコマンドか、さもなくば素の positional か」の排他を or 一発で表現しており、末尾挿入より正しい。末尾挿入案は撤回。

## subcommand の位置に制約を課さない

「subcommand は positional 列先頭でのみ分岐」という制約案は却下:

> ポジショナルを撮った後にサブコマンドは別に禁止しなくね? もともとポジショナルやオプションにコマンドを入れることもできるとしてる。

`commands` 糖衣はあくまで「ルート直下の主要サブコマンド群を簡潔に書く」ショートハンド。command の配置可能位置を制限するものではない。途中分岐・復帰が必要なら positionals/options の要素として command を直接置けばよい (DR-020)。**「曖昧さなく完全経路で一意に解決できる限り許す」** が原則。

## 採用しなかった案

### 案A (純 type 区別)

順序性が見えず、or 構造が埋もれる。

### 案B (純 配置区別、command をラッパで)

command の表記が割れ、トップが command である事実が消える。

### 末尾挿入

「サブコマンドか素の positional か」の排他を表現できない。

## 効果

- option/positional の順不同/順序が配置で一目で分かる。
- サブコマンドの排他構造が or として明示される。
- トップレベルが `type: "command"` で定義に現れる (アプリ自身がルートコマンド)。
- 普通のケースは `commands: [...]` で簡潔、特殊ケースは positionals 内に直接構造を書ける逃げ道がある。
- 正規形が前回 DR-004 の positionals 内 or に収束 = 過去 DR と合流。

## type 省略ルール

- type 省略時のデフォルトは所属配列で決まる (options[] → option、positionals[] → positional)。
- command / or / その他の構造要素は type 必須 (配置で決まらない)。
- option/positional に `type` 明示は許容するが冗長 (配置と不一致ならエラー)。

## 関連

- DR-002 (全要素同型)
- DR-004 (options/positionals 分割) — commands 却下を糖衣として部分撤回
- DR-017 (command 定義時1級)
- DR-019 (構造プリミティブと値伝搬)
- DR-020 (command の復帰/途中分岐は構造で組む)
