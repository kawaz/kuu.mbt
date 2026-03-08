# kuu Python API 設計書

## 概要

kuu の MoonBit 製 core パースエンジンを WASM FFI 経由で利用し、Python ユーザーに click/typer 並みの DX を提供する高級 API。

## 目標

1. **Python らしさ**: dataclass + type hints + デコレータで宣言的に CLI を定義
2. **型安全**: `Annotated` で kuu オプションのメタデータを型に紐付け
3. **click/typer ユーザーに自然**: 既存の Python CLI ライブラリの慣習を尊重
4. **kuu core の全機能を活用**: exclusive, required, variations, choices, implicit_value, serial, dashdash 等

## 方針

### typer 風 + kuu 独自機能

基本路線は **typer 風の関数シグネチャベース**。typer が click のラッパーとして成功したように、kuu-py は kuu core のラッパーとして同じ体験を提供する。

typer で実現できない kuu 独自機能（exclusive, variations, serial, dashdash 等）は `Annotated` メタデータと専用デコレータで自然に拡張する。

---

## API 設計

### 1. アプリケーション定義

```python
import kuu

app = kuu.App(name="mygit", description="A sample git-like CLI")
```

### 2. コマンド定義（デコレータ + 関数シグネチャ）

```python
@app.command()
def clone(
    url: Annotated[str, kuu.Positional(help="Repository URL")],
    directory: Annotated[str | None, kuu.Positional(help="Target directory")] = None,
    depth: Annotated[int, kuu.Option(help="Shallow clone depth")] = 0,
    branch: Annotated[str, kuu.Option(short="b", help="Branch to checkout")] = "",
    bare: Annotated[bool, kuu.Option(help="Create a bare repository")] = False,
):
    """Clone a repository"""
    ...
```

### 3. 型マッピング

Python の型ヒントから kuu core のコンビネータへの対応:

| Python 型 | kuu core | 意味 |
|---|---|---|
| `bool` (default=False) | `flag()` | フラグ（指定で True） |
| `bool` (default=True) | `flag(default=True)` | 反転フラグ（`--no-xxx` で False） |
| `str` | `string_opt()` | 文字列オプション |
| `int` | `int_opt()` | 整数オプション |
| `str \| None` | `string_opt()` + optional | 未指定で None |
| `int \| None` | `int_opt()` + optional | 未指定で None |
| `list[str]` | `append_string()` | 繰り返し可能な文字列 |
| `list[int]` | `append_int()` | 繰り返し可能な整数 |

#### None 型と required の関係

- `str` (デフォルト値なし) → **required** (必須オプション)
- `str | None` (= None) → optional、未指定時 None
- `str` (= "default") → optional、未指定時 "default"

### 4. Positional 引数

`kuu.Positional()` アノテーションで区別:

```python
def clone(
    url: Annotated[str, kuu.Positional(help="Repository URL")],  # required positional
    directory: Annotated[str | None, kuu.Positional(help="Target dir")] = None,  # optional positional
):
```

### 5. Rest 引数

`*args` 風の可変長位置引数:

```python
def add(
    files: Annotated[list[str], kuu.Rest(help="Files to add")],
    force: Annotated[bool, kuu.Option(short="f")] = False,
):
```

### 6. Count オプション

`kuu.Count()` アノテーションで明示:

```python
def main(
    verbose: Annotated[int, kuu.Count(short="v", help="Increase verbosity")] = 0,
):
```

### 7. サブコマンド

`@app.command()` デコレータでフラットに定義し、ネストは `@app.group()` で表現:

```python
app = kuu.App(name="mygit")

# トップレベルコマンド
@app.command()
def clone(url: Annotated[str, kuu.Positional()], ...):
    """Clone a repository"""
    ...

# ネストしたコマンドグループ
remote = app.group(name="remote", help="Manage remotes")

@remote.command()
def add(
    name: Annotated[str, kuu.Positional()],
    url: Annotated[str, kuu.Positional()],
    fetch: Annotated[bool, kuu.Option(short="f")] = False,
):
    """Add a remote"""
    ...

@remote.command()
def remove(name: Annotated[str, kuu.Positional()]):
    """Remove a remote"""
    ...
```

`group()` は `require_cmd()` を自動設定する。

### 8. Exclusive / Required 制約

デコレータで宣言:

```python
@app.command()
@kuu.exclusive("verbose", "quiet")
def main(
    verbose: Annotated[int, kuu.Count(short="v")] = 0,
    quiet: Annotated[bool, kuu.Option(short="q")] = False,
):
    ...
```

`required` はデフォルト値なしの型（`str`, `int`）で自動推論。明示的に指定する場合:

```python
@app.command()
@kuu.required("message")
def commit(
    message: Annotated[str, kuu.Option(short="m")] = "",
):
    ...
```

### 9. Choices

`Literal` 型または `kuu.Option(choices=...)` で指定:

```python
from typing import Literal

def main(
    # 方法1: Literal 型（推奨）
    color: Annotated[Literal["always", "never", "auto"], kuu.Option()] = "auto",

    # 方法2: 明示的 choices
    format: Annotated[str, kuu.Option(choices=["oneline", "short", "medium"])] = "medium",
):
```

### 10. Implicit Value

`--color` だけで `--color=always` と同等になる:

```python
def main(
    color: Annotated[
        str,
        kuu.Option(
            choices=["always", "never", "auto"],
            implicit_value="always",
        ),
    ] = "auto",
):
```

### 11. Variations

kuu 独自の variation 機能:

```python
def main(
    verbose: Annotated[
        int,
        kuu.Count(
            short="v",
            variation_reset="no",     # --no-verbose でリセット
        ),
    ] = 0,
    verify: Annotated[
        bool,
        kuu.Option(
            variation_false="no",     # --no-verify で False
        ),
    ] = True,
):
```

### 12. Dashdash (`--` セパレータ)

```python
def checkout(
    branch: Annotated[str | None, kuu.Positional()] = None,
    force: Annotated[bool, kuu.Option(short="f")] = False,
    # -- 以降のファイルリスト
    files: Annotated[list[str], kuu.Dashdash(help="Files to restore")] = [],
):
```

### 13. Serial（順序固定の複数 Positional）

serial は複数の positional を固定順序で受け取るパターン。Python では引数順序がそのまま serial 順序になるため、通常は自然に表現できる。

明示的に serial グループを作りたい場合は `kuu.Serial()` を使用:

```python
@remote.command(name="add")
def remote_add(
    # serial グループ: name, url の順で厳密に消費
    name: Annotated[str, kuu.Serial(group="remote-args", help="Remote name")],
    url: Annotated[str, kuu.Serial(group="remote-args", help="Remote URL")],
    fetch: Annotated[bool, kuu.Option(short="f")] = False,
):
    """Add a remote"""
    ...
```

同じ `group` 名の Serial 引数は、kuu core の `serial()` + `never()` にまとめられる。

### 14. Global オプション

`@app.global_options` で定義し、全サブコマンドに伝搬:

```python
app = kuu.App(name="mygit")

@app.global_options
@kuu.exclusive("verbose", "quiet")
def global_opts(
    verbose: Annotated[int, kuu.Count(short="v", help="Increase verbosity")] = 0,
    quiet: Annotated[bool, kuu.Option(short="q", help="Suppress output")] = False,
    color: Annotated[
        str,
        kuu.Option(
            choices=["always", "never", "auto"],
            implicit_value="always",
            help="When to use colors",
        ),
    ] = "auto",
):
    """Global options available to all subcommands"""
    ...
```

コマンド関数内からグローバルオプションにアクセスする方法:

```python
@app.command()
def clone(
    url: Annotated[str, kuu.Positional()],
    ctx: kuu.Context = kuu.CONTEXT,  # 特殊引数: kuu.Context を注入
):
    print(f"verbose={ctx.globals.verbose}")
```

### 15. Post Filter

kuu core の FilterChain に対応:

```python
def commit(
    message: Annotated[
        str,
        kuu.Option(
            short="m",
            post=[kuu.filters.trim, kuu.filters.non_empty],
        ),
    ] = "",
):
```

組み込みフィルタ:
- `kuu.filters.trim` — 前後の空白を除去
- `kuu.filters.non_empty` — 空文字列をエラーに
- `kuu.filters.one_of(choices)` — 選択肢チェック（通常は choices で代替）
- `kuu.filters.in_range(min, max)` — 数値範囲チェック

### 16. Hidden オプション

```python
def main(
    debug: Annotated[
        bool,
        kuu.Option(hidden=True, help="Internal debug flag"),
    ] = False,
):
```

### 17. Aliases

```python
def diff(
    staged: Annotated[
        bool,
        kuu.Option(aliases=["cached"], help="Show staged changes"),
    ] = False,
):
```

---

## Core FFI 接続

### WASM Runtime

wasmtime-py を使用。kuu core を WASM にコンパイルし、以下の FFI 関数を export する:

```
kuu_parser_new() -> i32             # Parser ID
kuu_flag(parser, name, ...) -> i32  # Opt ID
kuu_string_opt(parser, ...) -> i32
kuu_int_opt(parser, ...) -> i32
kuu_count(parser, ...) -> i32
kuu_append_string(parser, ...) -> i32
kuu_append_int(parser, ...) -> i32
kuu_positional(parser, ...) -> i32
kuu_rest(parser, ...) -> i32
kuu_sub(parser, ...) -> i32
kuu_parse(parser, args) -> i32      # ParseResult ID
kuu_get_bool(opt_id) -> i32
kuu_get_string(opt_id) -> ptr
kuu_get_int(opt_id) -> i32
kuu_get_string_array(opt_id) -> ptr
kuu_is_set(opt_id) -> i32
kuu_exclusive(parser, opt_ids)
kuu_required(parser, opt_id)
kuu_require_cmd(parser)
```

### Python 側のラッパー構造

```
pkg/py/
  kuu/
    __init__.py      # 公開 API (App, Option, Positional, etc.)
    _core.py         # WASM FFI ブリッジ
    _inspect.py      # 関数シグネチャ解析 (type hints -> core 呼び出し)
    _types.py        # Annotated メタデータ型定義
    filters.py       # 組み込みフィルタ
```

### シグネチャ解析フロー

1. デコレータが関数の `__annotations__` と `inspect.signature` を解析
2. 各パラメータの型ヒントと `Annotated` メタデータから core API 呼び出しを生成
3. `parse()` 後、結果を各パラメータに対応する Python 値に変換
4. 変換結果を引数として元の関数を呼び出す

```python
# 内部処理イメージ
def _build_parser(func):
    sig = inspect.signature(func)
    hints = get_type_hints(func, include_extras=True)

    parser = core.parser_new()
    opt_map = {}

    for name, param in sig.parameters.items():
        annotation = hints[name]
        meta = extract_kuu_meta(annotation)  # Annotated から kuu.Option 等を取得
        base_type = extract_base_type(annotation)
        default = param.default

        if isinstance(meta, kuu.Positional):
            opt_id = core.positional(parser, name=name, ...)
        elif isinstance(meta, kuu.Rest):
            opt_id = core.rest(parser, name=name, ...)
        elif isinstance(meta, kuu.Count):
            opt_id = core.count(parser, name=name, ...)
        elif base_type is bool:
            opt_id = core.flag(parser, name=name, default=default, ...)
        elif base_type is str:
            opt_id = core.string_opt(parser, name=name, default=default, ...)
        elif base_type is int:
            opt_id = core.int_opt(parser, name=name, default=default, ...)
        elif base_type is list[str]:
            opt_id = core.append_string(parser, name=name, ...)
        elif base_type is list[int]:
            opt_id = core.append_int(parser, name=name, ...)

        opt_map[name] = (opt_id, base_type)

    return parser, opt_map
```

---

## click/typer との差別化

### kuu でしかできないこと

| 機能 | click | typer | kuu-py |
|---|---|---|---|
| Exclusive options | 手動実装 | 手動実装 | `@kuu.exclusive("a", "b")` |
| Variation (--no-xxx, --reset-xxx) | callback で手動 | callback で手動 | `variation_false="no"` |
| Implicit value (--color -> always) | flag_value で部分的 | なし | `implicit_value="always"` |
| Dashdash (-- 以降の引数) | なし | なし | `kuu.Dashdash()` |
| Append dashdash (複数 -- グループ) | なし | なし | `kuu.AppendDashdash()` |
| Serial (順序固定 positional) | なし | なし | `kuu.Serial(group="...")` |
| Choices + implicit 複合 | なし | なし | `choices=[...], implicit_value=...` |
| Count + variation reset | なし | なし | `kuu.Count(variation_reset="no")` |
| Global options 自動伝搬 | Context で手動 | callback で手動 | `@app.global_options` |

### kuu-py の強み

1. **宣言的制約**: exclusive/required がデコレータで宣言可能。ロジックに制約チェックが混入しない
2. **variation 体系**: `--flag` / `--no-flag` / `--reset-flag` / `--unset-flag` を一貫した仕組みで提供
3. **dashdash ネイティブサポート**: `--` 以降の引数を型安全に受け取れる
4. **core エンジンの信頼性**: MoonBit の型システムで検証済みの 631+ テストケースが裏で動く
5. **クロス言語 CLI**: 同じ core を使って TypeScript/Go/Rust/Swift でも同一のパース挙動を保証

---

## 実行フロー

```
1. @app.command() デコレータが関数を登録
2. app.run() 呼び出し
3. sys.argv を取得
4. 登録済みコマンドから Parser ツリーを WASM core で構築
5. core.parse(args) を実行
6. ParseResult から各 Opt の値を取得
7. Python の型に変換して関数を呼び出し
```

---

## 将来の拡張

- **Completion**: `app.completion("zsh")` で zsh 補完スクリプト生成
- **Help カスタマイズ**: `kuu.HelpConfig` でヘルプ表示フォーマットを制御
- **Environment variable**: `kuu.Option(env="MY_VAR")` で環境変数フォールバック
- **Config file**: `kuu.Option(config="key.path")` で設定ファイル連携
- **Testing**: `app.test(["clone", "--depth", "1", "url"])` でテスト用パーサ実行
