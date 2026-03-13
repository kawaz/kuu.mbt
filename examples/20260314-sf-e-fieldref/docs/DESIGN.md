# struct-first CLI パーサ PoC: E. FieldRef + Binder 方式

## 概要

FieldRef（Lens パターン）+ クロージャベースの型消去で、struct-first な CLI パーサを実現する PoC。

ユーザーは struct を先に定義し、各フィールドへの FieldRef と parser を宣言するだけで CLI パーサが得られる。

## アーキテクチャ

```
FieldRef[S, A]  ──→  make_binder[S, T]  ──→  Binder[S]  ──→  OptDef[S]  ──→  parse_args
   (Lens)              (型消去)           (クロージャ)    (名前→バインド)    (走査)
```

### 型の流れ

1. `FieldRef[S, A]`: struct `S` のフィールド `A` への get/set 参照
2. `make_binder(field, parser)`: `A` を知る関数内でクロージャにキャプチャ → `Binder[S]` として返す（`A` は消える）
3. `OptDef[S]`: CLI オプション名 + `Binder[S]` の対
4. `parse_args(args, initial, opts)`: args を走査し、マッチした OptDef の binder.apply で state を更新

### 型消去のメカニズム

```moonbit
// T はこの関数のスコープ内でのみ存在
pub fn[S, T] make_binder(field : FieldRef[S, T], parse : (String) -> T?) -> Binder[S] {
  {
    name: field.name,
    apply: fn(s, raw) {      // ← T はクロージャの中に閉じ込められる
      match parse(raw) {
        Some(v) => ((field.set)(s, v), Accept)
        None => (s, Reject("parse failed: " + raw))
      }
    },
  }
}
```

## 主要な型

| 型 | 役割 |
|---|---|
| `FieldRef[S, A]` | struct S のフィールド A への型安全参照（Lens パターン） |
| `Binder[S]` | 型消去されたフィールドバインド（apply クロージャで T を隠蔽） |
| `OptDef[S]` | CLI オプション名と Binder の対 |
| `ReduceResult` | パース結果（Accept / Reject） |
| `IntoOpt` | struct → OptDef 配列を導出する trait |

## 設計判断

### DR-001: trait に型パラメータ不可

当初 `trait AnyBind[S]` + `&AnyBind[S]` trait object を使う設計だったが、MoonBit の trait は型パラメータを受け付けない。クロージャベースの型消去に変更。

これは kuu 本体の ExactNode パターンと同じアプローチ。

### immutable struct update

`{ ..s, field: v }` 構文で struct の部分更新を行う。元の struct は不変のまま新しい struct を返す。

## テスト状況

- 全18件パス
- FieldRef get/set、Binder 型消去、parse_args の正常/異常系、IntoOpt をカバー

## 成功基準の達成状況

| 基準 | 状況 |
|---|---|
| MoonBit でコンパイルが通る | OK |
| 型消去が正しく動く | OK（String, Int, Bool の Binder が同じ配列に格納） |
| FieldRef による get/set が正しく動作 | OK（struct update syntax 動作確認） |
| IntoOpt trait の手動実装パターンが確立 | OK |

## 今後の課題

- フラグ（値なしオプション）対応
- サブコマンド対応
- ヘルプ生成
- kuu との統合検討
- `derive(IntoOpt)` の将来的な自動化
