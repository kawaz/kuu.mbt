// borrow_id_axis_wbtest.mbt — `default_fn: "borrow:<target>"` の目的語が **参照識別子 (id) 軸**
// で引かれることの pin (docs/issue/2026-08-14-ref-link-resolution-name-axis-to-id-axis.md の残り
// 「borrow: の専用 fixture での pin は未」)。
//
// `default_fn_edges` は `name` で辺を張るが、decode 境界の `settle_name_axes` が `name` 自身を
// 参照識別子へ寄せた結果、実質 id 軸で解決している。実装の副作用ではなく DR-046 §1 /
// DR-136 §6 の要件そのものなので固定する。
//
// 併せて DR-046 / DR-120 §4 の 3 軸分離 (トリガ綴り / 結果キー / id) が同じ定義で観測できる —
// 明示 id は参照と内部同一性の軸に効き、トリガ綴りは name 由来のまま。

///|
/// 保証: 明示 `id` を持つ外側セルを `borrow:<id>` で引ける。トリガ綴りは name 由来
/// (`--socket-ttl`) のままで、id は参照の軸にだけ効く。
test "borrow: の目的語は参照識別子 (id) 軸で引かれる (DR-046 §1 / DR-136 §6)" {
  let src =
    #|{"options": [
    #|  {"name": "socket-ttl", "id": "sock_ttl", "type": "number", "long": true, "default": 60}
    #|],
    #|"commands": [
    #|  {"type": "command", "name": "socket", "options": [
    #|    {"name": "ttl", "type": "number", "long": true, "default_fn": "borrow:sock_ttl"}
    #|  ]}
    #|]}
  let ast = load_definition(src)
  // トリガ綴りは name 軸のまま (`--socket-ttl`) — 明示 id は入口の綴りを変えない。
  let args = ["--socket-ttl", "30", "socket"]
  let po = parse_legacy(ast, args)
  match po {
    @engine.Success(_) => ()
    other => fail("parse should succeed, got " + render_outcome(other))
  }
  match resolve_legacy(ast, po, args) {
    @engine.Success(rb) => {
      // 内部同一性キーは参照識別子軸 (`sock_ttl`) — 宣言名 `socket-ttl` ではない。
      let mut outer : @abi.Value? = None
      let mut inner : @abi.Value? = None
      let mut inner_src : @abi.Source? = None
      for b in rb {
        if is_sentinel(b.key) {
          continue
        }
        if b.key == "sock_ttl" && b.scope.length() == 0 {
          outer = Some(b.value)
        }
        if b.key == "ttl" && b.scope.length() == 1 && b.scope[0] == "socket" {
          inner = Some(b.value)
          inner_src = Some(b.source)
        }
      }
      assert_eq(outer, Some(@abi.Number(30.0)))
      // 子が外側の解決値を得ている = borrow が id 軸で引けている証拠。
      // 引けなければ子セルには binding が立たない (実測: 宣言名の綴りで書くと ttl は現れない)。
      assert_eq(inner, Some(@abi.Number(30.0)))
      assert_eq(inner_src, Some(@abi.Default))
    }
    other => fail("resolve should succeed, got " + render_outcome(other))
  }
}
