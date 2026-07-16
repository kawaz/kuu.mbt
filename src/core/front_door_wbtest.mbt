// front_door_wbtest.mbt — MDR-005 §正面玄関 3 契約の意味論 pin (issue 2026-07-15
// front-door-parse-missing-postprocessing の受け入れ条件)。conformance runner の乗り換えだけでは
// front_door.parse / front_door.resolve の**呼び出し側から見える契約**を直接固定できない —
// kuu-cli PoC dogfooding が発見した「front_door.parse が薄い parse_tree wrapper のまま spec 非
// 準拠 outcome を返す」実バグの根治として、玄関 API のシグネチャに沿った 3 本の pin を残す:
//
// 1. export-key 衝突 (DR-021 → DR-073): 同一入力で 2 要素が同じ export_key に共露出したとき、
//    front_door.parse は Success ではなく Ambiguous を返す (`promote_collision_ambiguous` の
//    parse 内包)
// 2. inheritable resolve (DR-059 §5 / DR-047 §4): 祖先 write-target で書かれた値が子 scope の
//    inherit 席に流下する。front_door.resolve が返す binds に子 scope 側の解決済み値 (source=
//    Inherit) が現れる
// 3. deprecated warnings (DR-058 §2): deprecated:true の alias 入口を発火した Success outcome
//    から `warnings_structured` が `{element, kind}` の構造化 warning を返す。sentinel
//    `@depr:...` は effects (非 sentinel binds) に混じらない (`is_sentinel` で除外可能)
//
// 期待値の根拠は kawaz/kuu の fixtures (`export-key/collision.json` /
// `inheritable-parse/basic.json` / `alias-parse/deprecated.json`) の該当 case と一致し、
// conformance runner が実際にその期待を満たしていることは `[json-conformance] mismatches=0` が
// 別途保証している — 本 wbtest は玄関 API の契約側からその 3 面を独立に固定する層。

///|
/// 保証 (MDR-005 §1 / DR-021 → DR-073 / DR-053 §3): front_door.parse は `parse_tree` の直接
/// 結果ではなく **`promote_collision_ambiguous` 込みの spec 準拠 Outcome** を返す。同一 args で
/// 2 flag (a / b) が共に export_key "x" へ露出する場合、raw `parse_tree` は Success を返すが、
/// 玄関 `parse` は Ambiguous に昇格し、各 interpretation が DR-073 §1 の claimants 面 (露出キー
/// "x" → 占める実体 name) を持つ。fixture 期待は 2 解釈 `{claimants: {"x":"a"}}` と
/// `{claimants: {"x":"b"}}` で、集合として比較する (順序非依存、DR-073 §3)。
test "front_door.parse: export-key 共露出は Ambiguous + claimants に昇格 (DR-021 → DR-073, MDR-005 §1)" {
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
  // raw `parse_tree` は Success を返す (parse 段は共露出を検知しない)。この対比は「front_door.parse
  // が薄い wrapper のままだった旧実装での不具合再現」の pin として、期待外れの Ambiguous 昇格が
  // parse_tree 側で先に起きていないことも同時に確認する。
  let raw = parse_tree(ScopeNode(ast.root), ["--a", "--b"], defs=ast.registry)
  match raw {
    Success(_) => ()
    other =>
      fail(
        "raw parse_tree should still succeed pre-promotion, got " +
        render_outcome(other),
      )
  }
  // 玄関 `parse` は promote_collision_ambiguous を内包するため Ambiguous を返す。
  let o = parse(ast, ["--a", "--b"])
  match o {
    Ambiguous(d) => {
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
        "front_door.parse should promote to Ambiguous, got " +
        render_outcome(other),
      )
  }
}

///|
/// 保証 (MDR-005 §1 / DR-059 §5 / DR-047 §4): front_door.resolve は値源ラダー
/// (env/config/inherit/default) を子 scope まで再帰的に充填する。inheritable:true の子 scope
/// entity は、祖先で書かれた write-target 値を **`Inherit` source** の binding として得る (spec
/// fixture `inheritable-parse/basic.json` の `ancestor-inherit-flowdown` case: `--sub-ttl 30 sub`
/// で `sub.ttl = 30`, source=inherit)。ここでは玄関 API のみを叩き、結果 binds に:
///   - root path=[] に ttl 値 30 with source=Cli (`--sub-ttl` 発火の write-target)
///   - 子 path=["sub"] に ttl 値 30 with source=Inherit (親から流下した inherit 席)
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
    Success(_) => ()
    other =>
      fail("front_door.parse should succeed, got " + render_outcome(other))
  }
  // resolve なしの Success binds には子 scope 側の ttl (inherit 経由の値) は入らない —
  // 「玄関 `resolve` を明示的に呼ばないと DR-047 §4 の最終状態は得られない」ことの反証面。
  match po {
    Success(pre) => {
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
    Success(rb) => {
      // root path=[] の ttl (write-target への cli 発火)。
      let mut root_ttl : Value? = None
      let mut root_src : Source? = None
      // 子 path=["sub"] の ttl (親から流下した inherit 値)。
      let mut sub_ttl : Value? = None
      let mut sub_src : Source? = None
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
      assert_eq(root_ttl, Some(VNum(30.0)))
      assert_eq(root_src, Some(Cli))
      assert_eq(sub_ttl, Some(VNum(30.0)))
      assert_eq(sub_src, Some(Inherit))
    }
    other =>
      fail("front_door.resolve should succeed, got " + render_outcome(other))
  }
}

///|
/// 保証 (MDR-005 §1 / DR-058 §2): deprecated:true が付いた alias 入口の発火は、値の束縛 (canonical
/// セル `port` = 80) と並行して、Success outcome から `warnings_structured` が
/// `{element: "port", kind: "deprecated"}` を返す。同時に、`@depr:port` sentinel binding は
/// `is_sentinel` で除外可能 = kuu-cli 相当の呼び出し側が effects (非 sentinel binds のリスト) を
/// 組み立てるときに漏れない (kuu-cli PoC codex レビュー M-1 = warnings の構造化 + sentinel を
/// effects に漏らさないためのプロダクション pub 面を要件化)。
test "front_door.parse + warnings_structured: deprecated alias 発火は構造化 warning + effects から @depr sentinel 除外 (DR-058 §2, MDR-005 §1)" {
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
    Success(binds) => {
      // port の値は 80、source=Cli (canonical セルへ普通に束縛される、DR-058 は受理不変)。
      let mut port_val : Value? = None
      for b in binds {
        if is_sentinel(b.key) {
          continue
        }
        if b.scope.length() == 0 && b.key == "port" {
          port_val = Some(b.value)
        }
      }
      assert_eq(port_val, Some(VNum(80.0)))
      // 構造化 warnings が `{element:"port", kind:"deprecated"}` の 1 件を返す。
      let ws = warnings_structured(o)
      assert_eq(ws, [{ element: "port", kind: "deprecated" }])
      // sentinel `@depr:port` は binds に含まれる (warnings_of/warnings_structured の素材) が、
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
/// 保証 (issue 2026-07-16-result-projection-production-promotion、DR-109 §3「sources は resolve
/// 済み出力に常に含める」/ §5 UX-Q5=a、MDR-005「射程外」節の解消): front_door の `result`/
/// `sources` が `resolve()` の Success payload だけから DR-052 result-key 軸適用済みの `result`
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
    Success(b) => b
    other => {
      fail("front_door.resolve should succeed, got " + render_outcome(other))
      panic()
    }
  }
  let rval = result(ast, rb)
  match rval {
    RObj(kvs) => {
      let mut p_val : RVal? = None
      let mut verbose_val : RVal? = None
      for kv in kvs {
        if kv.0 == "p" {
          p_val = Some(kv.1)
        }
        if kv.0 == "verbose" {
          verbose_val = Some(kv.1)
        }
      }
      assert_eq(p_val, Some(RScalar(VNum(8080.0))))
      assert_eq(verbose_val, Some(RScalar(VBool(false))))
    }
    _ => fail("front_door.result should be RObj at root scope")
  }
  let ses = sources(ast, rb)
  let mut p_src : Source? = None
  let mut verbose_src : Source? = None
  for se in ses {
    if se.key == "p" {
      p_src = Some(se.source)
    }
    if se.key == "verbose" {
      verbose_src = Some(se.source)
    }
  }
  assert_eq(p_src, Some(Cli))
  assert_eq(verbose_src, Some(Default))
}

///|
/// 保証 (issue 2026-07-16-result-projection-production-promotion、DR-109 §3): command 木を持つ
/// scope でも `front_door.sources` は**同一シグネチャ**のまま木全体の値源タグを返す — 呼び出し側は
/// command 木の有無 (`has_commands`) を一切意識しない (resolve.mbt `result_sources` のコメント
/// 参照、外部利用者にその分岐を意識させない 1 本の関数へ畳む設計)。子 scope "sub" で発火した
/// ttl の値源タグが `path: ["sub"], key: "ttl", source: Cli` として現れることを固定する。
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
    Success(b) => b
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
    Some(se) => assert_eq(se.source, Cli)
    None => fail("expected a sub.ttl SourceEntry with path=[\"sub\"]")
  }
}
