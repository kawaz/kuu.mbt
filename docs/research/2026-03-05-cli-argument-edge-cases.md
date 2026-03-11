# CLI引数の変態的パターン調査

## 1. ショートオプション結合

### 1.1 基本的なフラグ結合: `-abc`

複数のブール型ショートオプションを1つのダッシュの後に連結する。

```
-abc  →  -a -b -c
```

**POSIX Guideline 5** で規定:
> "One or more options without option-arguments, followed by at most one option that takes an option-argument, should be accepted when grouped behind one '-' delimiter."

| パーサ | 対応 | 備考 |
|---|---|---|
| C getopt | Yes | POSIX標準 |
| C getopt_long | Yes | getoptの上位互換 |
| Python argparse | Yes | 3.x で対応。最後のオプションが値を取れる |
| Python click | Yes | argparse ベース |
| Rust clap | Yes | `Arg::short` で自動的に結合対応 |
| Go flag | **No** | `-abc` = 1つのフラグ名 `abc`。結合非対応 |
| Go pflag (cobra) | Yes | boolショートフラグのみ結合可能 |
| Node.js commander | 部分的 | 結合をサポートするがドキュメントが薄い |
| Node.js yargs | 部分的 | yargs-parser が対応 |
| Perl Getopt::Long | 設定次第 | `bundling` 設定を有効にすると対応 |

### 1.2 値付きオプションとの混在結合: `-euo pipefail`

bashの `set -euo pipefail` のように、結合の最後のオプションが引数を取るパターン。

```
-euo pipefail  →  -e -u -o pipefail
-oArg          →  -o Arg  (値がオプションに直結)
-cblue         →  -c blue (値をスペースなしで指定)
```

**規則**: 結合中、引数を取るオプションは**最後**でなければならない。それ以降の文字列は値として解釈される。

```
-abc value     (a, b はフラグ、c が value を取る)
-abcvalue      (a, b はフラグ、c の値が "value")
```

| パーサ | 直結値 (`-oArg`) | 分離値 (`-o Arg`) | 結合+値 (`-abo Arg`) |
|---|---|---|---|
| C getopt | Yes | Yes | Yes |
| Python argparse | Yes | Yes | Yes |
| Rust clap | Yes | Yes | Yes |
| Go pflag | Yes | Yes | Yes (bool のみ結合) |
| Perl Getopt::Long | 設定次第 | Yes | bundling 時のみ |

### 1.3 grep的パターン: `-vA1B1`

```
-vA1B1  →  -v -A 1 -B 1  ?
```

これは**標準的なパーサでは動作しない**。理由:
- `-v` はフラグだが、`-A` は値を取る
- 結合中に値を取るオプションが現れた時点で、残りは全て値として解釈される
- したがって `-vA1B1` は `-v -A "1B1"` と解釈される

grepが `-vA1B1` を正しく解析できるのは、`A` と `B` の引数が**常に数値**であることを利用した独自パーサによるもの。汎用パーサでは再現困難。

### 1.4 カウントパターン: `-vvv`

同じフラグを繰り返して出現回数をカウントする。

```
-vvv   →  verbose level 3
-qqq   →  quiet level 3
```

| パーサ | 対応方法 |
|---|---|
| Python argparse | `action="count"` |
| Rust clap | `Arg::action(ArgAction::Count)` |
| Go pflag | `CountP` / `CountVarP` |
| Perl Getopt::Long | bundling + `$verbose++` のインクリメント |
| Node.js commander | `.argParser()` でカスタム実装 |
| Node.js yargs | `count: true` |

**注意**: 結合中のカウント (`-vvv`) と結合+異種フラグ (`-vvf`) の区別はパーサが自動判別する。

### 1.5 Perl Getopt::Long の bundling モード詳細

Perl の Getopt::Long は `bundling` 設定で結合を制御する特殊な仕組みを持つ:

- **bundling 無効 (デフォルト)**: `-vax` は `--vax` と同じ (単一ダッシュのロングオプション)
- **bundling 有効**: `-vax` は `-v -a -x` に展開。ロングオプションは `--` 必須
- **bundling_override**: bundling 有効 + 1文字オプションがロングオプションを上書き

---

## 2. 数値引数パターン

### 2.1 `tail -10` (レガシー数値オプション)

```
tail -10      # 最後の10行 (= tail -n 10)
tail +10      # 10行目以降 (= tail -n +10)
head -5       # 最初の5行 (= head -n 5)
```

**歴史**: UNIX V7時代の構文。POSIX.1-2001 で**非推奨 (obsolescent)** と明記。

**実装**: 汎用パーサでは扱えない。各ツールが独自にpre-processingで `-10` を `-n 10` に変換するか、カスタムパーサで処理する。

### 2.2 `nice -20 command`

```
nice -20 command    # priority -20 で実行
nice --20 command   # 一部の実装で同じ意味
```

`nice` の `-N` は数値そのものがオプション引数のように振る舞う。GNU coreutils では `-n` オプション (`nice -n -20 command`) が正式な形。

### 2.3 `kill -9` / `kill -TERM`

```
kill -9 pid       # signal 9 (SIGKILL)
kill -TERM pid    # signal TERM
kill -s TERM pid  # POSIX準拠形式
```

シグナル名/番号がダッシュ直後に来る。汎用パーサでは負数と区別できない。

### 2.4 汎用パーサでの対応

| パーサ | 負数値の扱い |
|---|---|
| Rust clap | `Arg::allow_negative_numbers(true)` で明示的に許可 |
| Python argparse | 負数は自動認識するが、`-1` がオプション名と衝突する場合は曖昧 |
| Go pflag | 明示的なサポートなし。`--` セパレータで回避 |

**設計指針**: レガシー数値オプション (`-10`) は汎用パーサの範疇外。対応するなら前処理(プリプロセッサ)で変換するアプローチが現実的。

---

## 3. その他の変則パターン

### 3.1 単一ダッシュ + ロング名: `find -name`

```
find -name "*.txt" -type f -mtime +7
```

findは**全てのオプションが単一ダッシュ + 複数文字**。これはPOSIX Guideline 3 (オプションは1文字) に違反するが、findは「オプション」ではなく「プライマリ (述語)」として定義されており、ガイドライン適用外。

**他の例**:
- X Window System: `-display :0`, `-geometry 80x24`, `-font fixed`
- Tcl/Tk: `-background red`, `-padx 10`
- Java: `-classpath`, `-Xmx512m`
- mpv: `-vo gpu`, `-ao pulse`

**歴史**: X11 (1984年) がこの規約を確立。GNUの `--` 規約 (1990年) より前のため、単一ダッシュがロングオプションに使われた。X Toolkit Intrinsics はさらにオプション名の**一意な省略**を許可する (`-disp` = `-display`)。

### 3.2 JVM引数: `-Xmx512m`

```
java -Xmx512m -Xms256m -XX:+UseG1GC -Dfoo=bar
```

JVMの引数体系:
- `-X`: 非標準オプション (例: `-Xmx`, `-Xms`, `-Xss`)
- `-XX:`: 詳細チューニング。`+`/`-` でbool切替、`=` で値設定
- `-D`: システムプロパティ (`-Dprop=value`)
- `-agentlib:`: ネイティブエージェント

**特異性**: オプション名と値の間にセパレータがない (`-Xmx512m` = `-Xmx` + `512m`)。プレフィックスベースの独自パーサ。

### 3.3 GCC最適化: `-O2`

```
gcc -O2 -Wall -Wextra -std=c17
```

`-O` の後に直接レベルが続く。`-O0`, `-O1`, `-O2`, `-O3`, `-Os`, `-Ofast`, `-Og`。
`-W` も同様: `-Wall`, `-Werror`, `-Wno-unused`。

**実装**: GCCは完全に独自のパーサを使用。汎用パーサでは `-O` を値付きオプション(スペースなし直結)として定義すれば近い動作は可能。

### 3.4 SSH複合値: `-L 8080:localhost:80`

```
ssh -L 8080:localhost:80 user@host
ssh -L [bind_address:]port:host:hostport
ssh -R 9090:localhost:3000 user@host
```

値の中にコロンで区切られた構造がある。パーサにとっては単なる文字列値だが、アプリケーション層で構造をパースする必要がある。

### 3.5 dd の key=value 形式

```
dd if=/dev/zero of=/dev/null bs=1M count=100
```

**特異性**:
- ダッシュもダブルダッシュも使わない
- `key=value` 形式がオペランド (引数) として並ぶ
- POSIX の Utility Syntax Guidelines に完全に違反

**歴史**: ddの構文はIBM JCLの `DD` ステートメントに由来する (`DD DSN=...`)。Unix V5 (1974年) から存在。

### 3.6 tar のダッシュなし結合: `tar xzf file.tar.gz`

GNU tarは3つのオプションスタイルをサポート:

**1. Old Style (ダッシュなし)**:
```
tar xzf file.tar.gz
tar cvf archive.tar dir/
```
最初の引数がダッシュで始まらなければ old style。引数を取るオプションの値は、オプション群の**後に出現順で**対応する。

**2. Short Style (ダッシュあり)**:
```
tar -x -z -f file.tar.gz
tar -xzf file.tar.gz
```

**重大な罠**: `tar cfz archive.tar.gz dir/` と `tar -cfz archive.tar.gz dir/` は**全く異なる**動作をする:
- Old style `cfz`: `c`=create, `f`=archive.tar.gz, `z`=gzip → 意図通り
- Short style `-cfz`: `c`=create, `f`=z (fの値が"z"), gzip指定なし → 壊れる

**3. Long Style**:
```
tar --create --gzip --file=archive.tar.gz dir/
```

### 3.7 rsync の混在パターン

```
rsync -avz --exclude='*.tmp' --delete src/ dest/
```

ショートフラグの結合 (`-avz`) とロングオプション (`--exclude`) の混在。これは POSIX/GNU 規約に完全に準拠した正当なパターン。

### 3.8 curl の繰り返し値付きオプション

```
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer token" \
  -d '{"key":"value"}'
```

`-H` を複数回指定して値を蓄積する。パーサ的には `append` アクション。

| パーサ | 複数指定の扱い |
|---|---|
| Python argparse | `action="append"` |
| Rust clap | `Arg::action(ArgAction::Append)` |
| Python click | `multiple=True` |
| Go pflag | `StringArrayP` |

### 3.9 `test` / `[` のシェルビルトイン引数

```
test -f file
[ -f file ]
[[ -f file ]]
```

**特異性**:
- `-f` は「オプション」ではなく「述語演算子」
- `[` はコマンド名であり、`]` は必須の最後の引数
- 引数の数に基づく文法 (0引数 → false, 1引数 → 非空判定, 2引数 → 単項演算, 3引数 → 二項演算)
- 通常のCLI引数パーサとは完全に異なる独自文法

### 3.10 git の `--pretty=format:"%H %s"`

```
git log --pretty=format:"%H %s"
git log --pretty=oneline
git log --format="%h - %an, %ar : %s"
```

`=` の後にコロンを含む値。パーサ的には `--pretty` の値が `format:"%H %s"` という文字列。`=` で分割後の値にさらにアプリケーション固有の構造がある。

### 3.11 `--` (ダブルダッシュ) セパレータ

```
rm -- -f                    # -f という名前のファイルを削除
git checkout -- file.txt    # ブランチ名とファイル名の曖昧性解消
ssh host -- command args    # リモートコマンドへの引数渡し
```

**POSIX Guideline 10** で規定。全てのPOSIX準拠パーサが対応必須。

### 3.12 `-` (単独ダッシュ) = 標準入出力

```
cat -              # stdin から読む
tar cf - dir/      # stdout に出力
echo "data" | diff - file.txt
```

**POSIX Guideline 13** で規定。`-` はオプションではなくオペランド。

### 3.13 `+` プレフィックス

```
tail -n +5         # 5行目から (POSIX)
sort +2            # 旧式: 3番目のフィールドでソート
date +"%Y-%m-%d"   # フォーマット文字列
```

GNUのgetoptは一時期 (1990-1992) `+` をロングオプションのプレフィックスに使用していた。POSIX 1992年制定時に禁止され `--` に移行。現在の `POSIXLY_CORRECT` 環境変数に名残がある。

### 3.14 Windows `/` プレフィックス

```
dir /S /B
xcopy /E /I src dest
cmd /C "command"
```

Windows では `/` がオプションプレフィックス。パス区切りも `\` のため衝突しない。PowerShell は `-` プレフィックスに移行した。

---

## 4. 規約・標準

### 4.1 POSIX Utility Syntax Guidelines (IEEE Std 1003.1)

[12. Utility Conventions](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html) より:

| GL | 要旨 |
|---|---|
| 1 | ユーティリティ名は2-9文字 |
| 2 | 小文字と数字のみ |
| 3 | オプション名は1文字の英数字。`-W` はベンダ予約。**多桁オプション禁止** |
| 4 | 全オプションは `-` で始まる |
| 5 | 引数なしオプションは結合可能。値付きは結合の最後のみ |
| 6 | オプションと引数は別々の引数。ただし直結も許可 |
| 7 | **引数は省略不可** (optional argument 非推奨) |
| 8 | 複数値は1引数内にカンマまたはスペースで区切る |
| 9 | オプションはオペランドより前 |
| 10 | `--` でオプション終了 |
| 11 | オプションの順序は任意 (相互排他は別) |
| 12 | オペランドの順序はツール依存 |
| 13 | `-` は stdin/stdout を意味する |
| 14 | GL3-10 でオプションと識別できるならオプションとして扱う |

**重要**: これらは "should" (推奨) であり "shall" (必須) ではない。多くの歴史的ツールが違反している。

### 4.2 GNU Coding Standards

[Command-Line Interfaces](https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces.html):

- ロングオプション: `--` で始まる、ハイフン区切りの単語 (`--ignore-backups`)
- 値: スペースまたは `=` で区切る (`--output file` / `--output=file`)
- 省略: 一意であれば省略可能 (`--ign` = `--ignore-backups`)
- 否定: `--no-` プレフィックス (`--no-color`)
- 標準オプション: `--help` と `--version` を全プログラムで提供
- 引数の位置自由: GNU getopt はオプションとオペランドの混在を許可 (permutation)

### 4.3 BSD vs GNU getopt の違い

| 項目 | BSD (POSIX) getopt | GNU getopt |
|---|---|---|
| 引数の位置 | 最初の非オプションで解析終了 | 全体をスキャンし並べ替え (permutation) |
| optional argument (`::`) | 一部対応 | 対応 (同一argv要素内のみ) |
| ロングオプション | なし (getopt_long は別) | getopt_long で対応 |
| `POSIXLY_CORRECT` | N/A | 設定するとBSD互換モード |
| `optind = 0` リセット | N/A | GNU拡張でリセット可能 |

### 4.4 歴史的変遷タイムライン

| 年代 | 出来事 |
|---|---|
| 1970s | Unix V1-V7: フラグなし → 単一文字フラグ登場 |
| 1974 | dd が IBM JCL 由来の `key=value` 構文で登場 |
| ~1980 | `getopt()` 関数が標準化 (AT&T) |
| 1984 | X Window System: 単一ダッシュ+ロング名の規約を確立 |
| ~1990 | GNU: `+` プレフィックスでロングオプション導入 |
| 1992 | IEEE POSIX shell/utilities 標準。`+` 禁止 → `--` に移行 |
| 1990s | `getopt_long()` の普及。GNU規約がデファクト標準に |
| 2000s | 各言語の高機能パーサ (argparse, clap, cobra) が登場 |

---

## 5. 各パーサの対応比較表

凡例: O = 完全対応, △ = 部分/設定次第, X = 非対応, ? = 未確認

| パターン | C getopt | C getopt_long | Python argparse | Python click | Rust clap | Go flag | Go pflag/cobra | Node commander | Node yargs | Perl Getopt::Long |
|---|---|---|---|---|---|---|---|---|---|---|
| フラグ結合 `-abc` | O | O | O | O | O | X | O (boolのみ) | △ | △ | △ (bundling) |
| 結合+値 `-oArg` | O | O | O | O | O | X | O | O | O | O |
| カウント `-vvv` | X | X | O (count) | O | O | X | O | △ | O | △ |
| ロングオプション `--foo` | X | O | O | O | O | O (=`-foo`) | O | O | O | O |
| ロング値 `--foo=bar` | X | O | O | O | O | O | O | O | O | O |
| ロング値 `--foo bar` | X | O | O | O | O | O | O | O | O | O |
| 否定 `--no-foo` | X | X (手動) | O (BoolOptAct) | O | O | X | △ (issue) | X | O | △ (negatable) |
| ロング省略 `--ign` | X | O | X | X | X | X | X | X | X | △ (auto_abbrev) |
| optional arg | X | △ (`::`) | O (nargs=?) | X | O | X | O | O | O | O |
| optional arg + subcmd | X | X | △ | X | △ (require_equals) | X | △ | △ | △ | X |
| `--` セパレータ | O | O | O | O | O | O | O | O | O | O |
| permutation (位置自由) | X | O (GNU) | O | O | O | X | O | O | O | O (permute) |
| サブコマンド | X | X | O | O | O | X | O | O | O | X |
| 負数値 `-1` | X | X | △ | △ | O (設定) | X | X | △ | △ | X |
| 複数値 append | X | X (手動) | O (append) | O (multiple) | O | X | O | O | O | O |
| value_delimiter | X | X | X | X | O | X | X | X | X | X |
| 単一ダッシュロング `-foo` | X | O (設定) | △ (prefix) | X | X | O (常にこれ) | X | X | X | O (getopt_compat) |

---

## 6. kuu への示唆

### 6.1 対応すべきパターン (優先度高)

| パターン | 理由 |
|---|---|
| フラグ結合 `-abc` | POSIX GL5 準拠。ユーザの基本期待値 |
| 結合+値 `-oArg` / `-o Arg` | POSIX GL6 準拠 |
| ロングオプション `--foo` / `--foo=bar` / `--foo bar` | GNU デファクト標準 |
| `--` セパレータ | POSIX GL10 必須 |
| `-` stdin/stdout | POSIX GL13 |
| カウント `-vvv` | 広く使われるパターン |
| 否定 `--no-foo` | モダンCLI標準 |
| 複数指定 append (`-H val -H val`) | curl等で必須パターン |
| サブコマンド | kuu設計要件 |
| Permutation (位置自由) | GNU準拠。ユーザビリティ向上 |

### 6.2 対応すべきパターン (優先度中)

| パターン | 理由 |
|---|---|
| ロングオプション省略 `--ign` → `--ignore` | 便利だが曖昧性の問題あり。一意性チェックが必要 |
| Optional argument (`--color` / `--color=auto`) | GNU grepの `--color[=WHEN]` パターン。`=` 必須にすれば曖昧性なし |
| value_delimiter (`--exclude=a,b,c`) | 便利だが `=` 内のカンマとの区別が必要 |

### 6.3 対応不要なパターン

| パターン | 理由 |
|---|---|
| レガシー数値 (`tail -10`) | POSIX非推奨。前処理での変換を推奨 |
| dd形式 (`if=file`) | 完全に独自規約。汎用パーサの範疇外 |
| tar old style (ダッシュなし結合) | レガシー互換性のみ。新規CLIでは不要 |
| X11単一ダッシュロング (`-display`) | 歴史的遺物。`--display` で対応 |
| JVM引数 (`-Xmx512m`) | JVM固有。汎用パーサでは扱わない |
| GCC `-O2` / `-Wall` | コンパイラ固有。プレフィックスマッチが必要なら別途検討 |
| `test` / `[` の文法 | シェル組み込み。引数パーサの範疇外 |
| Windows `/` プレフィックス | Unix系CLI限定なら不要 |

### 6.4 設計上の注意点

1. **optional argument の曖昧性**: `--color auto` は `--color` の値が `auto` か、`--color` (値なし) + オペランド `auto` か区別できない。`--color=auto` の `=` 形式を必須にするか、`=` 省略時は同一argv要素内のみ許可 (GNU方式) にすべき。

   **サブコマンドとの衝突**: `--config [FILE]` のようにデフォルト値ありの optional arg がサブコマンドと共存すると、パーサが `--config serve` の `serve` をオプション値かサブコマンドか区別できない。
   - **clap (Rust)**: `num_args=0..=1` ではサブコマンドと値を区別不能。`require_equals=true` にすれば `--config`（値なし=デフォルト）と `--config=path`（値あり）が明確に区別され、`--config serve` の `serve` はサブコマンドとして正しく解釈される。
   - **argparse (Python)**: `nargs='?'` で同様の曖昧性あり。位置引数（サブコマンド）より先にオプションが消費するため、意図せずサブコマンド名がオプション値になる。
   - **一般的回避策**: `=` 必須化（`--config=path`）、または optional arg を避けてフラグ+別オプションに分離（`--use-default-config` + `--config path`）。
   - **kuu**: `implicit_value` で3値パターンが自然に表現できる。ExactNode ベースのフラット走査で `--config` を先に消費するため、サブコマンドとの曖昧性が構造的に発生しない。

     ```
     app run                → get() = None    （設定ファイル不使用）
     app run --config       → get() = Some(implicit_value)（デフォルトパス）
     app run --config path  → get() = Some("path")（指定パス）
     ```

     clap が `require_equals` でワークアラウンドする問題を、kuu は設計レベルで回避している。

2. **負数値の扱い**: `-1` がオプション名か負数値かの判断。`allow_negative_numbers` のようなオプトイン方式が安全。
   - **kuu**: `-` をオプションのプレフィックスとして特別視しないため、`--num -1` で `-1` は `int_opt` の値として自然に消費される。`allow_negative_numbers` のような特別対応が不要。

3. **結合の最後のオプションの値**: `-abc foo` で `c` が値を取る場合、`-abcfoo` (直結) も許可するかは明示的に設計すべき。POSIX的には両方許可。

4. **permutation の罠**: `cmd -a file -b` でオプションとオペランドが混在する場合、`-b` をオプションとして認識するか。GNU方式ではYesだが、サブコマンドとの組み合わせで問題が生じる (`cmd subcmd -a` の `-a` は誰のオプション?)。

5. **`--no-` 否定の自動生成**: `--color` を定義すると自動的に `--no-color` も使えるようにするか。自動生成する場合、`--no-` で始まる本来のオプション名 (`--no-verify`) との衝突を考慮。

6. **ロング省略の衝突**: `--color` と `--count` があるとき `--co` は曖昧。エラーメッセージで候補を提示すべき。

---

## 参考文献

- [POSIX.1-2017 Utility Conventions (12.2)](https://pubs.opengroup.org/onlinepubs/9699919799/basedefs/V1_chap12.html)
- [GNU Coding Standards - Command-Line Interfaces](https://www.gnu.org/prep/standards/html_node/Command_002dLine-Interfaces.html)
- [GNU C Library - Argument Syntax](https://www.gnu.org/software/libc/manual/html_node/Argument-Syntax.html)
- [Why Do Long Options Start with Two Dashes?](https://blog.djmnet.org/2019/08/02/why-do-long-options-start-with/)
- [Conventions for Command Line Options (nullprogram)](https://nullprogram.com/blog/2020/08/01/)
- [Unix command line conventions over time](https://blog.liw.fi/posts/2022/05/07/unix-cli/)
- [Chris's Wiki: Unix Options Conventions](https://utcc.utoronto.ca/~cks/space/blog/unix/UnixOptionsConventions)
- [GNU tar: The Three Option Styles](https://www.gnu.org/software/tar/manual/html_section/Styles.html)
- [getopt(3) Linux man page](https://man7.org/linux/man-pages/man3/getopt.3.html)
- [getopt - Wikipedia](https://en.wikipedia.org/wiki/Getopt)
- [Command-line argument parsing - Wikipedia](https://en.wikipedia.org/wiki/Command-line_argument_parsing)
- [clap (Rust)](https://docs.rs/clap/latest/clap/)
- [pflag (Go)](https://pkg.go.dev/github.com/spf13/pflag)
- [Perl Getopt::Long](https://perldoc.perl.org/Getopt::Long)
- [Python argparse](https://docs.python.org/3/library/argparse.html)
- [Click Options](https://click.palletsprojects.com/en/stable/options/)
- [Commander.js](https://github.com/tj/commander.js)
- [Git CLI Conventions](https://git-scm.com/docs/gitcli)
- [JVM Arguments Prefixes (Baeldung)](https://www.baeldung.com/java-jvm-arguments-prefixes)
