# kuuを使った引数パースのデモプログラムの作成

## 目的

身近なアプリのモックを実際に作成してみることで以下を確認する。

- kuuのポテンシャル確認
- kuuの問題点の洗い出し
- 実際のプログラムをこのように書けるというサンプルの提供

## 作業手順

1. APP、LANG の指示がまだならQAツールを使ってユーザに確認する
2. 作業場所の確認
3. 作業指示に従い作業を開始する

## 作業場所

### 現在位置の確認

現在位置を確認して与えられた作業のための場所ぽければ作業内容に進み指示に従う。

もしmainなど作業場所ではなさそうなら作業用ワークスペースを作成し新規セッションの開始依頼をユーザに行う。

```
echo "pwd: $(pwd)"
echo "repo: $(git root)"
echo "wscur: $(jj root)"
echo "wsname: example-YYYYMMDD-{APP}-{LANG}[-{EXTRA}]" # 単にkuuを使ってみた以外に、例えばclapのDXで内部はkuuみたいなのを実践してみるとかの実験の場にしてもOK
echo "wsdir: $(jj workspace root --name {wsname})"
echo "workdir: {wsdir}/examples/{wsname}"
```

### 作業ワークスペース作成(無ければ)

基本的には `main@` の最新コミットから生やす。（`xxx@` はワークスペースxxxのカレントコミットのを指す書式） 

```
# ワークスペース作成
jj workspace add "{wsname}" -r main@""

# ワークスペースの最初のコミットに説明を付けつつ作業用の空コミットを作っておく
jj -R "{wsname}@" -m "chore: START {wsname}"
jj -R "{wsname}@" new
```

### 新規セッションの開始依頼

新規タブや分割で以下を貼り付けて新規セッションを開始してください。とユーザに依頼する。

```
( cd /path/to/{workspace} && claude --allow-dangerously-skip-permissions /itumono-example )
```

### 付録：ユーザのディレクトリ構成

ユーザは以下のようなディレクトリ構成で普段作業をしている。

```
~/.local/share/repos/github.com/{user}/{repo}/
  .git          # git bare repogitory ( `cd {repo} && git init --bare .git` で作成
  .jj           # jj directory of default worktree ( `cd {repo} && jj git init --git-repo .git` で作成
  .             # default worktree (基本的には empty のまま放置、`cd {repo} && jj worktree add main` などしてそちらで作業を行う
  main/         # main ワークスペース(個人リポジトリでで基本 jj を使ってる。仕事用や古いとこだとgitのmainワークツリー
  {workspace}/  # 並行作業は作業ごとにワークスペースを作ってそこで行う `jj worktree add ../wip-xxx; cd ../wip-xxx; claude`
    justfile            # ビルド手順とかすぐ忘れるので `just` とかすればとりあえずOKみたいにしておく
    src/
    examples/           # サンプルコード置き場など
    docs/               # ドキュメント置き場
      desision-records/ # 方針や決定を行った際の経緯や理由を記録する場所
        DR-001-xxx.md   # 時系列がわかるよう連番で作成する（設計書などで「DR-XXXの作業」みたいに参照しやすさのため日付じゃなく連番）
      plans/            # 作業計画を保存したりしなかったり
      knowledge/        # 作業中に発見したナレッジなどの保管場所
        YYYYMMDD-xxx.md # 時系列がわかるよう日付プレフィクスで作成
      research/         # 何かの調査を行った記録を残す場所
        YYYYMMDD-xxx.md # 時系列がわかるよう日付プレフィクスで作成
      DESIGN.md         # プロジェクトの設計書、常に最新を保ち実装やDRとの乖離がないか定期的に整合性チェックを行う
    poc/                # 技術検証の為のPoCコードを置く場所手探りの雑コードだったりプロジェクトが進んだ時から見たら古いコード
      poc001-xxx/       # コンテキスト汚染の元凶になりがちなのでAIルールで poc/ 以下のファイルは原則アクセス禁止としておく
                        # ユーザ指示により理由と目的とがる場合のみアクセスをを許可する
                        # AIルールで poc/ ディレクトリ以下のファイルは原則アクセス禁止として、おく、ユーザ指示と
```

## 作業指示
現時点の kuu を利用してて指定アプリの引数パースを行えることを検証するための実証コードの作成
あくまで引数パースの検証用サンプルであり、指定アプリの機能自体の実装は不要です。

### やること
- 指定ディレクIトリをあなたのプロジェクトトップと考え、その中にREADME,docs,src,justfileなど配置する形でお願いします。
- 作業中の気づいた点や思考したことは適宜DRとして記録を作成しながら進めてください。
- 作業に伴いDESIGN.mdも更新してください。
- キリの良い単位で適切にコミットしながら進める。作業に夢中でこれを忘れないようCronツールで30分毎のリマインドを設定する。
- キャラ設定
  - `vsay list` からキャラを選択（並列で作業してるエージェントと被らない用直近の `jj log` を確認）
  - `jj new -m "chore: CVをXXXに変更" --insert-before @` を実行(以降のコミットログやドキュメント作成はそのキャラで行う)
  - Cronツールで10分毎にユーザに現状を`vsay`を使って音声で簡潔に報告する。前回と変化がない場合は何も喋らない。
  
/itumono-full-loop 手順でフルオートモードで行ってください。ループ数の上限は特に指示がなければ納得するまで。

### 後片付け

この作業指示書によって設定されたCron設定を解除

````
# exampleの作成が完了しと判断したら

## ワーススペースの最後のコミットに変更が含まれている場合は空コミットを作成
jj new -r "{wsname}@"

## 最後の空コミットに END マークを付ける
jj -m "chore: START {wsname}" -r "{wsname}@" 

## 更にタグを付けておく
jj tag set "{wsname}" -r "{wsname}@"
