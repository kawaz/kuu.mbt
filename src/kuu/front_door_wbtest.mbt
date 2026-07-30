// front_door_wbtest.mbt — MDR-005 §正面玄関 3 契約の意味論 pin (issue 2026-07-15
// front-door-parse-missing-postprocessing の受け入れ条件)。conformance runner の乗り換えだけでは
// front_door.parse / front_door.resolve の**呼び出し側から見える契約**を直接固定できない —
// kuu-cli PoC dogfooding が発見した「front_door.parse が薄い @engine.parse_tree wrapper のまま spec 非
// 準拠 outcome を返す」実バグの根治として、玄関 API のシグネチャに沿った 3 本の pin を残す:
//
// 1. export-key 衝突 (DR-120): 2 要素が同じ露出キーへ解決する定義は front_door.parse_definition
//    が definition-error (kind=export-key-collision) として弾く — parse まで到達しない
// 2. inherit resolve (DR-031 #4 / DR-047 §4): 祖先 scope で書かれた値が子 scope の inherit 席へ
//    流下する。front_door.resolve が返す binds に子 scope 側の解決済み値 (source=@abi.Inherit)
//    が現れる
// 3. deprecated warnings (DR-058 §2): deprecated:true の alias 入口を発火した @engine.Success outcome
//    から `@engine.warnings_of` が `{element, kind}` の構造化 warning を返す。sentinel
//    `@depr:...` は effects (非 sentinel binds) に混じらない (`is_sentinel` で除外可能)
//
// 期待値の根拠は kawaz/kuu の fixtures (`export-key/collision.json` /
// `export-key/collision-identity.json` /
// `value-sources/inherit-ladder.json` / `alias-parse/deprecated.json`) の該当 case と一致し、
// conformance runner が実際にその期待を満たしていることは `[json-conformance] mismatches=0` が
// 別途保証している — 本 wbtest は玄関 API の契約側からその 3 面を独立に固定する層。

///|
/// 保証 (MDR-005 §1 / DR-120 §1/§3/§5): 2 つの値セルが同じ露出キーへ解決する定義は、玄関
/// `parse_definition` が definition-error (kind=export-key-collision) として弾く — parse 相へ
/// 到達しない。mapped 同士 (a/b とも `export_key: "x"`) と identity × mapped
/// (a は未指定、b が `export_key: "a"`) の両方を確認する — §3 の「解決経路の種類を区別しない」を
/// 玄関 API の側から独立に固定する層 (fixture 側は export-key/collision.json /
/// collision-identity.json)。
test "front_door.parse_definition: 露出キー衝突は definition-error (DR-120 §1/§3)" {
  fn collision_kinds(src : String) -> Array[String] raise {
    match parse_definition(@json.parse(src)) {
      Ok(_) => []
      Err(Malformed(reason)) => ["malformed:" + reason]
      Err(Rejected(errors)) => {
        let items : Array[String] = []
        for error in errors {
          items.push("\{error.element}/\{test_render_def_kind(error.kind)}")
        }
        test_sort_items(items)
        items
      }
    }
  }

  // mapped 同士 (fixtures/export-key/collision.json と同じ定義)。
  assert_eq(
    collision_kinds(
      (
        #|{"options": [
        #|  {"name": "a", "type": "flag", "long": true, "export_key": "x"},
        #|  {"name": "b", "type": "flag", "long": true, "export_key": "x"}
        #|]}
      ),
    ),
    ["a/export-key-collision", "b/export-key-collision"],
  )
  // identity × mapped (fixtures/export-key/collision-identity.json と同じ定義)。宣言順を
  // 入れ替えても同じ 2 件が立つ (検査は宣言順に依存しない)。
  let expected = ["a/export-key-collision", "b/export-key-collision"]
  assert_eq(
    collision_kinds(
      (
        #|{"options": [
        #|  {"name": "a", "type": "string", "long": true},
        #|  {"name": "b", "type": "string", "long": true, "export_key": "a"}
        #|]}
      ),
    ),
    expected,
  )
  assert_eq(
    collision_kinds(
      (
        #|{"options": [
        #|  {"name": "b", "type": "string", "long": true, "export_key": "a"},
        #|  {"name": "a", "type": "string", "long": true}
        #|]}
      ),
    ),
    expected,
  )
}

///|
/// 保証 (MDR-005 §1 / DR-031 #4 / DR-047 §4): front_door.resolve は値源ラダー
/// (env/config/inherit/default) を子 scope まで再帰的に充填する。inherit:true の子 scope entity は、
/// 祖先 scope で解決済みの同名値を **`@abi.Inherit` source** の binding として得る (`--ttl 30 sub`
/// で `sub.ttl = 30`, source=inherit)。ここでは玄関 API のみを叩き、結果 binds に:
///   - root path=[] に ttl 値 30 with source=@abi.Cli (`--ttl` 発火)
///   - 子 path=["sub"] に ttl 値 30 with source=@abi.Inherit (親から流下した inherit 席)
/// の 2 面が現れることを固定する。front_door.parse (単独) では resolve 相未実行なので子 scope の
/// ttl は binds に現れず、玄関 `resolve` が明示的に必要になる = 相区分の 2 段構成 (MDR-005 §1)
/// が意味を持つ最小の証拠でもある。
test "front_door.resolve: 祖先の解決値が子 scope の inherit 席へ流下 (DR-031 #4 / DR-047 §4, MDR-005 §1)" {
  let src =
    #|{"options": [
    #|  {"name": "ttl", "type": "number", "long": true, "default": 60}
    #|],
    #|"commands": [
    #|  {"type": "command", "name": "sub", "options": [
    #|    {"name": "ttl", "type": "number", "long": true, "inherit": true}
    #|  ]}
    #|]}
  let j = @json.parse(src)
  let ast = match parse_definition(j) {
    Ok(a) => a
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  let args = ["--ttl", "30", "sub"]
  let po = parse_legacy(ast, args)
  match po {
    @engine.Success(_) => ()
    other =>
      fail("front_door.parse should succeed, got " + render_outcome(other))
  }
  // resolve なしの @engine.Success binds には子 scope 側の ttl (inherit 経由の値) は入らない —
  // 「玄関 `resolve` を明示的に呼ばないと DR-047 §4 の最終状態は得られない」ことの反証面。
  match po {
    @engine.Success(pre) => {
      let mut had_sub_ttl = false
      for b in pre {
        if b.scope.length() == 1 &&
          b.scope[0] == "sub" &&
          b.key == "ttl" &&
          !is_sentinel(b.key) {
          had_sub_ttl = true
        }
      }
      assert_false(had_sub_ttl)
    }
    _ => ()
  }
  let ro = resolve_legacy(ast, po, args)
  match ro {
    @engine.Success(rb) => {
      // root path=[] の ttl (cli 発火)。
      let mut root_ttl : @abi.Value? = None
      let mut root_src : @abi.Source? = None
      // 子 path=["sub"] の ttl (親から流下した inherit 値)。
      let mut sub_ttl : @abi.Value? = None
      let mut sub_src : @abi.Source? = None
      for b in rb {
        if is_sentinel(b.key) {
          continue
        }
        if b.key == "ttl" {
          if b.scope.length() == 0 {
            root_ttl = Some(b.value)
            root_src = Some(b.source)
          } else if b.scope.length() == 1 && b.scope[0] == "sub" {
            sub_ttl = Some(b.value)
            sub_src = Some(b.source)
          }
        }
      }
      assert_eq(root_ttl, Some(@abi.Number(30.0)))
      assert_eq(root_src, Some(@abi.Cli))
      assert_eq(sub_ttl, Some(@abi.Number(30.0)))
      assert_eq(sub_src, Some(@abi.Inherit))
    }
    other =>
      fail("front_door.resolve should succeed, got " + render_outcome(other))
  }
}

///|
/// 保証 (MDR-005 §1 / DR-058 §2): deprecated:true が付いた alias 入口の発火は、値の束縛 (canonical
/// セル `port` = 80) と並行して、@engine.Success outcome から `@engine.warnings_of` が
/// `{element: "port", kind: "deprecated"}` を返す。同時に、`@depr:port` sentinel binding は
/// `is_sentinel` で除外可能 = kuu-cli 相当の呼び出し側が effects (非 sentinel binds のリスト) を
/// 組み立てるときに漏れない (kuu-cli PoC codex レビュー M-1 = warnings の構造化 + sentinel を
/// effects に漏らさないためのプロダクション pub 面を要件化)。
test "front_door.parse + @engine.warnings_of: deprecated alias 発火は構造化 warning + effects から @depr sentinel 除外 (DR-058 §2, MDR-005 §1)" {
  let src =
    #|{"options": [
    #|  {"name": "port", "type": "number", "short": "p"},
    #|  {"alias": "port", "short": "o", "deprecated": true}
    #|]}
  let j = @json.parse(src)
  let ast = match parse_definition(j) {
    Ok(a) => a
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  let o = parse_legacy(ast, ["-o", "80"])
  match o {
    @engine.Success(binds) => {
      // port の値は 80、source=@abi.Cli (canonical セルへ普通に束縛される、DR-058 は受理不変)。
      let mut port_val : @abi.Value? = None
      for b in binds {
        if is_sentinel(b.key) {
          continue
        }
        if b.scope.length() == 0 && b.key == "port" {
          port_val = Some(b.value)
        }
      }
      assert_eq(port_val, Some(@abi.Number(80.0)))
      // 構造化 warnings が `{element:"port", kind:"deprecated"}` の 1 件を返す。
      let ws = @engine.warnings_of(o)
      assert_eq(ws, [{ element: "port", kind: @abi.Deprecated }])
      // sentinel `@depr:port` は binds に含まれる (@engine.warnings_of/@engine.warnings_of の素材) が、
      // `is_sentinel` で除外可能 = 呼び出し側が effects を組み立てるときに漏れない。
      let mut had_depr_sentinel = false
      let mut non_sentinel_count = 0
      for b in binds {
        if b.key == "@depr:port" {
          had_depr_sentinel = true
          assert_true(is_sentinel(b.key))
        }
        if !is_sentinel(b.key) {
          non_sentinel_count = non_sentinel_count + 1
        }
      }
      assert_true(had_depr_sentinel)
      // 非 sentinel binds は少なくとも port 束縛の 1 件 (fold/scope の内部 binding が他に混ざる
      // 可能性は残すため下限のみを assert する — sentinel の除外自体が意図した契約なので、
      // 「@depr sentinel が非 sentinel カウントに含まれない」ことだけ確定させれば足りる)。
      assert_true(non_sentinel_count >= 1)
    }
    other =>
      fail("front_door.parse should succeed, got " + render_outcome(other))
  }
}

///|
/// 保証 (MDR-006 §7-3): `output` の effects 射影は利用者が値セルの発火だけを観測できる形を返し、
/// lowering/eval 内部の sentinel (`@depr:` を含む) と、値空間を持たない none/dd、config provider を
/// 選ぶ config_file cell を一律に除外する。各内部表現を呼び出し側が `is_sentinel` や Scope/Node 走査で
/// 再判定しないことが玄関契約であり、通常の値 effect は op/operand/source を失わず残る。
test "front_door.output: effects は sentinel・config_file・none・dd を吸収し通常値だけを返す (MDR-006 §7-3)" {
  fn view_of(src : String, args : Array[String]) -> OutputView raise {
    let ast = match parse_definition(@json.parse(src)) {
      Ok(a) => a
      Err(_) => {
        fail("parse_definition failed")
        panic()
      }
    }
    match parse_legacy(ast, args) {
      @engine.Success(binds) => output_legacy(ast, effects=binds)
      other => {
        fail("front_door.parse should succeed, got " + render_outcome(other))
        panic()
      }
    }
  }

  // deprecated alias は canonical value effect だけを残し、warning 素材の @depr sentinel を隠す。
  let normal = view_of(
    (
      #|{"options": [
      #|  {"name": "port", "type": "number", "short": "p"},
      #|  {"alias": "port", "short": "o", "deprecated": true}
      #|]}
    ),
    ["-o", "80"],
  )
  assert_eq(normal.effects.length(), 1)
  assert_eq(normal.effects[0].entity, "port")
  assert_eq(normal.effects[0].op, @abi.Set)
  assert_eq(normal.effects[0].operand, Some(@abi.Number(80.0)))
  assert_eq(normal.effects[0].source, @abi.Cli)

  // config_file は config provider 選択用の配線セルであり、発火しても利用者 effects には出ない。
  let config_file = view_of(
    (
      #|{"options": [{"name": "config", "type": "config_file", "long": true}]}
    ),
    ["--config", "/app.toml"],
  )
  assert_eq(config_file.effects, [])

  // none は値空間を持たない発火観測であり、placeholder Binding を effect として発明しない。
  let none = view_of(
    (
      #|{"options": [{"name": "sep", "type": "none", "long": true}]}
    ),
    ["--sep"],
  )
  assert_eq(none.effects, [])

  // dd も none と同じ値なし観測だが Entity を持たないため、Node 走査は玄関内部だけで吸収する。
  let dd = view_of(
    (
      #|{"options": [{"name": "--", "type": "dd"}]}
    ),
    ["--"],
  )
  assert_eq(dd.effects, [])
}

///|
/// 保証 (issue 2026-07-16-result-projection-production-promotion、DR-109 §3「sources は resolve
/// 済み出力に常に含める」/ §5 UX-Q5=a、MDR-005「射程外」節の解消): `output` が
/// `resolve_legacy()` の @engine.Success payload だけから DR-052 result-key 軸適用済みの `result`
/// オブジェクトと DR-031 値源タグの `sources` を組み立てられる。単一 scope (command 木なし) では
/// export_key rename (`port` → `p`) と、未発火 flag の preset default (`verbose` = false、
/// LOWERING §A.5) の両方が result/sources 双方に反映される — runner 側の conformance 期待
/// (`{p=8080,verbose=false}` / `p=cli,verbose=default`) と同型 (mismatches=0 は別途
/// conformance runner 側が保証)。
test "front_door.output: 単一 scope で export_key rename + flag preset default (DR-052 §1 / LOWERING §A.5, MDR-005 射程外解消)" {
  let src =
    #|{"options": [
    #|  {"name": "port", "type": "number", "long": true, "export_key": "p"},
    #|  {"name": "verbose", "type": "flag", "long": true}
    #|]}
  let j = @json.parse(src)
  let ast = match parse_definition(j) {
    Ok(a) => a
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  let args = ["--port", "8080"]
  let po = parse_legacy(ast, args)
  let ro = resolve_legacy(ast, po, args)
  let rb = match ro {
    @engine.Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects=rb)
  let rval = view.result
  match rval {
    @abi.Object(kvs) => {
      let mut p_val : @abi.ResultValue? = None
      let mut verbose_val : @abi.ResultValue? = None
      for kv in kvs {
        if kv.0 == "p" {
          p_val = Some(kv.1)
        }
        if kv.0 == "verbose" {
          verbose_val = Some(kv.1)
        }
      }
      assert_eq(p_val, Some(@abi.Scalar(@abi.Number(8080.0))))
      assert_eq(verbose_val, Some(@abi.Scalar(@abi.Bool(false))))
    }
    _ => fail("output.result should be @abi.Object at root scope")
  }
  assert_eq(render_rval_sorted(view.sources), "{p=cli,verbose=default}")
}

///|
/// 保証 (issue 2026-07-16-result-projection-production-promotion、DR-109 §3): command 木を持つ
/// scope でも `output` は同じ OutputView の `sources` として木全体の値源タグを返す — 呼び出し側は
/// command 木の有無を一切意識しない (resolve.mbt `result_sources` のコメント参照)。子 scope "sub" で発火した ttl の値源タグが
/// `path: ["sub"], key: "ttl", source: @abi.Cli` として現れることを固定する。
test "front_door.output: command 木でも子 scope の値源を OutputView.sources に返す (DR-109 §3, MDR-005 射程外解消)" {
  let src =
    #|{"commands": [
    #|  {"type": "command", "name": "sub", "options": [
    #|    {"name": "ttl", "type": "number", "long": true, "default": 60}
    #|  ]}
    #|]}
  let j = @json.parse(src)
  let ast = match parse_definition(j) {
    Ok(a) => a
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  let args = ["sub", "--ttl", "30"]
  let po = parse_legacy(ast, args)
  let ro = resolve_legacy(ast, po, args)
  let rb = match ro {
    @engine.Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  assert_eq(
    render_rval_sorted(output_legacy(ast, effects=rb).sources),
    "{sub={ttl=cli}}",
  )
}

///|
/// 保証 (統括裁定「@abi.ConfigVal/TtyObs の入力構築 API」(b)、DR-050 §2/§4): 外部利用者が `@abi.ConfigVal`
/// の variant (`@abi.Object`/`@abi.Array` 含む) を直接構築できない (`pub` でフィールド/variant 非公開) 制約下で、
/// `config_from_json` が JSON から組んだ `@abi.ConfigVal` を `parse_legacy()`/`resolve_legacy()` の `config?` provider
/// 経由で実際に config 席へ流し込めることを e2e で固定する。`config_file` 型要素 + `config_key`
/// を持つ `port` の値が config 由来 (`8080`, source=config) で result/sources 双方に現れ、
/// `config_file` 要素自身はインフラなので結果に現れない (`piece-filters/config-source.json` の
/// 輪郭と同型)。
test "front_door.config_from_json: JSON から組んだ @abi.ConfigVal が config 席経由で result/sources に反映される (DR-050 §2/§4, @abi.ConfigVal/TtyObs 入力構築 API)" {
  let src =
    #|{"options": [
    #|  {"name": "config", "type": "config_file", "long": true, "default": "/app.toml"},
    #|  {"name": "port", "type": "number", "long": true, "config_key": ["port"]}
    #|]}
  let j = @json.parse(src)
  let ast = match parse_definition(j) {
    Ok(a) => a
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  // 利用者は自前で @abi.Object を組めない — config_from_json に生 JSON を渡すだけで良い。
  let cfg_json = @json.parse(
    (
      #|{"port": 8080}
    ),
  )
  let cfg = config_from_json(cfg_json)
  let config_provider : (String) -> @abi.ConfigVal? = fn(_p) { Some(cfg) }
  let args : Array[String] = []
  let po = parse_legacy(ast, args, config=config_provider)
  let ro = resolve_legacy(ast, po, args, config=config_provider)
  let rb = match ro {
    @engine.Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let rval = output_legacy(ast, effects=rb).result
  match rval {
    @abi.Object(kvs) => {
      let mut port_val : @abi.ResultValue? = None
      let mut has_config_key = false
      for kv in kvs {
        if kv.0 == "port" {
          port_val = Some(kv.1)
        }
        if kv.0 == "config" {
          has_config_key = true
        }
      }
      assert_eq(port_val, Some(@abi.Scalar(@abi.Number(8080.0))))
      // config_file 要素自身はインフラで結果非掲載 (config-source.json の why 参照)。
      assert_false(has_config_key)
    }
    _ => fail("output.result should be @abi.Object")
  }
  assert_eq(
    render_rval_sorted(output_legacy(ast, effects=rb).sources),
    "{port=config}",
  )
}

///|
/// 保証 (統括裁定「@abi.ConfigVal/TtyObs の入力構築 API」(b)、DR-099 §4): 外部利用者が `TtyObs` を
/// (フィールド非公開のため) 直接構築できない制約下で、`tty_obs(terminal, cygwin)` が組んだ値を
/// `parse_legacy()`/`resolve_legacy()` の `tty?` 引数経由で `builtin/tty` preset 型要素の default 席解決規則
/// (`fold(観測) ?? 宣言 default ?? absent`、`tty-ladder.json` と同型) に実際に流し込めることを
/// e2e で固定する。`{terminal: true, cygwin: false}` の観測は宣言 default (`false`) と異なる値
/// (`true`) を fold するので、observation が宣言 default に優先することも同時に確認できる。
test "front_door.tty_obs: 構築した TtyObs が tty 席経由で builtin/tty の default 解決規則に反映される (DR-099 §4, @abi.ConfigVal/TtyObs 入力構築 API)" {
  let src =
    #|{"definitions": {"types": {
    #|  "stdout_tty": {"name": "builtin/tty", "config": {"tty_stream": "stdout"}}
    #|}},
    #|"options": [
    #|  {"name": "use_color", "type": "stdout_tty", "long": true, "default": false}
    #|]}
  let j = @json.parse(src)
  let ast = match parse_definition(j) {
    Ok(a) => a
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  // 利用者は自前で { terminal: .., cygwin: .. } を組めない (フィールド非公開) — tty_obs へ渡すだけ。
  let tty_map : Map[String, TtyObs] = { "stdout": tty_obs(true, false) }
  let args : Array[String] = []
  let po = parse_legacy(ast, args, tty=fn(key) { tty_map.get(key) })
  let ro = resolve_legacy(ast, po, args, tty=fn(key) { tty_map.get(key) })
  let rb = match ro {
    @engine.Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let rval = output_legacy(ast, effects=rb).result
  match rval {
    @abi.Object(kvs) => {
      let mut use_color_val : @abi.ResultValue? = None
      for kv in kvs {
        if kv.0 == "use_color" {
          use_color_val = Some(kv.1)
        }
      }
      // 観測 terminal=true が宣言 default=false より優先する (DR-098 §5 の優先順位)。
      assert_eq(use_color_val, Some(@abi.Scalar(@abi.Bool(true))))
    }
    _ => fail("output.result should be @abi.Object")
  }
  assert_eq(
    render_rval_sorted(output_legacy(ast, effects=rb).sources),
    "{use_color=tty}",
  )
}

///|
/// 保証 (issue front-door-resolve-ref-repeat-row-drop, K カテゴリ調査 2026-07-16): a ref-template
/// accum entity (`or` 枝 = seq(r,g,b) / string(colorname)、`multiple:"append"` + repeat) wraps its
/// own row bindings one scope level deeper than its declaring scope (`ref_row_head`/`@engine.Scoped(e.name,
/// ...)`, installer.mbt DR-078 §1) — `front_door.resolve` (= `resolve_scope_tree`) used to filter
/// "this scope's own bindings" by an EXACT scope-path match, which silently dropped that one-level-
/// deeper wrap (it is neither an exact-path binding nor a genuine `@engine.CommandSatisfied` command child)。
/// `output.result` は fired ref+repeat cell の row を落とさず描画する。`kawaz/kuu` fixture
/// `multiple-parse/ref-rows-append.json` fixes this exact shape (spec の
/// 正本 — 個々の row / count は同 fixture の `zero-fires-empty` / `single-fire-list` /
/// `two-fires-branch-append` case と 1:1); conformance runner stayed green for it because that
/// fixture doesn't trip `use_resolve` (no default ladder needed) and so never exercised
/// `resolve_scope_tree` at all — only `front_door`'s ALWAYS-resolve callers (kuu-cli 実機) exposed
/// the drop, hence pinning it here at the glass-box boundary `resolve_scope_tree` sits behind.
test "front_door.resolve+result: ref+repeat accum セルの row 集約が resolve 経由でも落ちない (DR-078 §1 / DR-084 §2, issue front-door-resolve-ref-repeat-row-drop)" {
  let src =
    #|{"definitions": {"templates": {
    #|  "color": {"or": [
    #|    {"seq": [
    #|      {"type": "number", "name": "r"},
    #|      {"type": "number", "name": "g"},
    #|      {"type": "number", "name": "b"}
    #|    ]},
    #|    {"type": "string", "name": "colorname"}
    #|  ]}
    #|}},
    #|"options": [
    #|  {"name": "hlcolors", "ref": "color", "long": true, "multiple": "append"}
    #|]}
  let j = @json.parse(src)
  let ast = match parse_definition(j) {
    Ok(a) => a
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  // ref-rows-append.json の 3 case を front_door.parse → resolve → result の一気通貫で再現する
  // (conformance runner の no-resolve 抜け道を経由しない = kuu-cli が実際に叩く経路そのもの)。
  fn hlcolors_of(args : Array[String]) -> @abi.ResultValue raise {
    let po = parse_legacy(ast, args)
    let ro = resolve_legacy(ast, po, args)
    let rb = match ro {
      @engine.Success(b) => b
      other => {
        fail("front_door.resolve should succeed, got " + render_outcome(other))
        panic()
      }
    }
    // resolve が復元済みの #row/#fire を `output` は再 merge せず、その binds を result 射影へ渡す。
    let view = output_legacy(ast, effects=rb)
    match view.result {
      @abi.Object(kvs) => {
        for kv in kvs {
          if kv.0 == "hlcolors" {
            return kv.1
          }
        }
        fail("result should carry a \"hlcolors\" key")
        panic()
      }
      _ => {
        fail("output.result should be @abi.Object at root scope")
        panic()
      }
    }
  }

  // zero-fires-empty: 0 発火でも accum cell は absent にならず `[]` (DR-044 uniform array)。
  assert_eq(hlcolors_of([]), @abi.Array([]))
  // single-fire-list: 1 発火でも要素1件の配列 (scalar への unwrap をしない、DR-034)。
  assert_eq(
    hlcolors_of(["--hlcolors", "red"]),
    @abi.Array([@abi.Object([("colorname", @abi.Scalar(@abi.String("red")))])]),
  )
  // two-fires-branch-append: 2 発火 (or の異なる枝) は row をそのまま順に積む (枝の違いを畳まない)。
  assert_eq(
    hlcolors_of(["--hlcolors", "red", "--hlcolors", "0", "128", "255"]),
    @abi.Array([
      @abi.Object([("colorname", @abi.Scalar(@abi.String("red")))]),
      @abi.Object([
        ("r", @abi.Scalar(@abi.Number(0.0))),
        ("g", @abi.Scalar(@abi.Number(128.0))),
        ("b", @abi.Scalar(@abi.Number(255.0))),
      ]),
    ]),
  )
}

///|
/// An option-level seq is one value slot whose children consume consecutive
/// tokens (DESIGN §1.1/§5.1). 結果キーを持つ子が並べば、その seq の値は**子ごとの object の配列では
/// なく 1 個の kv** になる (DESIGN §2.5「name を持つ子が並べば結果が自然に kv になる」/ §2.4 の
/// 露出規則 — 深い name 層は止めた層が作る子スコープに属する)。同じ規則を ref-template 経由で
/// pin しているのが `fixtures/repeat-parse/ref-template-no-repeat-degenerate.json` の
/// `single-rgb-degenerate-row` (`{hlcolor: {r,g,b}}`) — inline `seq` と `ref` は同じ消費文法の
/// 別の書き口 (DR-078 §1) なので結果形も一致する。
test "option seq folds its named children into one kv row" {
  let src =
    #|{"options": [{
    #|  "name": "config_file",
    #|  "long": true,
    #|  "seq": [
    #|    {"name": "path", "type": "string"},
    #|    {"name": "value", "type": "string"}
    #|  ]
    #|}]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  let parsed = parse_legacy(ast, ["--config-file", "p", "v"])
  let resolved = resolve_legacy(ast, parsed, ["--config-file", "p", "v"])
  let effects = match resolved {
    @engine.Success(bindings) => bindings
    other => {
      fail(
        "option seq should consume both operands, got " + render_outcome(other),
      )
      panic()
    }
  }
  match output_legacy(ast, effects~).result {
    @abi.Object(
      [
        (
          "config_file",
          @abi.Object(
            [
              ("path", @abi.Scalar(@abi.String("p"))),
              ("value", @abi.Scalar(@abi.String("v"))),
            ]
          ),
        ),
      ]
    ) => ()
    other =>
      fail(
        "option seq should produce config_file={path:p, value:v}, got " +
        render_rval_sorted(other),
      )
  }
}

///|
test "option seq supports three children and equal-separated first child" {
  let src =
    #|{"options": [{
    #|  "name": "triple",
    #|  "long": true,
    #|  "seq": [
    #|    {"name": "a", "type": "string"},
    #|    {"name": "b", "type": "string"},
    #|    {"name": "c", "type": "string"}
    #|  ]
    #|}]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  fn result_of(args : Array[String]) -> @abi.ResultValue raise {
    let parsed = parse_legacy(ast, args)
    let resolved = resolve_legacy(ast, parsed, args)
    let effects = match resolved {
      @engine.Success(bindings) => bindings
      other => {
        fail("option seq should parse, got " + render_outcome(other))
        panic()
      }
    }
    output_legacy(ast, effects~).result
  }
  let expected : @abi.ResultValue = @abi.Object([
    (
      "triple",
      @abi.Object([
        ("a", @abi.Scalar(@abi.String("x"))),
        ("b", @abi.Scalar(@abi.String("y"))),
        ("c", @abi.Scalar(@abi.String("z"))),
      ]),
    ),
  ])
  assert_eq(result_of(["--triple", "x", "y", "z"]), expected)
  assert_eq(result_of(["--triple=x", "y", "z"]), expected)
}

///|
test "option seq reports missing_operand when a child token is absent" {
  let src =
    #|{"options": [{
    #|  "name": "pair",
    #|  "long": true,
    #|  "seq": [
    #|    {"name": "left", "type": "string"},
    #|    {"name": "right", "type": "string"}
    #|  ]
    #|}]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  match parse_legacy(ast, ["--pair", "x"]) {
    @engine.Failure(detail) => {
      let mut found = false
      for error in detail.errors {
        if error.element == "right" && error.reason == "missing_operand" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail("starved option seq should fail, got " + render_outcome(other))
  }
}

///|
/// 保証 (DR-034 §6.2 / DR-044 §1): `multiple` が積む単位は**発火 1 回ぶんの値** = seq 1 行の kv で
/// あり、発火ごとに余分な配列階層は付かない。`fixtures/multiple-parse/ref-rows-append.json` の
/// `two-fires-branch-append` (`{hlcolors: [{colorname:"red"}, {r,g,b}]}`) の inline `seq` 版。
test "option seq multiple appends one kv row per firing" {
  let src =
    #|{"options": [{
    #|  "name": "pair",
    #|  "long": true,
    #|  "seq": [
    #|    {"name": "left", "type": "string"},
    #|    {"name": "right", "type": "string"}
    #|  ],
    #|  "multiple": "append"
    #|}]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  let args = ["--pair", "a", "b", "--pair=c", "d"]
  let parsed = parse_legacy(ast, args)
  let resolved = resolve_legacy(ast, parsed, args)
  let effects = match resolved {
    @engine.Success(bindings) => bindings
    other => {
      fail("multiple option seq should parse, got " + render_outcome(other))
      panic()
    }
  }
  assert_eq(
    output_legacy(ast, effects~).result,
    @abi.Object([
      (
        "pair",
        @abi.Array([
          @abi.Object([
            ("left", @abi.Scalar(@abi.String("a"))),
            ("right", @abi.Scalar(@abi.String("b"))),
          ]),
          @abi.Object([
            ("left", @abi.Scalar(@abi.String("c"))),
            ("right", @abi.Scalar(@abi.String("d"))),
          ]),
        ]),
      ),
    ]),
  )
}

///|
/// 保証 (対極、DESIGN §5.1 / DR-052 §2 / DR-044 §2): 結果キーを持つ子が 1 つも無い seq は
/// **配列形のまま** — 直上 2 本が固定する kv 畳み込みは「結果キーを持つ子が並ぶとき」の規則で
/// あって、seq という構造そのものが kv になるのではない。この配列形が from_entries の entries
/// 用法 (`[[k,v],...]` → object) が乗る座であり (DR-044 §2 の第 1 用法)、畳み込みを無条件に
/// 適用すると壊れる面。
test "option seq keeps the array form when no child carries a result key" {
  let anon =
    #|{"options": [{"name": "pair", "long": true, "seq": [
    #|  {"type": "string"}, {"type": "string"}
    #|]}]}
  let entries =
    #|{"options": [{"name": "entries", "long": true,
    #|  "multiple": {"accumulator": "append", "collector": {"from_entries": "entries"}},
    #|  "seq": [{"type": "string"}, {"type": "string"}]
    #|}]}
  fn result_of(src : String, args : Array[String]) -> @abi.ResultValue raise {
    let ast = match parse_definition(@json.parse(src)) {
      Ok(value) => value
      Err(_) => {
        fail("parse_definition failed")
        panic()
      }
    }
    let parsed = parse_legacy(ast, args)
    match resolve_legacy(ast, parsed, args) {
      @engine.Success(bindings) => output_legacy(ast, effects=bindings).result
      other => {
        fail("anonymous option seq should parse, got " + render_outcome(other))
        panic()
      }
    }
  }

  // 無名 2 子 = 子の値の配列 (DESIGN §5.1)。
  assert_eq(
    result_of(anon, ["--pair", "a", "1"]),
    @abi.Object([
      (
        "pair",
        @abi.Array([
          @abi.Scalar(@abi.String("a")),
          @abi.Scalar(@abi.String("1")),
        ]),
      ),
    ]),
  )
  // その配列形の上に from_entries entries 用法が乗る (DR-044 §2)。
  assert_eq(
    result_of(entries, ["--entries", "a", "1", "--entries", "b", "2"]),
    @abi.Object([
      (
        "entries",
        @abi.Object([
          ("a", @abi.Scalar(@abi.String("1"))),
          ("b", @abi.Scalar(@abi.String("2"))),
        ]),
      ),
    ]),
  )
}

///|
/// 保証 (DR-078 §1): 同じ消費文法を **どの書き口で書いても結果形は一致する**。inline `seq` /
/// `definitions.templates` 経由の `ref` / 構造 `or` の複数 item 枝 — 3 つとも同じ畳み方
/// (`@engine.seq_body_node`、結果キーを持つ子が 1 つでもあれば 1 個の kv、無ければ子の値の配列)
/// を共有する。ここが割れると「テンプレに切り出したら結果形が変わった」が起きる (実際、
/// templates の seq 本体だけが子 head を素で並べており、無名の子が全員同じ単一セルへ束ねられて
/// last-wins で 1 個に潰れていた — `{pair: "1"}`)。option 面と positional 面の両方で見る。
test "seq result shape is identical across inline / ref-template / or-branch" {
  fn result_of(src : String, args : Array[String]) -> @abi.ResultValue raise {
    let ast = match parse_definition(@json.parse(src)) {
      Ok(value) => value
      Err(_) => {
        fail("parse_definition failed for " + src)
        panic()
      }
    }
    let parsed = parse_legacy(ast, args)
    match resolve_legacy(ast, parsed, args) {
      @engine.Success(bindings) => output_legacy(ast, effects=bindings).result
      other => {
        fail("seq definition should parse, got " + render_outcome(other))
        panic()
      }
    }
  }

  // ── 無名の子 = 子の値の配列 (DESIGN §5.1)、3 経路とも同じ ────────────────
  let anon_array : @abi.ResultValue = @abi.Object([
    (
      "pair",
      @abi.Array([@abi.Scalar(@abi.String("a")), @abi.Scalar(@abi.String("1"))]),
    ),
  ])
  let anon_inline =
    #|{"options": [{"name": "pair", "long": true,
    #|  "seq": [{"type": "string"}, {"type": "string"}]}]}
  let anon_ref =
    #|{"definitions": {"templates": {"p": {
    #|  "seq": [{"type": "string"}, {"type": "string"}]}}},
    #| "options": [{"name": "pair", "long": true, "ref": "p"}]}
  let anon_or =
    #|{"options": [{"name": "pair", "long": true, "or": [
    #|  {"seq": [{"type": "string"}, {"type": "string"}]}]}]}
  assert_eq(result_of(anon_inline, ["--pair", "a", "1"]), anon_array)
  assert_eq(result_of(anon_ref, ["--pair", "a", "1"]), anon_array)
  assert_eq(result_of(anon_or, ["--pair", "a", "1"]), anon_array)

  // ── 結果キーを持つ子 = 1 個の kv (DESIGN §2.4/§2.5)、3 経路とも同じ ───────
  let named_kv : @abi.ResultValue = @abi.Object([
    (
      "pair",
      @abi.Object([
        ("path", @abi.Scalar(@abi.String("a"))),
        ("value", @abi.Scalar(@abi.String("1"))),
      ]),
    ),
  ])
  let named_inline =
    #|{"options": [{"name": "pair", "long": true, "seq": [
    #|  {"name": "path", "type": "string"}, {"name": "value", "type": "string"}]}]}
  let named_ref =
    #|{"definitions": {"templates": {"p": {"seq": [
    #|  {"name": "path", "type": "string"}, {"name": "value", "type": "string"}]}}},
    #| "options": [{"name": "pair", "long": true, "ref": "p"}]}
  let named_or =
    #|{"options": [{"name": "pair", "long": true, "or": [{"seq": [
    #|  {"name": "path", "type": "string"}, {"name": "value", "type": "string"}]}]}]}
  assert_eq(result_of(named_inline, ["--pair", "a", "1"]), named_kv)
  assert_eq(result_of(named_ref, ["--pair", "a", "1"]), named_kv)
  assert_eq(result_of(named_or, ["--pair", "a", "1"]), named_kv)

  // ── positional 面: ref テンプレと構造 or (positional 直下に inline seq の書き口は無い) ──
  let pos_anon_ref =
    #|{"definitions": {"templates": {"p": {
    #|  "seq": [{"type": "string"}, {"type": "string"}]}}},
    #| "positionals": [{"name": "pair", "ref": "p"}]}
  let pos_anon_or =
    #|{"positionals": [{"name": "pair", "or": [
    #|  {"seq": [{"type": "string"}, {"type": "string"}]}]}]}
  assert_eq(result_of(pos_anon_ref, ["a", "1"]), anon_array)
  assert_eq(result_of(pos_anon_or, ["a", "1"]), anon_array)

  // ── multiple を被せても畳み単位は「発火 1 回ぶんの行」で一致 (DR-044 §1) ──
  let two_rows : @abi.ResultValue = @abi.Object([
    (
      "pair",
      @abi.Array([
        @abi.Array([
          @abi.Scalar(@abi.String("a")),
          @abi.Scalar(@abi.String("1")),
        ]),
        @abi.Array([
          @abi.Scalar(@abi.String("b")),
          @abi.Scalar(@abi.String("2")),
        ]),
      ]),
    ),
  ])
  let multi_args = ["--pair", "a", "1", "--pair", "b", "2"]
  let multi_inline =
    #|{"options": [{"name": "pair", "long": true, "multiple": "append",
    #|  "seq": [{"type": "string"}, {"type": "string"}]}]}
  let multi_ref =
    #|{"definitions": {"templates": {"p": {
    #|  "seq": [{"type": "string"}, {"type": "string"}]}}},
    #| "options": [{"name": "pair", "long": true, "multiple": "append", "ref": "p"}]}
  let multi_or =
    #|{"options": [{"name": "pair", "long": true, "multiple": "append", "or": [
    #|  {"seq": [{"type": "string"}, {"type": "string"}]}]}]}
  assert_eq(result_of(multi_inline, multi_args), two_rows)
  assert_eq(result_of(multi_ref, multi_args), two_rows)
  assert_eq(result_of(multi_or, multi_args), two_rows)

  // 無名 3 子 / 1 子でも配列の要素数は宣言した子の数に一致する (要素数で構造を変えない)。
  let ref_three =
    #|{"definitions": {"templates": {"p": {"seq": [
    #|  {"type": "string"}, {"type": "string"}, {"type": "string"}]}}},
    #| "options": [{"name": "pair", "long": true, "ref": "p"}]}
  assert_eq(
    result_of(ref_three, ["--pair", "a", "1", "z"]),
    @abi.Object([
      (
        "pair",
        @abi.Array([
          @abi.Scalar(@abi.String("a")),
          @abi.Scalar(@abi.String("1")),
          @abi.Scalar(@abi.String("z")),
        ]),
      ),
    ]),
  )
  let ref_one =
    #|{"definitions": {"templates": {"p": {"seq": [{"type": "string"}]}}},
    #| "options": [{"name": "pair", "long": true, "ref": "p"}]}
  assert_eq(
    result_of(ref_one, ["--pair", "a"]),
    @abi.Object([("pair", @abi.Array([@abi.Scalar(@abi.String("a"))]))]),
  )
}

///|
test "single-value option remains scalar after option seq support" {
  let src =
    #|{"options": [{"name": "port", "type": "string", "long": true}]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  let args = ["--port", "80"]
  let parsed = parse_legacy(ast, args)
  let resolved = resolve_legacy(ast, parsed, args)
  let effects = match resolved {
    @engine.Success(bindings) => bindings
    other => {
      fail("single-value option should parse, got " + render_outcome(other))
      panic()
    }
  }
  assert_eq(
    output_legacy(ast, effects~).result,
    @abi.Object([("port", @abi.Scalar(@abi.String("80")))]),
  )
}

///|
/// 保証 (DR-120 §3 / DR-052 §1、dogfooding D4 で発見した実バグの根治 pin): 露出キーの解決は
/// **結果スコープ単位・軸単位**で行われる。静的検査 (`parse_definition` の
/// export-key-collision) と result builder は同じ 1 本の走査から出た同じ木を読むので、
/// 「検査は別キーと判定するのに result builder は identity のキーを書く」食い違いが起きない。
///
/// 落とす退行は 2 つとも「露出キーの解決を名前 1 枚の平坦な写像で持つ」実装が踏むもの:
///
/// 1. **同一スコープ・別軸の同名** — option `x` (`export_key: "ox"`) と command `x` が並ぶと、
///    平坦写像では宣言順で後に来る command の軸 (未指定 = identity) が option の軸を上書きし、
///    `--x` の結果キーが `ox` でなく `x` になる (= `export_key` が実行時に黙って無視される)。
///    静的検査は露出キー `ox` と `x` を別物と正しく判定するので `validate` は ok を返し、
///    食い違いだけが残る。同名 option / command の同居自体は合法 (DR-120 §7: 綴り軸と結果キー軸
///    は別、`fixtures/export-key/collision-option-command.json` が衝突する側を pin)
/// 2. **別スコープの同名** — root の `p` (identity) と子 command の `p` (`export_key: "sp"`)
///    のように、スコープが違えば衝突しない (DR-021「スコープ階層が違えば対象外」) 同名要素が
///    平坦写像では 1 エントリを取り合い、root の `--p` の結果キーが子の `export_key` になる
test "front_door.output: 露出キーの解決は結果スコープ・軸ごと (DR-052 §1 / DR-120 §3)" {
  fn result_of(src : String, args : Array[String]) -> String raise {
    let ast = match parse_definition(@json.parse(src)) {
      Ok(value) => value
      Err(_) => {
        fail("parse_definition should accept the definition")
        panic()
      }
    }
    let parsed = parse_legacy(ast, args)
    let resolved = resolve_legacy(ast, parsed, args)
    let effects = match resolved {
      @engine.Success(bindings) => bindings
      other => {
        fail("should parse, got " + render_outcome(other))
        panic()
      }
    }
    render_rval_sorted(output_legacy(ast, effects~).result)
  }

  // 1. option `x` (export_key: "ox") と command `x` の同居。`--x` は option の結果キー `ox`。
  let option_and_command =
    #|{"options":[{"name":"x","type":"flag","long":true,"export_key":"ox"}],
    #| "commands":[{"name":"x","type":"command","options":[{"name":"inner","type":"flag","long":true}]}]}
  assert_eq(result_of(option_and_command, ["--x"]), "{ox=true}")
  // 同じ定義で command 側を選ぶと scope label は identity の `x` (option の export_key に
  // 引きずられない)。`inner` は未発火の flag なので preset default が入る。
  assert_eq(result_of(option_and_command, ["x"]), "{ox=false,x={inner=false}}")
  // 2. root の `p` と子 scope の `p` (export_key: "sp")。root の `--p` は identity の `p`。
  let same_name_across_scopes =
    #|{"options":[{"name":"p","type":"flag","long":true}],
    #| "commands":[{"name":"sub","type":"command","options":[{"name":"p","type":"flag","long":true,"export_key":"sp"}]}]}
  assert_eq(result_of(same_name_across_scopes, ["--p"]), "{p=true}")
  // 子 scope 側の `--p` は子の export_key `sp` の下に入る (root の `p` は preset default)。
  assert_eq(
    result_of(same_name_across_scopes, ["sub", "--p"]),
    "{p=false,sub={sp=true}}",
  )
}

///|
/// 保証 (DESIGN §2.3/§2.4/§5.1 / DR-025 の --color 4 パターン / DR-052 §3、issue
/// option-or-result-key-vanishes): **name を持つ要素に `or` を直書きすると、その name が 1 段の
/// 結果スコープを作る**。旧実装は or を「値を持たない構造ディスパッチャ」として扱い、枝の leaf を
/// 親スコープへ平坦に落としていたため、宣言した結果キーが結果から丸ごと消えていた
/// (`{"name":"color","or":[{"type":"string"}]}` + `--color red` → root が object ですらない素の
/// `"red"`、他 option を併存させると `color` だけが消滅)。
///
/// 平坦モデルが spec と食い違う点は 3 つあり、どれも本 test が同時に固定する:
///
/// 1. **同じ body を `ref` で書くと結果形が違った** — `definitions.templates` 経由の or は
///    以前からネストする (`{color:{cname:...}}`、`ref-rows-append.json` 系)。DR-007「ref は構造
///    定義全てを引き継ぐ」に反して直書きと ref で結果が割れていた
/// 2. **`or` と同居する通常フィールドが無言で死んでいた** — DESIGN §1.2 は「`or` / `seq` キーは
///    name / multiple / value_name 等と同居可能」と規定するが、平坦モデルでは wrapper の
///    `export_key` / `multiple` が着地するセルを持たず、宣言が黙って捨てられていた
/// 3. **空間形と `=` 形で結果が割れていた** — `--color=red` は共有 eq_split matcher へ素の entry を
///    積むため、匿名 leaf では値ごと消えていた
test "front_door.output: name を持つ or は 1 段の結果スコープを作る (DESIGN §2.3/§5.1 / DR-025)" {
  fn result_of(src : String, args : Array[String]) -> String raise {
    let ast = match parse_definition(@json.parse(src)) {
      Ok(value) => value
      Err(_) => {
        fail("parse_definition should accept the definition")
        panic()
      }
    }
    let parsed = parse_legacy(ast, args)
    let resolved = resolve_legacy(ast, parsed, args)
    let effects = match resolved {
      @engine.Success(bindings) => bindings
      other => {
        fail("should parse, got " + render_outcome(other))
        panic()
      }
    }
    render_rval_sorted(output_legacy(ast, effects~).result)
  }

  // DR-025 パターン A (or に name / 子に name 無し): 選ばれた枝の値がそのまま `color` に乗る
  // (§5.1「or の値 = 選ばれた子の値」)。枝が 1 本でも 2 本でも構造は変わらない。
  let anon_two_branches =
    #|{"options":[{"name":"color","long":true,"or":[{"type":"string"},{"type":"number"}]},
    #|            {"name":"v","type":"flag","long":true}]}
  assert_eq(
    result_of(anon_two_branches, ["--color", "red"]),
    "{color=red,v=false}",
  )
  let anon_one_branch =
    #|{"options":[{"name":"color","long":true,"or":[{"type":"string"}]},
    #|            {"name":"v","type":"flag","long":true}]}
  assert_eq(
    result_of(anon_one_branch, ["--color", "red", "--v"]),
    "{color=red,v=true}",
  )
  // `=` 形も空間形と同じ結果形 (DR-014 / DESIGN §7.2)。
  assert_eq(result_of(anon_one_branch, ["--color=red"]), "{color=red,v=false}")

  // DR-025 パターン C (or に name / 枝ごとに name): 枝の leaf は `color` の子スコープ。
  let named_leaf =
    #|{"options":[{"name":"color","long":true,"or":[{"type":"string","name":"cname"}]},
    #|            {"name":"v","type":"flag","long":true}]}
  assert_eq(
    result_of(named_leaf, ["--color", "red", "--v"]),
    "{color={cname=red},v=true}",
  )
  // DR-007: 同じ or body を `ref` テンプレ経由で書いても同じ結果形 (直書きと ref が割れない)。
  let named_leaf_via_ref =
    #|{"definitions":{"templates":{"c":{"or":[{"type":"string","name":"cname"}]}}},
    #| "options":[{"name":"color","long":true,"ref":"c"},
    #|            {"name":"v","type":"flag","long":true}]}
  assert_eq(
    result_of(named_leaf_via_ref, ["--color", "red", "--v"]),
    "{color={cname=red},v=true}",
  )

  // DR-025 パターン D (seq 枝の子に name): 枝は 1 個の kv (§2.5)、それが `color` の値になる。
  let seq_branch_named =
    #|{"options":[{"name":"color","long":true,"or":[
    #|   {"seq":[{"type":"number","name":"r"},{"type":"number","name":"g"}]},
    #|   {"type":"string","name":"cname"}]}]}
  assert_eq(
    result_of(seq_branch_named, ["--color", "1", "2"]),
    "{color={g=2,r=1}}",
  )
  // 同じ seq 枝の子が匿名なら §5.1 の「子の値の配列」— option 直下の `seq` と同じ畳み方。
  let seq_branch_anon =
    #|{"options":[{"name":"color","long":true,"or":[
    #|   {"seq":[{"type":"number"},{"type":"number"}]},
    #|   {"type":"string"}]}]}
  assert_eq(result_of(seq_branch_anon, ["--color", "1", "2"]), "{color=[1,2]}")

  // DESIGN §1.2「`or` キーは name / multiple 等と同居可能」: wrapper の `multiple` / `export_key`
  // が実際に効く (平坦モデルでは着地するセルが無く無言で捨てられていた)。
  let multiple_or =
    #|{"options":[{"name":"color","long":true,"multiple":"append",
    #|             "or":[{"type":"string","name":"cname"}]}]}
  assert_eq(
    result_of(multiple_or, ["--color", "red", "--color", "blue"]),
    "{color=[{cname=red},{cname=blue}]}",
  )
  let renamed_or =
    #|{"options":[{"name":"color","long":true,"export_key":"COLOR","or":[{"type":"string"}]}]}
  assert_eq(result_of(renamed_or, ["--color", "red"]), "{COLOR=red}")

  // positional の or も同じ (name を持てば結果スコープ、name 無しは従来どおり透過)。
  let positional_named_or =
    #|{"positionals":[{"name":"color","or":[{"type":"string","name":"cname"}]}]}
  assert_eq(result_of(positional_named_or, ["red"]), "{color={cname=red}}")
  let positional_anon_or =
    #|{"positionals":[{"or":[{"type":"string","name":"cname"}]}]}
  assert_eq(result_of(positional_anon_or, ["red"]), "{cname=red}")

  // 枝 leaf の name が root の兄弟と同名でも露出キー衝突にならない (別スコープ、DR-021
  // 「スコープ階層が違えば対象外」/ DR-120 §3) — 平坦モデルでは同一スコープに並ぶ扱いで
  // definition-error になっていた。ここは `parse_definition` の受理だけを固定する: 結果形は
  // installer の entity 名前空間が平坦 (`ensure_entity` は name で add-if-absent) なため、
  // 同名の root 兄弟が preset default を失う別のギャップに当たる (issue 起票対象、本 test の
  // 射程外)。
  let leaf_shares_sibling_name =
    #|{"options":[{"name":"color","long":true,"or":[{"type":"string","name":"v"}]},
    #|            {"name":"v","type":"flag","long":true}]}
  assert_true(parse_definition(@json.parse(leaf_shares_sibling_name)) is Ok(_))
}

///|
/// Render the complete DR-122 shadow tree with deterministic object-key ordering.
fn wbtest_sources_of(src : String, args : Array[String]) -> String raise {
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition should accept the definition")
      panic()
    }
  }
  let parsed = parse_legacy(ast, args)
  let resolved = resolve_legacy(ast, parsed, args)
  let effects = match resolved {
    @engine.Success(bindings) => bindings
    other => {
      fail("should resolve, got " + render_outcome(other))
      panic()
    }
  }
  render_rval_sorted(output_legacy(ast, effects~).sources)
}

///|
/// OutputView の 3 面 (`result` / `sources` / `effects`) を 1 本の文字列へ整形する。
fn wbtest_view_of(src : String, args : Array[String]) -> String raise {
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition should accept the definition")
      panic()
    }
  }
  let parsed = parse_legacy(ast, args)
  let resolved = resolve_legacy(ast, parsed, args)
  let effects = match resolved {
    @engine.Success(bindings) => bindings
    other => {
      fail("should resolve, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects~)
  let eff_items : Array[String] = []
  for effect in view.effects {
    eff_items.push(effect.entity)
  }
  test_sort_items(eff_items)
  "result=" +
  render_rval_sorted(view.result) +
  " sources=" +
  render_rval_sorted(view.sources) +
  " effects=" +
  test_join_comma(eff_items)
}

///|
/// DR-029 の値同期と DR-031 / DR-121 §4 の経路 provenance を一組で固定する。
/// canonical 自身の入口は `cli`、別要素の `link` 入口は同じ canonical cell に `link` として
/// 着地し、参照側は自前の結果キーを持たない。両入口を使った場合は args 順で最後に値を確定した
/// 効果の source が残る。
test "front_door.output: link entry routes into the canonical cell with source=link (DR-029 / DR-031 / DR-121 §4)" {
  let src =
    #|{"options":[
    #|  {"name":"target","type":"string","long":true},
    #|  {"name":"legacy","type":"string","long":[":set:linked"],"link":"target"}
    #|]}
  assert_eq(
    wbtest_view_of(src, ["--target", "canonical"]),
    "result={target=canonical} sources={target=cli} effects=target",
  )
  assert_eq(
    wbtest_view_of(src, ["--legacy"]),
    "result={target=linked} sources={target=link} effects=target",
  )
  assert_eq(
    wbtest_view_of(src, ["--target", "first", "--legacy"]),
    "result={target=linked} sources={target=link} effects=target",
  )
  assert_eq(
    wbtest_view_of(src, ["--legacy", "--target", "last"]),
    "result={target=last} sources={target=cli} effects=target",
  )
}

///|
/// Root link routing is independent of entry spelling: long space form, eq-split form, and positional
/// consumption all use the linked element's own parser but land in the same canonical cell.
test "front_door.output: link routes long space, eq-split, and positional entry forms through one target" {
  let option_src =
    #|{"options":[
    #|  {"name":"target","type":"string"},
    #|  {"name":"legacy","type":"string","long":true,"link":"target"}
    #|]}
  assert_eq(
    wbtest_view_of(option_src, ["--legacy", "space"]),
    "result={target=space} sources={target=link} effects=target",
  )
  assert_eq(
    wbtest_view_of(option_src, ["--legacy=equal"]),
    "result={target=equal} sources={target=link} effects=target",
  )
  let positional_src =
    #|{"options":[{"name":"target","type":"string"}],
    #| "positionals":[{"name":"legacy","type":"string","link":"target"}]}
  assert_eq(
    wbtest_view_of(positional_src, ["operand"]),
    "result={target=operand} sources={target=link} effects=target",
  )
}

///|
/// DR-086 cut classifies the entry's consumption shape through transparent link/global wrappers.
/// A value-taking main entry that can consume `always` must suppress the same-trigger zero-argument
/// variant, leaving the required positional unsatisfied rather than reinterpreting that token.
test "front_door.parse: link wrapper preserves value-slot cut against zero-argument variant (DR-086)" {
  let src =
    #|{"options":[
    #|  {"name":"target","type":"string"},
    #|  {"name":"color","type":"string","long":[":set",":set:always"],
    #|   "values":["always","none"],"link":"target"}
    #|],"positionals":[{"name":"extra","type":"string","required":true}]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  match parse_legacy(ast, ["--color", "always"]) {
    @engine.Failure(detail) => {
      let mut found = false
      for error in detail.errors {
        if error.element == "extra" && error.reason == "missing_operand" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "value-slot cut should preserve the missing operand, got " +
        render_outcome(other),
      )
  }
}

///|
/// A global link entry keeps the declaring target cell when copied into a command scope. Long space,
/// eq-split, and short matcher entries all carry the full lexical escape depth.
test "front_door.output: global link entries keep target routing across command scopes" {
  let src =
    #|{"options":[
    #|  {"name":"target","type":"string"},
    #|  {"name":"legacy","type":"string","long":true,"short":"l","global":true,"link":"target"}
    #|],"commands":[{"type":"command","name":"sub","options":[
    #|  {"name":"quiet","type":"flag","long":true}
    #|]}]}
  let expected = "result={sub={quiet=true},target=value} sources={sub={quiet=cli},target=link} effects=quiet,target"
  assert_eq(
    wbtest_view_of(src, ["sub", "--legacy", "value", "--quiet"]),
    expected,
  )
  assert_eq(wbtest_view_of(src, ["sub", "--legacy=value", "--quiet"]), expected)
  assert_eq(wbtest_view_of(src, ["sub", "-l", "value", "--quiet"]), expected)
}

///|
/// DR-032 target identity is bound where a global link is declared. A descendant's same-named
/// local cell must not capture the copied link by causing a second bare-name lookup.
test "front_door.output: copied global link ignores descendant same-name target shadow" {
  let src =
    #|{"options":[{"name":"target","type":"string","global":true}],
    #| "commands":[{"type":"command","name":"mid","options":[
    #|   {"name":"legacy","type":"string","long":true,"global":true,"link":"target"}
    #| ],"commands":[{"type":"command","name":"sub","options":[
    #|   {"name":"target","type":"string","long":true},
    #|   {"name":"quiet","type":"flag","long":true}
    #| ]}]}]}
  assert_eq(
    wbtest_view_of(src, ["mid", "sub", "--legacy", "value", "--quiet"]),
    "result={mid={sub={quiet=true}},target=value} sources={mid={sub={quiet=cli}},target=link} effects=quiet,target",
  )
}

///|
/// link は canonical cell の露出キー位置へ provenance を置く。canonical が `export_key` で
/// rename されても、参照側の name は result/sources に現れない。
test "front_door.output: link source follows the canonical export_key position (DR-122 §2 / DR-121 §4)" {
  let src =
    #|{"options":[
    #|  {"name":"target","type":"string","export_key":"published"},
    #|  {"name":"legacy","type":"string","long":[":set:linked"],"link":"target"}
    #|]}
  assert_eq(
    wbtest_view_of(src, ["--legacy"]),
    "result={published=linked} sources={published=link} effects=target",
  )
}

///|
/// DR-067 §1 の参照層: bare-name link target は定義時に同一 lexical scope で解決し、存在しない
/// target は実行時の Reject へ遅延せず `absent-ref` definition-error にする。
test "front_door.parse_definition: an absent bare link target is @abi.AbsentRef (DR-067 §1)" {
  let src =
    #|{"options":[{"name":"legacy","type":"string","long":true,"link":"missing"}]}
  match parse_definition(@json.parse(src)) {
    Ok(_) => fail("expected absent-ref definition error")
    Err(Rejected(errors)) => {
      let mut found = false
      for error in errors {
        if error.element == "legacy" && error.kind == @abi.AbsentRef {
          found = true
        }
      }
      assert_true(found)
    }
    Err(Malformed(message)) =>
      fail("expected absent-ref, got malformed: " + message)
  }
}

///|
/// DR-029 では ref/type と link は直交するが、現実装は ref leaf の wrapper scope 除去と複合値 carrier
/// をまだ持たない。silent wrong answer を避け、解除条件が実装されるまで unsupported で明示的に塞ぐ。
test "front_door.parse_definition: ref plus link is explicitly unsupported until structured routing exists" {
  let src =
    #|{"definitions":{"templates":{"payload":{"type":"string","name":"value"}}},
    #| "options":[
    #|  {"name":"target","type":"string"},
    #|  {"name":"legacy","long":true,"ref":"payload","link":"target"}
    #| ]}
  match parse_definition(@json.parse(src)) {
    Err(Rejected(errors)) => {
      let mut found = false
      for error in errors {
        if error.element == "legacy" && error.kind == @abi.Unsupported {
          found = true
        }
      }
      assert_true(found)
    }
    Err(Malformed(message)) =>
      fail("expected unsupported, got malformed: " + message)
    Ok(_) => fail("ref+link must not silently keep the reference-side result")
  }
}

///|
/// DR-029 の操作列例: count 入口の increment と canonical number 入口の set は同じ target cell の
/// mutation 列へ args 順で合流する。最後の `-v` は link 経路なので最終 source も `link` になる。
test "front_door.output: link preserves mixed count increment and set operation order (DR-029)" {
  let src =
    #|{"options":[
    #|  {"name":"log_level","type":"number","long":true,"default":0},
    #|  {"name":"verbose","type":"count","short":"v","link":"log_level"}
    #|]}
  assert_eq(
    wbtest_view_of(src, ["-vv", "--log-level", "5", "-v"]),
    "result={log_level=6} sources={log_level=link} effects=log_level",
  )
}

///|
/// 保証 (DR-052 §1 結果キー軸 / DR-109 §3 値の出所): `sources` のキーは **result と同じ露出キー
/// 体系**で並ぶ — 定義が command を持つかどうかで軸が変わらない。`export-key/rename-flag-default.json`
/// が射影後キーの直接 pin (cell name `verbose` に対し `sources: {"v": "cli"}`)、
/// `export-key/rename-multiple.json` の why が「sources も同じ射影後キーの下で由来を示す」と
/// 明言する。R1: 値セル rename × commands あり。
test "front_door.output: command 木でも値セル rename が sources に効く (DR-052 §1)" {
  let src =
    #|{"options":[{"name":"verbose","type":"flag","long":true,"export_key":"v"}],
    #| "commands":[{"type":"command","name":"serve"}]}
  assert_eq(wbtest_sources_of(src, ["--verbose"]), "{v=cli}")
}

///|
/// R2 (DR-052 §1): scope ラベル rename — command 自身の露出キーと配下セルの露出キーの両方が
/// sources の path/key に載る。
test "front_door.output: command 木の scope ラベル rename が sources に効く (DR-052 §1)" {
  let src =
    #|{"commands":[{"type":"command","name":"cmd","export_key":"sv","options":[
    #|  {"name":"inner","type":"number","long":true,"export_key":"i"}]}]}
  assert_eq(wbtest_sources_of(src, ["cmd", "--inner", "3"]), "{sv={i=cli}}")
}

///|
/// R3 (DR-052 §2): scope 透過 (`export_key: null`) — ラベル segment が落ち、子が親スコープへ
/// 昇格する。sources の path も同じく 1 段浅くなる。
test "front_door.output: command 木の scope 透過昇格が sources に効く (DR-052 §2)" {
  let src =
    #|{"commands":[{"type":"command","name":"serve","export_key":null,"options":[
    #|  {"name":"port","type":"number","long":true}]}]}
  assert_eq(wbtest_sources_of(src, ["serve", "--port", "80"]), "{port=cli}")
}

///|
/// R4 (DR-052 §2): 値セル透過 (`export_key: null`) × commands あり — 結果キー軸を持たない値は
/// result から消える (`export-key/transparent-kv.json`) ので sources からも消える。
test "front_door.output: command 木でも透過値セルは sources に現れない (DR-052 §2)" {
  let src =
    #|{"options":[{"name":"opt","type":"number","long":true,"export_key":null},
    #|            {"name":"keep","type":"number","long":true}],
    #| "commands":[{"type":"command","name":"serve"}]}
  assert_eq(wbtest_sources_of(src, ["--opt", "1", "--keep", "2"]), "{keep=cli}")
}

///|
/// 保証 (DR-044 uniform array / DR-109 §3): 0 回発火の accum セルは result で `[]` を持つ
/// (未発火でも absent にならない) ので、`sources` にも `default` の席がある — command 木の
/// 有無で非対称にならない。未発火 flag・default 付きスカラは値源ラダーが default 席を解いて
/// binding を作るので両経路とも既に `default` を出すが、0 回発火の accum セルだけは binding が
/// 作られないため木経路で欠けていた。
test "front_door.output: command 木でも 0 回発火の accum セルが default 由来を持つ (DR-044, DR-109 §3)" {
  let src =
    #|{"options":[{"name":"a","type":"flag","long":true},
    #|            {"name":"ttl","type":"number","long":true,"default":30},
    #|            {"name":"tags","type":"string","long":true,"multiple":"append"}],
    #| "commands":[{"type":"command","name":"serve"}]}
  assert_eq(wbtest_sources_of(src, []), "{a=default,tags=[],ttl=default}")
}

///|
/// U1/U2 (CONFORMANCE.md §2「sources のキーは result と同一のキー体系」): `name` 付き `seq` が
/// 作る結果スコープ (DESIGN §2.3) の path は、**定義に command があるかどうかに依らず** sources
/// に載る。`pr` は result で `{"pr":{"path":..,"value":..}}` なので sources も `pr.path`/`pr.value`。
/// U1 (command 無し) と U2 (未発火 dummy command 1 本) を対にすることで「command の有無で
/// sources の path 軸が変わらない」を直接 pin する。
test "front_door.output: named seq の結果スコープ path は command 無しでも sources に載る" {
  let body =
    #|"options":[{"name":"pr","long":true,"seq":[
    #|  {"name":"path","type":"string"},{"name":"value","type":"string"}]}]
  let no_command = "{" + body + "}"
  let with_command = "{" +
    body +
    ",\"commands\":[{\"type\":\"command\",\"name\":\"dummy\"}]}"
  let want = "{pr={path=cli,value=cli}}"
  assert_eq(wbtest_sources_of(no_command, ["--pr", "x", "y"]), want)
  assert_eq(wbtest_sources_of(with_command, ["--pr", "x", "y"]), want)
}

///|
/// U3 (DESIGN §2.4 / DR-025 C 型): `name` 付き `or` の枝 leaf も同じく 1 段の結果スコープに入る
/// (`{"mode":{"num":7}}`) ので、sources のキーは `mode.num`。U1/U2 と同じく command の有無で
/// 変わらない。枝は int/bool で値空間が排他 (完全経路ちょうど 1 本、`or-parse/
/// option-named-branch-leaves-kv.json` と同じ型選定)。
test "front_door.output: named or の結果スコープ path は command 無しでも sources に載る" {
  let body =
    #|"options":[{"name":"mode","long":true,"or":[
    #|  {"name":"num","type":"int"},{"name":"flag","type":"bool"}]}]
  let no_command = "{" + body + "}"
  let with_command = "{" +
    body +
    ",\"commands\":[{\"type\":\"command\",\"name\":\"dummy\"}]}"
  let want = "{mode={num=cli}}"
  assert_eq(wbtest_sources_of(no_command, ["--mode", "7"]), want)
  assert_eq(wbtest_sources_of(with_command, ["--mode", "7"]), want)
}

///|
/// U5 (DR-045「default 値へ戻す... committed=false」): `unset` variant の発火は CLI 由来だが
/// 値としては未確定 (ラダーの再着席結果は "as if untouched") なので、`sources` は発火トークン
/// 自身の `cli` ではなく `default` を報告する。ラダーを走らせない parse-only 経路
/// (`output_of_interpretation` / `output_legacy` に parse 相 binds を渡す形) でしか観測できない
/// — resolve を通せばラダーが default 席を解いて binding を差し替えるため。
/// 射影の統一 (`result_sources` 1 本化) でこの読み替えを落とさないことの pin。
test "front_door.output: unset 発火の値源は default (parse-only 経路、DR-045)" {
  let src =
    #|{"options":[{"name":"color","type":"string",
    #|  "long":[":set","no:unset","reset:default"],"default":"auto"}]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition should accept the definition")
      panic()
    }
  }
  let binds = match parse_legacy(ast, ["--no-color"]) {
    @engine.Success(bindings) => bindings
    other => {
      fail("should parse, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects=binds)
  assert_eq(render_rval_sorted(view.sources), "{color=default}")
}

///|
/// `wbtest_view_of` の変種: `sources` は **どの結果キーが席を持つか** の集合だけを見る (値源
/// タグも path も落とす)。`repeat` 配下の断面は sources の path に index segment (`#k`) が
/// 現れるが、配列要素の provenance addressing は spec 側の未裁定事項なので、内部セルの除外を
/// 見るだけの pin がその綴りに依存しないようにする。
///
/// キーは「席の葉」だけを取る — `grp.#0.gflag` なら `gflag`。除外を見るには「その名前の席が
/// 在るか / 無いか」で足り、どこに在るかは `result` 側 (同じ関数が返す) が語る。
fn wbtest_collect_source_keys(
  source : @abi.ResultValue,
  out : Array[String],
) -> Unit {
  match source {
    @abi.Object(fields) =>
      for field in fields {
        match field.1 {
          @abi.Scalar(_) => out.push(field.0)
          nested => wbtest_collect_source_keys(nested, out)
        }
      }
    @abi.Array(values) =>
      for value in values {
        wbtest_collect_source_keys(value, out)
      }
    @abi.Scalar(_) => ()
  }
}

///|
fn wbtest_view_keys_of(src : String, args : Array[String]) -> String raise {
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition should accept the definition")
      panic()
    }
  }
  let parsed = parse_legacy(ast, args)
  let resolved = resolve_legacy(ast, parsed, args)
  let effects = match resolved {
    @engine.Success(bindings) => bindings
    other => {
      fail("should resolve, got " + render_outcome(other))
      panic()
    }
  }
  let view = output_legacy(ast, effects~)
  let src_items : Array[String] = []
  wbtest_collect_source_keys(view.sources, src_items)
  test_sort_items(src_items)
  let eff_items : Array[String] = []
  for effect in view.effects {
    eff_items.push(effect.entity)
  }
  test_sort_items(eff_items)
  "result=" +
  render_rval_sorted(view.result) +
  " source-keys=" +
  test_join_comma(src_items) +
  " effects=" +
  test_join_comma(eff_items)
}

///|
/// `body` (options/positionals の JSON 断片) を 1 段の command scope で包む。`export_key` は
/// `None` = 指定なし (identity) / `Some("\"sv\"")` = rename / `Some("null")` = 透過。
fn wbtest_under_command(body : String, export_key : String?) -> String {
  let label = match export_key {
    None => ""
    Some(v) => ",\"export_key\":" + v
  }
  "{\"commands\":[{\"type\":\"command\",\"name\":\"serve\"" +
  label +
  "," +
  body +
  "}]}"
}

///|
/// 内部セル (DR-089 §3 `type: "none"` / DR-050 `type: "config_file"` / DR-093 §2 dd trigger) は
/// **結果 / 由来 / 効果のどれにも現れない**。除外は `result` / `sources` が露出キー軸
/// (`internal_cells`)、`effects` が宣言名軸 (`output_internal_cell`) と別々の席で行うので、
/// 3 面すべてを 1 本の pin で見る (1 面だけ見ると片面の regression を取り逃がす)。
///
/// scope ラベルの export_key 3 境界 — identity (`name` のみ) / renamed (`export_key: "sv"`) /
/// transparent (`export_key: null`) — で不変。席を宣言名のまま持っていた頃は renamed /
/// transparent で除外が外れ、`sv.touch` が result にも sources にも漏れていた。
test "front_door.output: none セルは scope rename の 3 境界すべてで 3 面から消える (DR-089 §3)" {
  let body =
    #|"options":[{"name":"touch","type":"none","long":true},
    #|           {"name":"keep","type":"flag","long":true,"export_key":"k"}]
  let args = ["serve", "--touch", "--keep"]
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, None), args),
    "result={serve={k=true}} sources={serve={k=cli}} effects=keep",
  )
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, Some("\"sv\"")), args),
    "result={sv={k=true}} sources={sv={k=cli}} effects=keep",
  )
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, Some("null")), args),
    "result={k=true} sources={k=cli} effects=keep",
  )
}

///|
/// 同上の `config_file` 版 (DR-050: 値は config provider を解決する PATH であって利用者向けの
/// 結果ではない)。`none` と違い engine の値空間なしセルではない (`Entity.is_config_file` の別軸)
/// ので、席の収集経路も別。
test "front_door.output: config_file セルは scope rename の 3 境界すべてで 3 面から消える (DR-050)" {
  let body =
    #|"options":[{"name":"cfg","type":"config_file","long":true,"default":"/app.toml"},
    #|           {"name":"keep","type":"flag","long":true}]
  let args = ["serve", "--keep"]
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, None), args),
    "result={serve={keep=true}} sources={serve={keep=cli}} effects=keep",
  )
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, Some("\"sv\"")), args),
    "result={sv={keep=true}} sources={sv={keep=cli}} effects=keep",
  )
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, Some("null")), args),
    "result={keep=true} sources={keep=cli} effects=keep",
  )
}

///|
/// 同上の dd trigger 版 (DR-093 §2/§7: `--` の trigger element は値空間を持たない)。dd trigger は
/// entity ではなく `greedy` 側のノードが運ぶので、`Scope.entities` の走査では席が拾えない。
test "front_door.output: dd trigger は scope rename の 3 境界すべてで 3 面から消える (DR-093 §2)" {
  let body =
    #|"options":[{"name":"--","type":"dd","export_key":"marker"}],
    #|"positionals":[{"name":"x","type":"string"}]
  let args = ["serve", "--", "-v"]
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, None), args),
    "result={serve={x=-v}} sources={serve={x=cli}} effects=x",
  )
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, Some("\"sv\"")), args),
    "result={sv={x=-v}} sources={sv={x=cli}} effects=x",
  )
  assert_eq(
    wbtest_view_of(wbtest_under_command(body, Some("null")), args),
    "result={x=-v} sources={x=cli} effects=x",
  )
}

///|
/// 内部セル除外の **値セル名軸** (上 3 本は scope ラベル軸)。`none` セル自身が `export_key` で
/// rename されている場合も除外が効く — `result` / `sources` 側の席を宣言名 (`touch`) のまま
/// 持つと露出キー (`t`) と食い違い、`t` が漏れる。
test "front_door.output: 値セル自身が rename された none も 3 面から消える (DR-089 §3 × DR-052 §1)" {
  let src =
    #|{"options":[{"name":"touch","type":"none","long":true,"export_key":"t"},
    #|            {"name":"keep","type":"flag","long":true}]}
  assert_eq(
    wbtest_view_of(src, ["--touch", "--keep"]),
    "result={keep=true} sources={keep=cli} effects=keep",
  )
}

///|
/// 内部セル除外の **非-command 結果スコープ軸**。`name` を持つ `seq` / `or` (DESIGN §2.3/§2.4) や
/// `repeat` (DR-043) が作る結果スコープの配下でも除外が効く。これらの値セルは `Scope.entities`
/// には**親スコープに平坦に**住み、結果スコープの段は Node 木の `Scoped` / `IndexedRepeat` だけが
/// 持つので、entity 走査だけでは席の path が付かず除外が外れていた (`command` 木しか降りて
/// いなかった頃は `pr.touch` / `grp.#0.touch` が 3 面すべてに漏れていた)。
///
/// `repeat` 配下は発火ごとに `grp/#0`, `grp/#1` … と別 path になるが、席は `grp` の 1 つ —
/// 照合前に index segment を落とすことで、どの発火でも同じ席に当たる。ただし **index segment
/// が結果面にどう出るか (出るか否かを含む) は spec 側の未裁定事項** (配列要素の provenance
/// addressing、`docs/issue/2026-07-26-array-element-provenance-sources-addressing.md`) なので、
/// この pin は `wbtest_view_keys_of` で席の集合だけを見て綴りに依存しない。
test "front_door.output: named seq / or / repeat 配下の none も 3 面から消える (DESIGN §2.3/§2.4, DR-043)" {
  let seq_renamed =
    #|{"options":[{"name":"pair","export_key":"pr","long":true,"seq":[
    #|  {"name":"touch","type":"none"},{"name":"keep","type":"string"}]}]}
  assert_eq(
    wbtest_view_of(seq_renamed, ["--pair", "x", "y"]),
    "result={pr={keep=y}} sources={pr={keep=cli}} effects=keep",
  )
  let seq_identity =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"name":"touch","type":"none"},{"name":"keep","type":"string"}]}]}
  assert_eq(
    wbtest_view_of(seq_identity, ["--pair", "x", "y"]),
    "result={pair={keep=y}} sources={pair={keep=cli}} effects=keep",
  )
  // or の枝が seq を持つ形 (枝 leaf は nameless 同化で `mode` 直下へ昇格、DR-052 §2)。
  let or_seq =
    #|{"options":[{"name":"mode","long":true,"or":[
    #|  {"name":"pair","seq":[{"name":"touch","type":"none"},{"name":"keep","type":"string"}]},
    #|  {"name":"num","type":"int"}]}]}
  assert_eq(
    wbtest_view_of(or_seq, ["--mode", "a", "b"]),
    "result={mode={keep=b}} sources={mode={keep=cli}} effects=keep",
  )
  // `repeat` 配下は sources の path に index segment が現れるが、その綴りは未裁定 (下記) なので
  // 席の集合だけを見る。
  let repeat =
    #|{"positionals":[{"name":"grp","repeat":{"min":1,"max":2},"positionals":[
    #|  {"name":"touch","type":"none"},{"name":"gflag","type":"string"}]}]}
  assert_eq(
    wbtest_view_keys_of(repeat, ["a", "b"]),
    "result={grp=[{gflag=b}]} source-keys=gflag effects=gflag",
  )
}

///|
/// accumulator の各 row は、その発火で選ばれた or 枝だけを持つ。別枝の repeat セルは
/// 宣言上 accumulator でも、成立しなかった row へ暗黙の空配列席を作らない。
test "front_door.output: accumulator の or row は選択枝だけを持つ (DR-051 / DR-122 §2)" {
  let src =
    #|{"options":[{"name":"sel","long":true,"multiple":"append","or":[
    #|  {"name":"nums","type":"number","repeat":{"min":1}},
    #|  {"name":"word","type":"string"}]}]}
  assert_eq(
    wbtest_view_of(src, ["--sel", "1", "2", "--sel", "foo"]),
    "result={sel=[{nums=[1,2]},{word=foo}]} sources={sel=[{nums=[cli,cli]},{word=cli}]} effects=nums,nums,word",
  )
}

///|
/// inline seq と ref は同じ構造の別表記であり、repeat 宣言子は発火回数にかかわらず行配列を作る。
/// none 子は照合消費だけを担い、各 row の effects / result / sources には席を持たない。
test "front_door.output: repeat inline seq builds rows and excludes none cells" {
  let src =
    #|{"commands":[{"type":"command","name":"rows","options":[
    #|  {"name":"pair","long":true,"repeat":{"min":1},"seq":[
    #|    {"name":"touch","type":"none"},{"name":"keep","type":"string"}]}]}]}
  assert_eq(
    wbtest_view_of(src, ["rows", "--pair", "x", "a", "y", "b"]),
    "result={rows={pair=[{keep=a},{keep=b}]}} sources={rows={pair=[{keep=cli},{keep=cli}]}} effects=keep,keep",
  )
  assert_eq(
    wbtest_view_of(src, ["rows", "--pair", "x", "a"]),
    "result={rows={pair=[{keep=a}]}} sources={rows={pair=[{keep=cli}]}} effects=keep",
  )
}

///|
/// accum セルの default 席 (DR-044 uniform array: 未発火でも `[]` を持つので `sources` にも席が
/// 要る) は、**0 回発火のときだけ**足す。判定は値がどこに着席するかで 2 通りに分かれる:
/// スカラ accum は cell 自身、`name` 付き `seq` / `or` の accum は cell が作る結果スコープの
/// **child** に着く。後者を「cell address に entry が無い = 0 fire」と読むと、値が入っていても
/// `"pair": "default"` を報告してしまう (事実として誤り)。
///
/// 3 構造 (named seq / named or / nested command のスカラ) × 0 / 1 / 2 fire で pin する。
/// 発火済み wrapper 自身に何を報告するかは spec 側の未裁定事項なので、ここでは席を足さない
/// (child の entry だけが語る) 挙動を固定する。
test "front_door.output: accum セルの default 席は 0 回発火のときだけ (DR-044)" {
  let seq =
    #|{"options":[{"name":"pair","long":true,"multiple":"append","seq":[
    #|  {"name":"path","type":"string"},{"name":"value","type":"string"}]}]}
  assert_eq(
    wbtest_view_of(seq, []),
    "result={pair=[]} sources={pair=[]} effects=",
  )
  assert_eq(
    wbtest_view_of(seq, ["--pair", "x", "1"]),
    "result={pair=[{path=x,value=1}]} sources={pair=[{path=cli,value=cli}]} effects=path,value",
  )
  assert_eq(
    wbtest_view_of(seq, ["--pair", "x", "1", "--pair", "y", "2"]),
    "result={pair=[{path=x,value=1},{path=y,value=2}]} sources={pair=[{path=cli,value=cli},{path=cli,value=cli}]} effects=path,path,value,value",
  )
  // 枝は int/bool で値空間が排他 (完全経路ちょうど 1 本)。
  let or_ =
    #|{"options":[{"name":"color","long":true,"multiple":"append","or":[
    #|  {"name":"num","type":"int"},{"name":"flag","type":"bool"}]}]}
  assert_eq(
    wbtest_view_of(or_, []),
    "result={color=[]} sources={color=[]} effects=",
  )
  assert_eq(
    wbtest_view_of(or_, ["--color", "7"]),
    "result={color=[{num=7}]} sources={color=[{num=cli}]} effects=num",
  )
  assert_eq(
    wbtest_view_of(or_, ["--color", "7", "--color", "true"]),
    "result={color=[{num=7},{flag=true}]} sources={color=[{num=cli},{flag=cli}]} effects=flag,num",
  )
  // 対照: スカラ accum は cell 自身に着席するので、従来どおり cell address の entry で判定できる。
  let scalar =
    #|{"commands":[{"type":"command","name":"serve","options":[
    #|  {"name":"t","type":"string","long":true,"multiple":"append"}]}]}
  assert_eq(
    wbtest_view_of(scalar, ["serve"]),
    "result={serve={t=[]}} sources={serve={t=[]}} effects=",
  )
  assert_eq(
    wbtest_view_of(scalar, ["serve", "--t", "a"]),
    "result={serve={t=[a]}} sources={serve={t=[cli]}} effects=t",
  )
  assert_eq(
    wbtest_view_of(scalar, ["serve", "--t", "a", "--t", "b"]),
    "result={serve={t=[a,b]}} sources={serve={t=[cli,cli]}} effects=t,t",
  )
}

///|
/// named group の child default は、発火した row の wrapper 配下でだけ解決する。
/// 0 fire では child の席自体が存在せず、DR-044 の wrapper accumulator 席だけが `[]` を供給する。
/// row が発火した後は default 宣言を持つ child を空席のまま完全経路へ含め、resolve 相で充填する。
test "front_door.output: named group child default は wrapper 外へ漏れない (DR-051 / DR-122 §3)" {
  let src =
    #|{"positionals":[{"name":"xs","repeat":{"min":0,"max":2},"positionals":[
    #|  {"name":"k","type":"string"},{"name":"v","type":"string","default":"D"}]}]}
  assert_eq(wbtest_view_of(src, []), "result={xs=[]} sources={xs=[]} effects=")
  assert_eq(
    wbtest_view_of(src, ["a", "b"]),
    "result={xs=[{k=a,v=b}]} sources={xs=[{k=cli,v=cli}]} effects=k,v",
  )
  assert_eq(
    wbtest_view_of(src, ["a", "b", "c", "d"]),
    "result={xs=[{k=a,v=b},{k=c,v=d}]} sources={xs=[{k=cli,v=cli},{k=cli,v=cli}]} effects=k,k,v,v",
  )
  assert_eq(
    wbtest_view_of(src, ["a"]),
    "result={xs=[{k=a,v=D}]} sources={xs=[{k=cli,v=default}]} effects=k",
  )
  // bool/flag defaults also feed build_result's default-cell projection; they must obey the same
  // declaration scope gate instead of being injected at root when the group has no row.
  let bool_child =
    #|{"positionals":[{"name":"xs","repeat":{"min":0,"max":1},"positionals":[
    #|  {"name":"k","type":"string"},{"name":"b","type":"bool","default":true}]}]}
  assert_eq(
    wbtest_view_of(bool_child, []),
    "result={xs=[]} sources={xs=[]} effects=",
  )
  assert_eq(
    wbtest_view_of(bool_child, ["a", "false"]),
    "result={xs=[{b=false,k=a}]} sources={xs=[{b=cli,k=cli}]} effects=b,k",
  )
  // The row path can use the child default, but it is incomplete when the required trailing positional
  // is left empty; the competing zero-row path therefore leaves the token for `tail`.
  let trailing =
    #|{"positionals":[
    #|  {"name":"xs","repeat":{"min":0,"max":2},"positionals":[
    #|    {"name":"k","type":"string"},{"name":"v","type":"string","default":"D"}]},
    #|  {"name":"tail","type":"string"}]}
  assert_eq(
    wbtest_view_of(trailing, ["a"]),
    "result={tail=a,xs=[]} sources={tail=cli,xs=[]} effects=tail",
  )
}

///|
/// Each structural option firing owns an independent child default seat; resolving one occurrence must
/// not deduplicate another row at the same wrapper scope.
test "front_door.output: multiple seq rows resolve child defaults independently" {
  let src =
    #|{"options":[{"name":"pair","long":true,"multiple":"append","seq":[
    #|  {"name":"k","type":"string"},{"name":"v","type":"string","default":"D"}]}]}
  assert_eq(
    wbtest_view_of(src, ["--pair", "a", "--pair", "b"]),
    "result={pair=[{k=a,v=D},{k=b,v=D}]} sources={pair=[{k=cli,v=default},{k=cli,v=default}]} effects=k,k",
  )
}

///|
/// DR-043 zero-progress is checked against the actual structural child head, including the empty seat
/// path introduced by a default-bearing child.
test "front_door.parse_definition: repeat with a default-only structural head is ZeroProgress" {
  let src =
    #|{"positionals":[{"name":"xs","repeat":{"min":0,"max":2},"or":[
    #|  {"name":"v","type":"string","default":"D"}]}]}
  match parse_definition(@json.parse(src)) {
    Err(Rejected(errors)) => {
      let mut found = false
      for error in errors {
        if error.element == "xs" && error.kind == @abi.ZeroProgress {
          found = true
        }
      }
      if !found {
        fail("expected ZeroProgress, got: " + deferrs_str(errors))
      }
    }
    Ok(_) => fail("default-only repeated structural head was accepted")
    Err(Malformed(message)) =>
      fail("unexpected malformed definition: " + message)
  }
  let progresses =
    #|{"positionals":[{"name":"xs","repeat":{"min":0,"max":2},"positionals":[
    #|  {"name":"a","type":"string","default":"A"},
    #|  {"name":"b","type":"string"}]}]}
  match parse_definition(@json.parse(progresses)) {
    Ok(_) => ()
    Err(_) => fail("a required sibling makes every repeated row progress")
  }
}

///|
/// 保証 (DR-122 §3 / CONFORMANCE §2): nameless 子だけを持つ `seq` accumulator は、result の
/// row/tuple 配列と同じ位置に各要素の source を置く。0 fire は空配列、CLI 値は `cli`、消費 0
/// literal は `const` になる。0 / 1 / 2 fire、rename、別 wrapper との同居を固定する。
test "front_door.output: nameless seq accumulator reports each row element source (DR-122 §3)" {
  let pair =
    #|{"options":[{"name":"pair","long":true,"multiple":"append","seq":[
    #|  {"type":"string"},{"type":"string"}]}]}
  assert_eq(
    wbtest_view_of(pair, []),
    "result={pair=[]} sources={pair=[]} effects=",
  )
  assert_eq(
    wbtest_view_of(pair, ["--pair", "a", "b"]),
    "result={pair=[[a,b]]} sources={pair=[[cli,cli]]} effects=",
  )
  assert_eq(
    wbtest_view_of(pair, ["--pair", "a", "b", "--pair", "c", "d"]),
    "result={pair=[[a,b],[c,d]]} sources={pair=[[cli,cli],[cli,cli]]} effects=",
  )
  let with_literal =
    #|{"options":[{"name":"pair","long":true,"multiple":"append","seq":[
    #|  {"type":"string"},{"type":"string","value":"fallback"}]}]}
  assert_eq(
    wbtest_view_of(with_literal, ["--pair", "x"]),
    "result={pair=[[x,fallback]]} sources={pair=[[cli,const]]} effects=",
  )
  // `#row` の宣言 scope は result と同じ export-key 軸へ写してから wrapper 席と照合する。
  let renamed =
    #|{"options":[{"name":"pair","export_key":"pr","long":true,"multiple":"append","seq":[
    #|  {"type":"string"},{"type":"string"}]}]}
  assert_eq(
    wbtest_view_of(renamed, ["--pair", "a", "b"]),
    "result={pr=[[a,b]]} sources={pr=[[cli,cli]]} effects=",
  )
  // 外側 command と wrapper の両段を rename しても、source path は result の露出アドレスと一致する。
  let nested =
    #|{"commands":[{"type":"command","name":"serve","export_key":"sv","options":[
    #|  {"name":"pair","export_key":"pr","long":true,"multiple":"append","seq":[
    #|    {"type":"string"},{"type":"string"}]}]}]}
  assert_eq(
    wbtest_view_of(nested, ["serve", "--pair", "a", "b"]),
    "result={sv={pr=[[a,b]]}} sources={sv={pr=[[cli,cli]]}} effects=",
  )
  // ref+repeat も行境界に `#row` を使う。別 wrapper の marker を誤って pair の発火と数えない。
  let repeat_sibling =
    #|{"definitions":{"templates":{"color":{"or":[
    #|  {"type":"string","name":"colorname"}]}}},"options":[
    #|  {"name":"pair","long":true,"multiple":"append","seq":[
    #|    {"type":"string"},{"type":"string"}]},
    #|  {"name":"hlcolors","ref":"color","repeat":{"min":0},"long":true}
    #|]}
  assert_eq(
    wbtest_view_of(repeat_sibling, ["--hlcolors", "red", "blue"]),
    "result={hlcolors=[{colorname=red},{colorname=blue}],pair=[]} sources={hlcolors=[{colorname=cli},{colorname=cli}],pair=[]} effects=colorname,colorname",
  )
}

///|
/// DESIGN §5.2: child `value:` は消費 0 const、child `default:` は通常消費を保つ ladder seat。
/// 1 token のとき result は同形でも、余剰 token を引き取れるのは default 形だけである。
test "front_door.output: seq child value const と default ladder は消費位相が異なる (DESIGN §5.2)" {
  let value_form =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"type":"string"},{"type":"string","value":"fallback"}]}]}
  let default_form =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"type":"string"},{"type":"string","default":"fallback"}]}]}
  assert_eq(
    wbtest_result_of(value_form, ["--pair", "x"]),
    "{pair=[x,fallback]}",
  )
  assert_eq(
    wbtest_view_of(default_form, ["--pair", "x"]),
    "result={pair=[x,fallback]} sources={pair=[cli,default]} effects=",
  )
  match parse_legacy(load_definition(value_form), ["--pair", "x", "y"]) {
    @engine.Success(_) =>
      fail("value const must not consume the trailing token")
    _ => ()
  }
  assert_eq(
    wbtest_view_of(default_form, ["--pair", "x", "y"]),
    "result={pair=[x,y]} sources={pair=[cli,cli]} effects=",
  )
}

///|
/// 複数の child default seat は完全経路集合の事後比較ではなく、背骨順に消費か fallback かを確定する。
test "front_door.output: child default の先食いは背骨順に逐次確定する" {
  // 先の seat a は x を消費して downstream 完全経路へ届くため cli で確定する。次の seat b は
  // y を消費すると必須 tail を飢えさせるため空席へ fallback し、tail が y を消費する。
  let sequential =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"name":"a","type":"string","default":"A"},
    #|  {"name":"b","type":"string","default":"B"}]}],
    #|"positionals":[{"name":"tail","type":"string"}]}
  assert_eq(
    wbtest_view_of(sequential, ["--pair", "x", "y"]),
    "result={pair={a=x,b=B},tail=y} sources={pair={a=cli,b=default},tail=cli} effects=a,tail",
  )
}

///|
test "front_door.output: option ref repeat child default sees trailing positional" {
  // GreedyRepeat's option satellite must not close its throwaway repeat scope before the referenced
  // row's child default consults the real outer tail. The row takes k=a, v defaults, and tail takes b.
  let src =
    #|{"definitions":{"templates":{"row":{"seq":[
    #|  {"name":"k","type":"string"},
    #|  {"name":"v","type":"string","default":"D"}]}}},
    #|"options":[{"name":"rows","long":true,"ref":"row","repeat":{"min":0}}],
    #|"positionals":[{"name":"tail","type":"string"}]}
  match parse_legacy(load_definition(src), ["--rows", "a", "b"]) {
    @engine.Success(bindings) => {
      let mut defaulted = false
      let mut tail_kept = false
      let mut child_consumed_tail = false
      for binding in bindings {
        if binding.key.length() >= 6 && binding.key[0:6].to_owned() == "#seat:" {
          defaulted = true
        }
        if binding.key == "tail" && binding.value == @abi.String("b") {
          tail_kept = true
        }
        if binding.key == "v" && binding.value == @abi.String("b") {
          child_consumed_tail = true
        }
      }
      assert_true(defaulted)
      assert_true(tail_kept)
      assert_false(child_consumed_tail)
    }
    other =>
      fail(
        "option ref repeat must default its child before the outer tail: " +
        render_outcome(other),
      )
  }
}

///|
/// 型がトークンを認識した後の値不正は Held Error のまま残り、default fallback を生成しない。
test "front_door.parse: child default の消費 Held は fallback で握り潰さない" {
  // int seat が number として認識した非整数 2.5 は Held Error であり、n=0 の空席枝を立てて
  // 2.5 を rest へ送る Reject/fallback 経路には読み替えない。
  let src =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"name":"k","type":"string"},
    #|  {"name":"n","type":"int","default":0}]}],
    #|"positionals":[{"name":"rest","type":"string","repeat":{"min":0}}]}
  let ast = load_definition(src)
  match parse_legacy(ast, ["--pair", "x", "2.5"]) {
    @engine.Failure(failure) => {
      let mut found = false
      for error in failure.errors {
        if error.element == "n" &&
          error.args_pos == 2 &&
          error.reason == "not_an_integer" {
          found = true
        }
      }
      assert_true(found)
    }
    other =>
      fail(
        "a held int error must not fall back to the child default seat: " +
        render_outcome(other),
      )
  }
}

///|
/// Child defaults use the same typed default pipeline as root cells, including parse failures and
/// scalar-array shape validation.
test "front_door.output: structural child defaults preserve type and shape validation" {
  let invalid_value =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"type":"string"},{"name":"n","type":"int","default":"bad"}]}]}
  let ast = load_definition(invalid_value)
  let args = ["--pair", "x"]
  match resolve_legacy(ast, parse_legacy(ast, args), args) {
    @engine.Failure(_) => ()
    _ => fail("an invalid int child default must fail during resolve")
  }
  let invalid_shape =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"type":"string"},{"name":"n","type":"int","default":[1,2]}]}]}
  match parse_definition(@json.parse(invalid_shape)) {
    Err(Rejected(errors)) => {
      let mut found = false
      for error in errors {
        if error.element == "n" && error.kind == @abi.InvalidRange {
          found = true
        }
      }
      assert_true(found)
    }
    _ => fail("an array default on a scalar child must be InvalidRange")
  }
}

///|
/// 保証 (DESIGN §2.5 / DR-120 / DR-122 §2): 結果キーを持つ子 (`name` 付き) の消費 0 literal は
/// kv 経路に乗り、自分のセルを持つので `sources` に `const` の entry が出る (DR-031 の 8 語彙目 —
/// 「const は値セルに最初からいる。default は無い時に埋める」。literal は充填でなく宣言定数)。
/// 同じ `seq` の中で cli 消費の子と宣言定数の子が別タグで並ぶ。
test "front_door.output: named seq 子の消費 0 literal は kv セルとして const の由来を持つ (DR-031 / DR-122 §3)" {
  let src =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"name":"path","type":"string"},
    #|  {"name":"mode","type":"string","value":"fallback"}]}]}
  assert_eq(
    wbtest_view_of(src, ["--pair", "x"]),
    "result={pair={mode=fallback,path=x}} sources={pair={mode=const,path=cli}} effects=path",
  )
}

///|
/// 保証 (CONFORMANCE §2 の導出手順 / DR-052 §3): **選ばれなかった `or` 枝の literal は着席しない**。
/// `sources` は `result` の射影であり、選ばれなかった枝は result に現れない以上 sources にも
/// 現れない。消費 0 であることは「常に発火する」ことを意味しない — 枝の選択は or の構造が決める。
test "front_door.output: from_entries carries each surviving value source through key promotion" {
  let src =
    #|{"options":[{"name":"entries","long":true,
    #| "multiple":{"accumulator":"append","collector":{"from_entries":"entries"}},
    #| "seq":[{"type":"string"},{"type":"string"}]}]}
  assert_eq(
    wbtest_view_of(src, ["--entries", "a", "1", "--entries", "b", "2"]),
    "result={entries={a=1,b=2}} sources={entries={a=cli,b=cli}} effects=",
  )
}

///|
test "front_door.output: kv_map last-wins keeps the winning entry source" {
  let src =
    #|{"options":[
    #| {"name":"define","type":"string","long":true,
    #|  "multiple":{"accumulator":"kv_map"}},
    #| {"name":"legacy","type":"string","long":true,"link":"define"}]}
  assert_eq(
    wbtest_view_of(src, [
      "--define", "A=first", "--define", "B=second", "--legacy", "A=linked",
    ]),
    "result={define={A=linked,B=second}} sources={define={A=link,B=cli}} effects=define,define,define",
  )
}

///|
test "front_door.output: unique removes the duplicate value and its source together" {
  let src =
    #|{"options":[
    #| {"name":"tag","type":"string","long":true,"multiple":"append",
    #|  "accum_filters":["unique"]},
    #| {"name":"legacy","type":"string","long":true,"link":"tag"}]}
  assert_eq(
    wbtest_view_of(src, ["--legacy", "a", "--tag", "a", "--legacy", "b"]),
    "result={tag=[a,b]} sources={tag=[link,link]} effects=tag,tag,tag",
  )
}

///|
test "front_door.output: 未選択の or 枝が持つ default seat は result にも sources にも現れない (DR-052 §3)" {
  let src =
    #|{"options":[{"name":"mode","long":true,"or":[
    #|  {"name":"fast","type":"string"},
    #|  {"name":"slow","type":"int","default":7}]}]}
  assert_eq(
    wbtest_view_of(src, ["--mode", "x"]),
    "result={mode={fast=x}} sources={mode={fast=cli}} effects=fast",
  )
  let anonymous =
    #|{"positionals":[{"or":[
    #|  {"name":"fast","type":"bool"},
    #|  {"name":"slow","type":"int","default":7}]}]}
  assert_eq(
    wbtest_view_of(anonymous, ["true"]),
    "result={fast=true} sources={fast=cli} effects=fast",
  )
}

///|
/// Two default-only or branches produce distinct observable seat effects, so DR-038 keeps both complete
/// paths and reports ambiguity rather than merging their defaults into one result.
test "front_door.output: default-only or branches remain ambiguous" {
  let src =
    #|{"options":[{"name":"mode","long":true,"or":[
    #|  {"name":"a","type":"int","default":1},
    #|  {"name":"b","type":"int","default":2}]}]}
  match parse_legacy(load_definition(src), ["--mode"]) {
    @engine.Ambiguous(data) => assert_eq(data.interpretations.length(), 2)
    _ => fail("two default-only branches must remain ambiguous")
  }
}

///|
/// 保証 (対極、`dec_or_leaf` の allowed_keys): 構造子の子が受け付けるのは `value` / `default` まで。
/// 未対応キーは黙って捨てず `malformed_definition` を返す — decode を通して lowering で無視すると
/// 「書けたのに効かない」silent wrong answer になる。`default_fn:` を含むのは意図的で、遅延評価の
/// invocation は lowering 時点で値が確定せず消費 0 literal に落とせないため (別 issue)。
test "front_door: 構造子の子の未対応キーは malformed_definition のまま (value/default だけを開けた)" {
  for key in ["env", "long", "default_fn", "multiple"] {
    let src = "{\"options\":[{\"name\":\"pair\",\"long\":true,\"seq\":[" +
      "{\"type\":\"string\"},{\"type\":\"string\",\"" +
      key +
      "\":\"x\"}]}]}"
    match parse_definition(@json.parse(src)) {
      Ok(_) =>
        fail(
          "構造子の子の未対応キー '" +
          key +
          "' は弾かれるべき",
        )
      Err(_) => ()
    }
  }
  // `value:` と `default:` は別位相なので同居でき、const が常に default を影にする。
  let both =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"type":"string"},{"type":"string","value":"a","default":"b"}]}]}
  assert_eq(
    wbtest_view_of(both, ["--pair", "x"]),
    "result={pair=[x,a]} sources={pair=[cli,const]} effects=",
  )
}

///|
/// `wbtest_view_of` の result だけを見る版 (sources の要素ごと addressing が未裁定な形を
/// 扱うため — DR-122 §3)。
fn wbtest_result_of(src : String, args : Array[String]) -> String raise {
  let ast = load_definition(src)
  let parsed = parse_legacy(ast, args)
  match resolve_legacy(ast, parsed, args) {
    @engine.Success(bindings) =>
      render_rval_sorted(output_legacy(ast, effects=bindings).result)
    other => {
      fail("should resolve, got " + render_outcome(other))
      panic()
    }
  }
}

///|
fn load_definition(src : String) -> AtomicAST raise {
  match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => {
      fail("parse_definition should accept the definition")
      panic()
    }
  }
}

///|
/// 保証 (DESIGN §5.2 × DR-096 §3.3 の `=` 形): `=` の右辺が渡る先は「最初に**消費する**子」で
/// あって「最初の子」ではない。消費 0 literal が先頭に並んでいてもトークンを取らないので、
/// eq entry はその次の消費する子が担う。**space 形と `=` 形で結果が割れない**ことが要点
/// (両形が同じ消費文法の別の書き口である以上、literal の位置で結果形が変わってはいけない)。
test "front_door: seq 先頭の消費 0 literal は `=` 形の値スロットを奪わない (DESIGN §5.2 / DR-096)" {
  let named_first_literal =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"name":"mode","type":"string","value":"L"},
    #|  {"name":"path","type":"string"}]}]}
  let named_want = "{pair={mode=L,path=x}}"
  assert_eq(wbtest_result_of(named_first_literal, ["--pair", "x"]), named_want)
  assert_eq(wbtest_result_of(named_first_literal, ["--pair=x"]), named_want)
  // nameless (配列形) でも同じ — 子の順序は宣言順のまま保たれる。
  let anon_first_literal =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"type":"string","value":"L"},{"type":"string"}]}]}
  assert_eq(
    wbtest_result_of(anon_first_literal, ["--pair", "x"]),
    "{pair=[L,x]}",
  )
  assert_eq(wbtest_result_of(anon_first_literal, ["--pair=x"]), "{pair=[L,x]}")
  // 対極: 全ての子が消費 0 literal なら `=` 形は成立しない (右辺 `x` の行き場が無い)。
  // space 形だけが配線され、宣言値がそのまま出る。
  let all_literal =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"name":"a","type":"string","value":"A"},
    #|  {"name":"b","type":"string","value":"B"}]}]}
  assert_eq(wbtest_result_of(all_literal, ["--pair"]), "{pair={a=A,b=B}}")
  match parse_legacy(load_definition(all_literal), ["--pair=x"]) {
    @engine.Success(_) =>
      fail("全子が消費 0 なら `=` 右辺を受け取る子が無い")
    _ => ()
  }
}

///|
/// ref template 内で隣接する child repeat も、大域の後続 positional を含む完全経路で
/// greedy share を確定し、複数の完全経路を ambiguous として残さない。
test "ref-template child repeats honor global greedy share under an outer repeat" {
  let src =
    #|{"definitions":{"templates":{"pair":{"seq":[
    #|  {"name":"xs","type":"string","repeat":{"min":1}},
    #|  {"name":"ys","type":"string","repeat":{"min":1}}
    #|]}}},"positionals":[
    #|  {"name":"rows","ref":"pair","repeat":{"min":1}},
    #|  {"exact":"END"}
    #|]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(value) => value
    Err(_) => abort("expected ref-template repeat definition to lower")
  }
  match parse_legacy(ast, ["a", "b", "c", "END"]) {
    @engine.Success(bindings) => {
      let mut xs = 0
      let mut ys = 0
      for binding in bindings {
        if binding.key == "xs" {
          xs = xs + 1
        }
        if binding.key == "ys" {
          ys = ys + 1
        }
      }
      assert_eq(xs, 2)
      assert_eq(ys, 1)
    }
    other =>
      fail("expected one preferred complete path, got " + render_outcome(other))
  }
}

///|
/// An explicitly empty default still selects the repeated child cell; zero pieces is an array value,
/// not absence of the selected seat.
test "DR-123: selected child repeat preserves an explicitly empty default" {
  let src =
    #|{"positionals":[{"name":"pair","seq":[
    #|  {"name":"head","type":"string"},
    #|  {"name":"tags","type":"string","repeat":{"min":0},"default":[]}
    #|]}]}
  assert_eq(
    wbtest_view_of(src, ["a"]),
    "result={pair={head=a,tags=[]}} sources={pair={head=cli,tags=[]}} effects=head",
  )
}

///|
/// A repeat default belongs only to a selected structural branch. Rejecting that branch must not
/// materialize either its declared default or the repeat cell's implicit empty array.
test "DR-123: an unselected or branch repeat default remains absent" {
  let src =
    #|{"positionals":[{"or":[
    #|  {"name":"fast","type":"string"},
    #|  {"name":"tags","type":"int","repeat":{"min":0},"default":[1]}
    #|]}]}
  let view = wbtest_view_of(src, ["x"])
  assert_false(view.contains("tags"))
  assert_true(view.contains("fast"))
}
