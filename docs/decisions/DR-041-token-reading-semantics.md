# DR-041: トークン読みの意味論 — 読みは枝、greedy は面で優先、prefix ガードは持たない

> 由来: parts-arggen 側セッションでの arggen ロード (journal `2026-06-29-arggen-phase0-alignment.md`) を受けた本セッションの議論で確定。findings `2026-06-29-ast-missing-pieces.md` の F-001 (dashdash) / F-002 (equal separator) / F-003 (short_combine) / F-004 (一部) に対応する。installer アーキテクチャ (DR-042) と対で確定した。

## 決定

`--key=value` の分解や連結 short (`-abc`) の展開のような **トークン境界の再解釈**を、評価器の実行時意味論として以下の 5 則で定義する。

用語: greedy 面のエントリがトークンを読む機構を **matcher** と呼ぶ (素の exact 一致が最小形)。うちトークン境界を再解釈して複数の読みを生成するものを**再解釈 matcher** と呼ぶ。再解釈 matcher は installer (DR-042) が parse_definition 時に植え付けるものであり、AtomicAST に専用のノード型・フィールドは追加しない。

### 1. AST 要素ではなく評価器契約である

AtomicAST のスキーマ (exact / or / seq / primitive + multiple) は変更しない。matcher の構成材料は、スコープに配置されたエントリ (installer が回収した long / short 等) と config (DR-014) から導出される。

「AtomicAST スキーマ不変」は「仕様不変」を意味しない。本 DR で増えるのは**評価器契約** (DESIGN.md §15 の領域) である。

### 2. 読みの規則はスコープ従属 (全域前処理パスではない)

matcher が生成する読みの規則は、**現在の文法位置のスコープ**の回収エントリから構成される。argv 全体を一括で正規化する前処理パスは存在しない。

`prog -a -- -b` と `prog -- -a -b` で `-a` の読み方が変わる、つまり規則の適用可否は経路上の位置 (どこまで消費したか) に依存するため、全域パスでは意味論が成立しない。

### 3. 候補読みは枝 (多重 Accept)

matcher は 1 トークンに対して読みを**枝として全列挙**し、絞り込まない (素の exact は読み 1 つの縮退形、再解釈 matcher は複数の読みを生成しうる)。DR-038 の「入力を全消費する完全経路がちょうど1本」は、**読みの選択を含む全探索空間**に適用される。

DR-038 の `-n1.0f` 例 (値付着 `n="1.0f"` と分割 `n="1.0"` + `-f` の 2 経路 → ambiguous) は、この複数読みがそのまま枝になる帰結として導出される。ボトムアップ実装の「値トライアル長い方先勝ち commit」は本契約に違反するため置換対象 (DR-038 / DR-039 と同じ判定)。

matcher 間に優先順位はない (全 matcher の全読みが対等な枝)。優先が働くのは次項の greedy 面 vs positional 面の間だけ。

### 4. 背骨と先食い: greedy は宣言スコープの背骨でのみ発火し、素通し消費に優先する

スコープの positional 進行の消費点列を**背骨 (spine)** と呼ぶ。greedy マークは「その構造位置に縛られず、**宣言スコープの背骨上の任意の消費点**で発火できる」という出現位置の自由を与える。出現回数は repeat の軸であり直交する (通常のオプションは greedy + repeat の両方を持つ。repeat のみ = 先頭固定ブロック型、greedy のみ = どこでも書けるが 1 回)。

- **背骨の範囲**: command 部分木は新しい背骨を宣言し、祖先の greedy はそこに届かない (スコープ越えは DR-042 の global installer による構造コピーで表現)。発火した greedy の内部消費 (値スロット、dd の継続) には背骨がなく、何も発火しない。それ以外の構造 (ref 再帰の unfold 等) は現在の背骨に留まる。
- **先食い**: 背骨上の消費点で、そこに到達可能な greedy エントリが読めるトークンは、素通し消費 (positional が raw で食う読み) の枝を生成しない。素通しはトリガ不一致 (読みゼロ) の時のみ。dd マーカー (`--`) も greedy 面の住人なので、寛容な string positional が `--` を値として食う枝はこの規則が抑止する (positional 面のマーカーとして置くと `prog -a -- -b` が常に ambiguous になることを垂直スライス PoC で実測済み)。
- **同名トリガの解決 (shadowing)**: 複数スコープ由来の同名トリガが同じ消費点で衝突する場合 (global コピー等) は最小スコープの宣言が食う — lexical 解決 (DR-032/033) のパース時適用。同一スコープ内の同名重複は従来どおり静的 warn + 実行時 ambiguous (DR-021/038)。
- **背骨は多孔質、greedy 内部は一体** — どちらも独立の規則ではなく背骨規則の系: `cp a --verbose b` も repeat 反復間の `cp src... --verbose dst` も背骨上だから割り込め、`--color -v` が `color="-v"` になる (getopt 同型) のは値スロットに背骨がないから。トリガトークンが引数の束縛を宣言する、というのが greedy の意味論。
- `prog -v src` (`-v` 定義済み、src は string positional) → 背骨上の `-v` は greedy 発火のみで `src="-v"` の読みは立たない。リテラル `-v` を positional に渡すには dd (`--`) を使う (greedy の値スロットへは raw 消費されるため escape 不要)。
- 読みが生成した断片は再度読解しない (再帰読解なし)。cluster の走査は short の読み生成内で完結する。

### 5. prefix ガードは持たない (規則従属)

値プリミティブは「option 風に見えるトークン」を形の理由では拒否しない。未定義の `-x` はどの matcher にも読まれず素通しで positional に落ちる:

- その位置の positional が string → `"-x"` を値として消費して成功
- その位置が number 等 → value_parser が失敗。これは DR-037 の **Error** (この枝のつもりだが値が不正) として保持し、完全経路 0 本のときに表示する (例: `"-x" is not a number`)

「`-` 始まりは positional が拒否」という prefix 従属ガードは採用しない。ガードを持つと評価器に mode 状態が必要になり dd が純糖衣で閉じなくなるうえ、暗黙ルール最小化 (§0.1) に反する。古典 CLI 互換の unknown-option エラーが欲しい場合は installer のパラメータや pre_filter による方言で opt-in する。

## 各機構への適用

### dashdash (`--`) — 素の exact を matcher とする greedy トリガ兼消費者

dd は UsefulAST の糖衣であり (DR-014 の「config に含めず AST に直接書く」判断を踏襲)、dd installer (DR-042) が **greedy 面の exact 衛星 (トリガ兼消費者)** として展開する: `--` の完全一致で発火し、マーカー 1 トークンを消費して値は生まず、**以降の positional 継続を自分の内部消費として引き継ぐ**。

dd のための特別規則はゼロで、全挙動が §4 の既存 2 規則から導出される:

- `--` 自体が寛容な positional に値として食われない ← 先食い (greedy が読めるトークンだから)
- `--` 以降で option が抑制される (sever) ← greedy の内部消費は一体 (発火した dd の内部に greedy は割り込まない → 継続は全て raw 消費)
- 2 個目の `--` は内部消費の中なので raw で positional に落ちる (古典と同じ)

AtomicAST に専用ノード型・状態フィールドは不要。「継続を内部として引き継ぐ」の実装表現 (継続参照の構造 / 経路局所の sever フラグ + 純マーカー) は観測挙動が同一であれば自由 (垂直スライス PoC は sever フラグ形で同一挙動を確認済み)。**dd の matcher は素の exact 一致であり、トークン境界の再解釈をしない** (再解釈 matcher が要るのは long の eq-split / short の cluster だけ)。

dd 糖衣を書いていない定義では `--` に特別な意味はない (明示性重視)。

dd 糖衣を書いていない定義では `--` に特別な意味はない (明示性重視)。

### equal separator (`--key=value`) — long installer の matcher

スコープで回収された long エントリ + config (`allow_equal_separator` / `long_prefix`) から規則を構成。トークン `--k=v` に対して読み `[--k の発火, 値断片 "v"]` を生成する。`k` が未定義なら不一致 → 素通しで positional へ。

### short combine (`-abc`) — short installer の matcher

スコープで回収された short エントリ + config (`short_combine` / `short_prefix`) から規則を構成。cluster 分解・値付着の全解釈を読みとして列挙する。曖昧になる定義 (`-cv` 問題) は正しく ambiguous になる。他 CLI 互換 (「short の値付着は末尾のみ」等) は installer のパラメータとして狭める方言で吸収し、コアの責務にしない。

## 受け入れる帰結

1. **typo が positional に飲まれうる**: 寛容な string positional がある定義では `--verbse` が値として成功しうる。緩和は (a) 静的 warn (DR-021: 「option 群 + 上限なし string positional」構造の警告)、(b) 近接候補提示 (findings F-016)、(c) 方言ガードの opt-in。コアの既定は定義を信頼する。
2. **定義済み option と同形の文字列を scope の positional に渡すには `--` が要る**: 古典 CLI と同じ制約であり、escape 経路は常に存在する。greedy の値スロットは raw 消費なのでこの制約を受けない。
3. **ambiguous は増える方向**: 多重 Accept は greedy commit より多くの曖昧を検出する。これは DR-038 が既に受け入れた帰結の再確認。

## 採用しなかった案

### 専用ノード型 (`end_of_options: true` 等) の導入

findings F-001 の選択肢 (1)。AtomicAST に評価器指示用のフィールドが増え、DR-039 の「AtomicAST = 既存エンジンのノードグラフのシリアライズ形」テーゼから外れる。再スコープ化で構造的に表現できるため不要。

### 全域前処理パス (argv 一括正規化 → path-search)

「第0フェーズ」という語が連想させる構成だが、規則適用可否が経路依存 (`--` の前後) なので成立しない。層の分離は責務の分離であって、時間的な 2 パスではない。

### prefix 従属ガード

古典互換だが評価器状態 (options_allowed bit) が必要になり、dd の純糖衣性が崩れる。互換は方言へ。

### 先食いトリガ集合の特例拡張 (greedy ∪ dd マーカー)

dd を positional 面のマーカーとして置き、先食いの述語にだけ「宣言済み dd マーカー」を特例で加える案。dd を greedy 面の住人 (トリガ兼消費者) と捉えれば §4 の既存 2 規則 (先食い + 内部一体) から全挙動が導出されるため、特例は不要。

## 射程外

matcher を植え付ける installer のアーキテクチャ (所有語彙・合成の不変則・registry 区分) は本 DR では扱わない。DR-042 を参照。

## 関連

- DR-042 (installer アーキテクチャ — matcher の供給者、対で確定)
- DR-014 (config 集約; dashdash を config に含めず AST 直接とした先行判断。long_prefix / short_prefix / allow_equal_separator / short_combine は matcher の構成パラメータ)
- DR-037 (Reject / Error 区別; 素通し消費先の value_parser 失敗は Error)
- DR-038 (完全経路の一意性; 本 DR の読みは同契約下の枝)
- DR-039 (lagg / sagg = `install_eq_split` / `install_short_combine` の対応; 先勝ち commit の置換)
- DR-018 (commands の or 糖衣; command 名の照合は素の exact であり matcher の関与なし)
- journal `2026-06-29-arggen-phase0-alignment.md` (ロード段階の経緯)
- findings `2026-06-29-ast-missing-pieces.md` F-001 / F-002 / F-003 / F-004 (一部)
- 垂直スライス PoC (slice 枝 `poc/`、journal `2026-07-02-slice-poc.md`) — §4 トリガ語彙拡張と sever 実装形の実測根拠
