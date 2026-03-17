# kuuを使った引数パースのデモプログラムの作成

## 目的

身近なアプリのモックを実際に作成してみることで以下を確認する。

- kuuのポテンシャル確認
- kuuの問題点の洗い出し
- 実際のプログラムをこのように書けるというサンプルの提供

## 命名規則

ワークスペース名・ディレクトリ名・タグ名は全て同じ形式を使う。

```
YYYYMMDD-{app}[-{lang}][-{extra}]
```

- `{app}`: モックする CLI 名（curl, kubectl, cargo 等）
- `{lang}`: 言語識別子（moonbit, typescript, go, python, swift, rust 等）。MoonBit の場合も省略せず付与する
- `{extra}`: バリエーション等の補足（省略可）
- **略称禁止**: 後で見て意味が分からない略称は使わない（例: `sf` → `struct-first` と書く）

例: `20260309-cargo-python`, `20260309-curl-moonbit`, `20260309-mydocker-go`

## 作業手順

1. APP、LANG、バリエーションの指示がまだならQAツールを使ってユーザに確認する。
  - 選択肢は既存examplesや`jj workspace list`も確認し、被りも多少は気にしつつ面白そうな組み合わせやチャレンジを提案する
  - ユーザは面倒くさがりなのでこのQAの各項目の最初の選択肢に「エキサイティングな組み合わせを自由に選んんで」を置くこと
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
echo "wsname: YYYYMMDD-{app}[-{lang}][-{extra}]"
echo "wsdir: $(jj workspace root --name {wsname})"
echo "workdir: {wsdir}/examples/{wsname}"
```

### 作業ワークスペース作成(無ければ)

基本的には `main@` の最新コミットから生やす。（`xxx@` はワークスペースxxxのカレントコミットを指す書式）

```
# ワークスペース作成
jj workspace add "{wsname}" -r main@

# ワークスペースの最初のコミットに説明を付けつつ作業用の空コミットを作っておく
jj describe -R "{wsdir}" -m "chore: START {wsname}"
jj new -R "{wsdir}"

# 作業ディレクトリの作成
mkdir -p "{workdir}"

# ユーザ指示の引き継ぎを兼ねる "{workdir}/README.md" まで用意しておくこと（新規セッションでスタートするので）
```

### 新規セッションの開始依頼

新規タブや分割で以下を貼り付けて新規セッションを開始してください。とユーザに依頼する。

```
cd "/path/to/{wsdir}" &&
claude \
  --add-dir "{repo}" \
  --dangerously-skip-permissions \
  '/itumono-example {workdir} を見て作業開始'
```

画面に表示しつつQAツールでクリップボードに入れますか？ と確認し、OKなら pbcopy にぶち込む

### 付録：ユーザのディレクトリ構成

ユーザは以下のようなディレクトリ構成で普段作業をしている。

```
~/.local/share/repos/github.com/{user}/{repo}/
  .git          # git bare repository
  .jj           # jj directory of default workspace
  .             # default workspace (基本的には empty のまま放置)
  main/         # main ワークスペース
  {workspace}/  # 並行作業は作業ごとにワークスペースを作ってそこで行う
    justfile
    src/
    examples/
      archives/         # 完了済み example のアーカイブ
    docs/
      decision-records/ # 方針や決定を行った際の経緯や理由を記録
        DR-001-xxx.md
      plans/
      knowledge/
        YYYYMMDD-xxx.md
      research/
        YYYYMMDD-xxx.md
      DESIGN.md
```

## 作業指示
現時点の kuu を利用して指定アプリの引数パースを行えることを検証するための実証コードの作成。
あくまで引数パースの検証用サンプルであり、指定アプリの機能自体の実装は不要です。

### やること
- 指定ディレクトリをあなたのプロジェクトトップと考え、その中にREADME,docs,src,justfileなど配置する形でお願いします。
- 作業中の気づいた点や思考したことは適宜DRとして記録を作成しながら進めてください。
- 作業に伴いDESIGN.mdも更新してください。
- キリの良い単位で適切にコミットしながら進める。作業に夢中でこれを忘れないようCronツールで30分毎のリマインドを設定する。
- キャラ設定
  - `vsay list` からキャラを選択（並列で作業してるエージェントと被らないよう直近の `jj log` を確認）
  - `jj new -m "chore: CVをXXXに変更" --insert-before @` を実行(以降のコミットログやドキュメント作成はそのキャラで行う)
  - Cronツールで10分毎にユーザに現状を`vsay`を使って音声で簡潔に報告する。前回と変化がない場合は何も喋らない。

/itumono-full-loop 手順でフルオートモードで行ってください。ループ数の上限は特に指示がなければ納得するまで。

### 後片付け

この作業指示書によって設定されたCron設定を解除

```bash
# example の作成が完了したと判断したら

## ワークスペースの最後のコミットに変更が含まれている場合は空コミットを作成
jj new -R "{wsdir}"

## 最後の空コミットに END マークを付ける
jj describe -R "{wsdir}" -m "chore: END {wsname}"

## タグを付ける（名前はワークスペース名と同じ）
jj tag set "{wsname}" -r "{wsname}@"

## 完了した example を archives に移動
mv "{wsdir}/examples/{wsname}" "{repo}/main/examples/archives/{wsname}"
```
