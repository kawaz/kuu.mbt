// front_door_wbtest.mbt — MDR-005 §正面玄関 3 契約の意味論 pin (issue 2026-07-15
// front-door-parse-missing-postprocessing の受け入れ条件)。conformance runner の乗り換えだけでは
// front_door.parse / front_door.resolve の**呼び出し側から見える契約**を直接固定できない —
// kuu-cli PoC dogfooding が発見した「front_door.parse が薄い @engine.parse_tree wrapper のまま spec 非
// 準拠 outcome を返す」実バグの根治として、玄関 API のシグネチャに沿った 3 本の pin を残す:
//
// 1. export-key 衝突 (DR-021 → DR-073): 同一入力で 2 要素が同じ export_key に共露出したとき、
//    front_door.parse は @engine.Success ではなく @engine.Ambiguous を返す (`promote_collision_ambiguous` の
//    parse 内包)
// 2. inheritable resolve (DR-059 §5 / DR-047 §4): 祖先 write-target で書かれた値が子 scope の
//    inherit 席に流下する。front_door.resolve が返す binds に子 scope 側の解決済み値 (source=
//    @engine.Inherit) が現れる
// 3. deprecated warnings (DR-058 §2): deprecated:true の alias 入口を発火した @engine.Success outcome
//    から `@engine.warnings_structured` が `{element, kind}` の構造化 warning を返す。sentinel
//    `@depr:...` は effects (非 sentinel binds) に混じらない (`is_sentinel` で除外可能)
//
// 期待値の根拠は kawaz/kuu の fixtures (`export-key/collision.json` /
// `inheritable-parse/basic.json` / `alias-parse/deprecated.json`) の該当 case と一致し、
// conformance runner が実際にその期待を満たしていることは `[json-conformance] mismatches=0` が
// 別途保証している — 本 wbtest は玄関 API の契約側からその 3 面を独立に固定する層。

///|
/// 保証 (MDR-005 §1 / DR-021 → DR-073 / DR-053 §3): front_door.parse は `@engine.parse_tree` の直接
/// 結果ではなく **`promote_collision_ambiguous` 込みの spec 準拠 @engine.Outcome** を返す。同一 args で
/// 2 flag (a / b) が共に export_key "x" へ露出する場合、raw `@engine.parse_tree` は @engine.Success を返すが、
/// 玄関 `parse` は @engine.Ambiguous に昇格し、各 interpretation が DR-073 §1 の claimants 面 (露出キー
/// "x" → 占める実体 name) を持つ。fixture 期待は 2 解釈 `{claimants: {"x":"a"}}` と
/// `{claimants: {"x":"b"}}` で、集合として比較する (順序非依存、DR-073 §3)。
test "front_door.parse: export-key 共露出は @engine.Ambiguous + claimants に昇格 (DR-021 → DR-073, MDR-005 §1)" {
  let src =
    #|{"options": [
    #|  {"name": "a", "type": "flag", "long": true, "export_key": "x"},
    #|  {"name": "b", "type": "flag", "long": true, "export_key": "x"}
    #|]}
  let j = @json.parse(src)
  let ast = match parse_definition(j) {
    Ok(a) => a
    Err(_) => {
      fail("parse_definition failed")
      panic()
    }
  }
  // raw `@engine.parse_tree` は @engine.Success を返す (parse 段は共露出を検知しない)。この対比は「front_door.parse
  // が薄い wrapper のままだった旧実装での不具合再現」の pin として、期待外れの @engine.Ambiguous 昇格が
  // @engine.parse_tree 側で先に起きていないことも同時に確認する。
  let raw = @engine.parse_tree(
    @engine.ScopeNode(ast.root),
    ["--a", "--b"],
    defs=ast.templates,
  )
  match raw {
    @engine.Success(_) => ()
    other =>
      fail(
        "raw @engine.parse_tree should still succeed pre-promotion, got " +
        render_outcome(other),
      )
  }
  // 玄関 `parse` は promote_collision_ambiguous を内包するため @engine.Ambiguous を返す。
  let o = parse(ast, ["--a", "--b"])
  match o {
    @engine.Ambiguous(d) => {
      assert_eq(d.interpretations.length(), 2)
      // 各 interpretation の claimants に露出キー "x" → 実体 name の写像が1件だけ載る (DR-073 §1)。
      // 並び順は不定なので、a と b の 2 名がちょうど 1 度ずつ現れることをセットとして確認する。
      let mut have_a = false
      let mut have_b = false
      for interp in d.interpretations {
        assert_eq(interp.claimants.length(), 1)
        let (key, holder) = interp.claimants[0]
        assert_eq(key, "x")
        if holder == "a" {
          have_a = true
        }
        if holder == "b" {
          have_b = true
        }
      }
      assert_true(have_a)
      assert_true(have_b)
    }
    other =>
      fail(
        "front_door.parse should promote to @engine.Ambiguous, got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (MDR-005 §1 / DR-059 §5 / DR-047 §4): front_door.resolve は値源ラダー
/// (env/config/inherit/default) を子 scope まで再帰的に充填する。inheritable:true の子 scope
/// entity は、祖先で書かれた write-target 値を **`@engine.Inherit` source** の binding として得る (spec
/// fixture `inheritable-parse/basic.json` の `ancestor-inherit-flowdown` case: `--sub-ttl 30 sub`
/// で `sub.ttl = 30`, source=inherit)。ここでは玄関 API のみを叩き、結果 binds に:
///   - root path=[] に ttl 値 30 with source=@engine.Cli (`--sub-ttl` 発火の write-target)
///   - 子 path=["sub"] に ttl 値 30 with source=@engine.Inherit (親から流下した inherit 席)
/// の 2 面が現れることを固定する。front_door.parse (単独) では resolve 相未実行なので子 scope の
/// ttl は binds に現れず、玄関 `resolve` が明示的に必要になる = 相区分の 2 段構成 (MDR-005 §1)
/// が意味を持つ最小の証拠でもある。
test "front_door.resolve: inheritable が親 write-target → 子 scope の inherit 席へ流下 (DR-059 §5 / DR-047 §4, MDR-005 §1)" {
  let src =
    #|{"commands": [
    #|  {"type": "command", "name": "sub", "options": [
    #|    {"name": "ttl", "type": "number", "long": true, "inheritable": true, "default": 60}
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
  let args = ["--sub-ttl", "30", "sub"]
  let po = parse(ast, args)
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
  let ro = resolve(ast, po, args)
  match ro {
    @engine.Success(rb) => {
      // root path=[] の ttl (write-target への cli 発火)。
      let mut root_ttl : @engine.Value? = None
      let mut root_src : @engine.Source? = None
      // 子 path=["sub"] の ttl (親から流下した inherit 値)。
      let mut sub_ttl : @engine.Value? = None
      let mut sub_src : @engine.Source? = None
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
      assert_eq(root_ttl, Some(@engine.VNum(30.0)))
      assert_eq(root_src, Some(@engine.Cli))
      assert_eq(sub_ttl, Some(@engine.VNum(30.0)))
      assert_eq(sub_src, Some(@engine.Inherit))
    }
    other =>
      fail("front_door.resolve should succeed, got " + render_outcome(other))
  }
}

///|
/// 保証 (MDR-005 §1 / DR-058 §2): deprecated:true が付いた alias 入口の発火は、値の束縛 (canonical
/// セル `port` = 80) と並行して、@engine.Success outcome から `@engine.warnings_structured` が
/// `{element: "port", kind: "deprecated"}` を返す。同時に、`@depr:port` sentinel binding は
/// `is_sentinel` で除外可能 = kuu-cli 相当の呼び出し側が effects (非 sentinel binds のリスト) を
/// 組み立てるときに漏れない (kuu-cli PoC codex レビュー M-1 = warnings の構造化 + sentinel を
/// effects に漏らさないためのプロダクション pub 面を要件化)。
test "front_door.parse + @engine.warnings_structured: deprecated alias 発火は構造化 warning + effects から @depr sentinel 除外 (DR-058 §2, MDR-005 §1)" {
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
  let o = parse(ast, ["-o", "80"])
  match o {
    @engine.Success(binds) => {
      // port の値は 80、source=@engine.Cli (canonical セルへ普通に束縛される、DR-058 は受理不変)。
      let mut port_val : @engine.Value? = None
      for b in binds {
        if is_sentinel(b.key) {
          continue
        }
        if b.scope.length() == 0 && b.key == "port" {
          port_val = Some(b.value)
        }
      }
      assert_eq(port_val, Some(@engine.VNum(80.0)))
      // 構造化 warnings が `{element:"port", kind:"deprecated"}` の 1 件を返す。
      let ws = @engine.warnings_structured(o)
      assert_eq(ws, [{ element: "port", kind: "deprecated" }])
      // sentinel `@depr:port` は binds に含まれる (@engine.warnings_of/@engine.warnings_structured の素材) が、
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
    match parse(ast, args) {
      @engine.Success(binds) => output(ast, binds)
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
  assert_eq(normal.effects[0].op, @engine.Set)
  assert_eq(normal.effects[0].operand, Some(@engine.VNum(80.0)))
  assert_eq(normal.effects[0].source, @engine.Cli)

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
/// 済み出力に常に含める」/ §5 UX-Q5=a、MDR-005「射程外」節の解消): front_door の `result`/
/// `sources` が `resolve()` の @engine.Success payload だけから DR-052 result-key 軸適用済みの `result`
/// オブジェクトと DR-031 値源タグの `sources` を組み立てられる。単一 scope (command 木なし) では
/// export_key rename (`port` → `p`) と、未発火 flag の preset default (`verbose` = false、
/// LOWERING §A.5) の両方が result/sources 双方に反映される — runner 側の `proj_result_export`/
/// `proj_sources` が同じ入力に対して返す conformance 期待 (`{p=8080,verbose=false}` /
/// `p=cli,verbose=default`) と同型 (mismatches=0 は別途 conformance runner 側が保証)。
test "front_door.result/sources: 単一 scope で export_key rename + flag preset default (DR-052 §1 / LOWERING §A.5, MDR-005 射程外解消)" {
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
  let po = parse(ast, args)
  let ro = resolve(ast, po, args)
  let rb = match ro {
    @engine.Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let view = output(ast, rb)
  assert_eq(view.result, result(ast, rb))
  assert_eq(view.sources, sources(ast, rb))
  let rval = view.result
  match rval {
    @engine.RObj(kvs) => {
      let mut p_val : @engine.RVal? = None
      let mut verbose_val : @engine.RVal? = None
      for kv in kvs {
        if kv.0 == "p" {
          p_val = Some(kv.1)
        }
        if kv.0 == "verbose" {
          verbose_val = Some(kv.1)
        }
      }
      assert_eq(p_val, Some(@engine.RScalar(@engine.VNum(8080.0))))
      assert_eq(verbose_val, Some(@engine.RScalar(@engine.VBool(false))))
    }
    _ => fail("front_door.result should be @engine.RObj at root scope")
  }
  let ses = view.sources
  let mut p_src : @engine.Source? = None
  let mut verbose_src : @engine.Source? = None
  for se in ses {
    if se.key == "p" {
      p_src = Some(se.source)
    }
    if se.key == "verbose" {
      verbose_src = Some(se.source)
    }
  }
  assert_eq(p_src, Some(@engine.Cli))
  assert_eq(verbose_src, Some(@engine.Default))
}

///|
/// 保証 (issue 2026-07-16-result-projection-production-promotion、DR-109 §3): command 木を持つ
/// scope でも `front_door.sources` は**同一シグネチャ**のまま木全体の値源タグを返す — 呼び出し側は
/// command 木の有無 (`has_commands`) を一切意識しない (resolve.mbt `result_sources` のコメント
/// 参照、外部利用者にその分岐を意識させない 1 本の関数へ畳む設計)。子 scope "sub" で発火した
/// ttl の値源タグが `path: ["sub"], key: "ttl", source: @engine.Cli` として現れることを固定する。
test "front_door.sources: command 木を持つ scope でも 1 本のシグネチャで子 scope の値源を返す (DR-109 §3, MDR-005 射程外解消)" {
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
  let po = parse(ast, args)
  let ro = resolve(ast, po, args)
  let rb = match ro {
    @engine.Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let ses = sources(ast, rb)
  let mut found : SourceEntry? = None
  for se in ses {
    if se.key == "ttl" && se.path.length() == 1 && se.path[0] == "sub" {
      found = Some(se)
    }
  }
  match found {
    Some(se) => assert_eq(se.source, @engine.Cli)
    None => fail("expected a sub.ttl SourceEntry with path=[\"sub\"]")
  }
}

///|
/// 保証 (統括裁定「@engine.ConfigVal/TtyObs の入力構築 API」(b)、DR-050 §2/§4): 外部利用者が `@engine.ConfigVal`
/// の variant (`@engine.CObj`/`@engine.CArr` 含む) を直接構築できない (`pub` でフィールド/variant 非公開) 制約下で、
/// `config_from_json` が JSON から組んだ `@engine.ConfigVal` を `parse()`/`resolve()` の `config?` provider
/// 経由で実際に config 席へ流し込めることを e2e で固定する。`config_file` 型要素 + `config_key`
/// を持つ `port` の値が config 由来 (`8080`, source=config) で result/sources 双方に現れ、
/// `config_file` 要素自身はインフラなので結果に現れない (`piece-filters/config-source.json` の
/// 輪郭と同型)。
test "front_door.config_from_json: JSON から組んだ @engine.ConfigVal が config 席経由で result/sources に反映される (DR-050 §2/§4, @engine.ConfigVal/TtyObs 入力構築 API)" {
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
  // 利用者は自前で @engine.CObj を組めない — config_from_json に生 JSON を渡すだけで良い。
  let cfg_json = @json.parse(
    (
      #|{"port": 8080}
    ),
  )
  let cfg = config_from_json(cfg_json)
  let config_provider : (String) -> @engine.ConfigVal? = fn(_p) { Some(cfg) }
  let args : Array[String] = []
  let po = parse(ast, args, config=config_provider)
  let ro = resolve(ast, po, args, config=config_provider)
  let rb = match ro {
    @engine.Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let rval = result(ast, rb)
  match rval {
    @engine.RObj(kvs) => {
      let mut port_val : @engine.RVal? = None
      let mut has_config_key = false
      for kv in kvs {
        if kv.0 == "port" {
          port_val = Some(kv.1)
        }
        if kv.0 == "config" {
          has_config_key = true
        }
      }
      assert_eq(port_val, Some(@engine.RScalar(@engine.VNum(8080.0))))
      // config_file 要素自身はインフラで結果非掲載 (config-source.json の why 参照)。
      assert_false(has_config_key)
    }
    _ => fail("front_door.result should be @engine.RObj")
  }
  let ses = sources(ast, rb)
  let mut port_src : @engine.Source? = None
  for se in ses {
    if se.key == "port" {
      port_src = Some(se.source)
    }
  }
  assert_eq(port_src, Some(@engine.Config))
}

///|
/// 保証 (統括裁定「@engine.ConfigVal/TtyObs の入力構築 API」(b)、DR-099 §4): 外部利用者が `TtyObs` を
/// (フィールド非公開のため) 直接構築できない制約下で、`tty_obs(terminal, cygwin)` が組んだ値を
/// `parse()`/`resolve()` の `tty?` 引数経由で `builtin/tty` preset 型要素の default 席解決規則
/// (`fold(観測) ?? 宣言 default ?? absent`、`tty-ladder.json` と同型) に実際に流し込めることを
/// e2e で固定する。`{terminal: true, cygwin: false}` の観測は宣言 default (`false`) と異なる値
/// (`true`) を fold するので、observation が宣言 default に優先することも同時に確認できる。
test "front_door.tty_obs: 構築した TtyObs が tty 席経由で builtin/tty の default 解決規則に反映される (DR-099 §4, @engine.ConfigVal/TtyObs 入力構築 API)" {
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
  let po = parse(ast, args, tty=tty_map)
  let ro = resolve(ast, po, args, tty=tty_map)
  let rb = match ro {
    @engine.Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let rval = result(ast, rb)
  match rval {
    @engine.RObj(kvs) => {
      let mut use_color_val : @engine.RVal? = None
      for kv in kvs {
        if kv.0 == "use_color" {
          use_color_val = Some(kv.1)
        }
      }
      // 観測 terminal=true が宣言 default=false より優先する (DR-098 §5 の優先順位)。
      assert_eq(use_color_val, Some(@engine.RScalar(@engine.VBool(true))))
    }
    _ => fail("front_door.result should be @engine.RObj")
  }
  let ses = sources(ast, rb)
  let mut use_color_src : @engine.Source? = None
  for se in ses {
    if se.key == "use_color" {
      use_color_src = Some(se.source)
    }
  }
  assert_eq(use_color_src, Some(@engine.Tty))
}

///|
/// 保証 (issue front-door-resolve-ref-repeat-row-drop, K カテゴリ調査 2026-07-16): a ref-template
/// accum entity (`or` 枝 = seq(r,g,b) / string(colorname)、`multiple:"append"` + repeat) wraps its
/// own row bindings one scope level deeper than its declaring scope (`ref_row_head`/`@engine.Scoped(e.name,
/// ...)`, installer.mbt DR-078 §1) — `front_door.resolve` (= `resolve_scope_tree`) used to filter
/// "this scope's own bindings" by an EXACT scope-path match, which silently dropped that one-level-
/// deeper wrap (it is neither an exact-path binding nor a genuine `@engine.CmdSat` command child), so
/// `front_door.result` always rendered `[]` for a fired ref+repeat cell no matter how many times it
/// fired. `kawaz/kuu` fixture `multiple-parse/ref-rows-append.json` fixes this exact shape (spec の
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
  fn hlcolors_of(args : Array[String]) -> @engine.RVal raise {
    let po = parse(ast, args)
    let ro = resolve(ast, po, args)
    let rb = match ro {
      @engine.Success(b) => b
      other => {
        fail("front_door.resolve should succeed, got " + render_outcome(other))
        panic()
      }
    }
    // resolve が復元済みの #row/#fire を `output` は再 merge せず、その binds を result 射影へ渡す。
    let view = output(ast, rb)
    assert_eq(view.result, result(ast, rb))
    match view.result {
      @engine.RObj(kvs) => {
        for kv in kvs {
          if kv.0 == "hlcolors" {
            return kv.1
          }
        }
        fail("result should carry a \"hlcolors\" key")
        panic()
      }
      _ => {
        fail("front_door.result should be @engine.RObj at root scope")
        panic()
      }
    }
  }

  // zero-fires-empty: 0 発火でも accum cell は absent にならず `[]` (DR-044 uniform array)。
  assert_eq(hlcolors_of([]), @engine.RArr([]))
  // single-fire-list: 1 発火でも要素1件の配列 (scalar への unwrap をしない、DR-034)。
  assert_eq(
    hlcolors_of(["--hlcolors", "red"]),
    @engine.RArr([
      @engine.RObj([("colorname", @engine.RScalar(@engine.VStr("red")))]),
    ]),
  )
  // two-fires-branch-append: 2 発火 (or の異なる枝) は row をそのまま順に積む (枝の違いを畳まない)。
  assert_eq(
    hlcolors_of(["--hlcolors", "red", "--hlcolors", "0", "128", "255"]),
    @engine.RArr([
      @engine.RObj([("colorname", @engine.RScalar(@engine.VStr("red")))]),
      @engine.RObj([
        ("r", @engine.RScalar(@engine.VNum(0.0))),
        ("g", @engine.RScalar(@engine.VNum(128.0))),
        ("b", @engine.RScalar(@engine.VNum(255.0))),
      ]),
    ]),
  )
}
