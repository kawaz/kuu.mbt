# DR-022: never + serial コンビネータ設計

## 背景

Step 11（拡張コンビネータ）の一環として、positional のグループ化 (serial) と固定長保証 (never) を実装。

## never

positional センチネル。serial の末尾に置いて、固定長 positionals 消費後の余分な引数を防止。

```moonbit
pub fn Parser::never(self : Parser) -> Unit
```

- 引数がある場合: `Error("unexpected argument: {arg}")` を返す
- 引数がない場合: `Reject` を返す
- Opt を返さない（値を持たないため）

## serial

positional のグループ化。setup クロージャで子 positional を定義し、compound handler として親に登録。

```moonbit
pub fn Parser::serial(self : Parser, setup~ : (Parser) -> Unit) -> Unit
```

### 実装の要点

1. **軽量 sub-parser**: Parser::new() は --help ノードを自動登録するため使わない。struct を直接構築
2. **next_id / parsed 共有**: sub-parser は親と ID 空間・パース状態を共有。serial 内の Opt[T] は親の parse 後に .get() でアクセス可能
3. **compound handler**: sub の全 positional を一括消費する greedy handler を親に1つ登録
4. **is_rest 判定**: sub の末尾 positional が rest なら serial 全体を is_rest=true で登録

### dashdash との連携

install_separator_node 内で positional が順次消費される際、serial の compound handler が1単位として機能する。`-- file1 dest1 -- file2 dest2` のようなグループ単位消費が可能。

## 実装状況

全て実装済み。612 テスト（never 3件、serial 5件追加）。
