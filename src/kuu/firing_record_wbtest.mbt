// firing_record_wbtest.mbt — DR-114 §6.1「cell fn は発火時に 1 回」の一本化 (FiringRecord) の pin。
//
// 3 実行経路 (effects 射影 / 枝ローカル fold / resolve 相 CLI seat) が同じ発火を独立実行していた
// 旧構造では、実行回数カウンタは経路数ぶん増え、非決定 fn は経路ごとに別の値を観測した。
// 一本化後は「勝ち経路確定後の 1 回の fold (値残余セルは枝内実行の引き継ぎ)」だけが実行し、
// 射影と resolve は FiringRecord の消費者になる — カウンタ = 発火数、観測値は全経路一致。

///|
fn firing_ast(src : String, registry : @node.Registry) -> AtomicAST raise {
  match
    parse_definition(
      @json.parse(src) catch {
        _ => abort("invalid test definition JSON")
      },
      extensions=registry,
    ) {
    Ok(ast) => ast
    Err(Rejected(errors)) => {
      let detail = if errors.length() > 0 {
        errors[0].message
      } else {
        "no definition error detail"
      }
      fail("parse_definition should accept the definition: " + detail)
      panic()
    }
    Err(Malformed(message)) => {
      fail("parse_definition should accept the definition: " + message)
      panic()
    }
  }
}

///|
/// 呼ぶたびに値が変わる (= 非決定を模す) Value fn を数えるカウンタ付き registry。
fn firing_counter_registry(
  name : String,
  counter : Ref[Int],
  value_of : (Int, @extension.FnCtx) -> @abi.Value,
) -> @node.Registry {
  let registry = canonical_registry()
  guard registry.register_type(CsvSeatType::{  } as &@extension.TypeExt) else {
    abort("duplicate test resident: csv")
  }
  guard registry.register_cell_fn(
    @extension.cell_fn_descriptor(
      name,
      [],
      @extension.CellFnOutput::Value,
      @extension.FnFallibility::Total,
      run=fn(_, ctx) {
        counter.val = counter.val + 1
        Ok(@extension.FnOutput::Value(value_of(counter.val, ctx)))
      },
    ),
  ) else {
    abort("duplicate test cell fn: " + name)
  }
  registry
}

///|
test "DR-114 §6.1: 値残余の無いセルの fn は発火 1 回 — 3 経路が record を消費する" {
  let counter : Ref[Int] = { val: 0 }
  // 呼ぶたびに 10, 20, 30... を返す = 再実行があれば経路間で観測値がずれる非決定 fn。
  let registry = firing_counter_registry("tick", counter, fn(n, _) {
    @abi.Number(n.to_double() * 10.0)
  })
  let ast = firing_ast(
    (
      #|{"options":[{"name":"n","type":"number","long":[":tick"]}]}
    ),
    registry,
  )
  let args = ["--n", "--n"]
  guard parse(ast, args) is Success(binds) else { fail("should parse") }
  let effects = binds.effects(ast)
  guard resolve(ast, binds, args) is Success(resolved) else {
    fail("should resolve")
  }
  let view = output(ast, resolved)
  // 実行は裁定後 fold の 2 発火分のみ (旧構造では effects 射影 + resolve + output 射影で 6 回)。
  assert_eq(counter.val, 2)
  // 非決定 fn でも全経路の観測が一致する: effects 射影 = output の effects = result。
  assert_eq(effects.length(), 2)
  assert_eq(effects[0].operand, Some(@abi.Number(10)))
  assert_eq(effects[1].operand, Some(@abi.Number(20)))
  assert_eq(view.effects, effects)
  assert_eq(@engine.element_value(resolved.raw, [], "n"), Some(@abi.Number(20)))
}

///|
test "DR-114 §6.1 × DR-131 §1.1: Value(null) の record は set(null) 観測とラダー開放へ一度だけ配達される" {
  let counter : Ref[Int] = { val: 0 }
  let registry = firing_counter_registry("nil-tick", counter, fn(_, _) {
    @abi.Null
  })
  let ast = firing_ast(
    (
      #|{"options":[{"name":"n","type":"number","default":7,"long":[":nil-tick"]}]}
    ),
    registry,
  )
  let args = ["--n"]
  guard parse(ast, args) is Success(binds) else { fail("should parse") }
  let effects = binds.effects(ast)
  guard resolve(ast, binds, args) is Success(resolved) else {
    fail("should resolve")
  }
  let view = output(ast, resolved)
  // null は failure へ分類せず set(null) として観測し、セル適用時だけ default 席へ開放する。
  assert_eq(effects.length(), 1)
  assert_eq(effects[0].op, @abi.EffectOp::Set)
  assert_eq(effects[0].operand, Some(@abi.Null))
  assert_eq(@engine.element_value(resolved.raw, [], "n"), Some(@abi.Number(7)))
  assert_eq(view.effects, effects)
  // effects / resolve は同じ FiringRecord を消費するため、resident 実行は発火時の 1 回だけ。
  assert_eq(counter.val, 1)
}

///|
test "DR-114 §6.1: 値残余セルの fn は枝内実行を引き継ぐ — fold の枝選別値と resolve の座値が同一" {
  let counter : Ref[Int] = { val: 0 }
  let registry = firing_counter_registry("tock", counter, fn(n, _) {
    @abi.Number(100.0 + n.to_double())
  })
  let ast = firing_ast(
    (
      #|{"options":[
      #|  {"name":"arr","type":"csv","long":true},
      #|  {"name":"last","type":"number","long":[":tock"],"link":"arr[-1]"}]}
    ),
    registry,
  )
  let args = ["--arr", "1,2", "--last"]
  guard parse(ast, args) is Success(binds) else { fail("should parse") }
  let effects = binds.effects(ast)
  guard resolve(ast, binds, args) is Success(resolved) else {
    fail("should resolve")
  }
  let view = output(ast, resolved)
  // 実行は枝ローカル fold (裁定前の枝選別) の 1 回だけ。effects / resolve は記録を消費する —
  // 非決定 fn の「枝選別に使った値」と「座へ書かれた値」の乖離 (issue の危険域) が閉じる。
  assert_eq(counter.val, 1)
  assert_eq(effects.length(), 2)
  // 観測アドレスは発火時点の現在長で解決済み (DR-127 §6): arr[-1] → arr[1]。
  assert_eq(effects[1].entity, "arr")
  assert_eq(effects[1].path, [@abi.ObservationIndex(1)])
  assert_eq(effects[1].operand, Some(@abi.Number(101)))
  assert_eq(view.effects, effects)
  assert_eq(
    @engine.element_value(resolved.raw, [], "arr"),
    Some(@abi.Array([@abi.Number(1), @abi.Number(101)])),
  )
}

///|
/// `ctx.old` を読む fn (old+1)。record 消費 gate (resolve 側の old 一致) を通ることも
/// このカウンタで pin する — gate が外れて再実行されればカウンタが増える。
fn firing_bump_registry(counter : Ref[Int]) -> @node.Registry {
  firing_counter_registry("bump", counter, fn(_, ctx) {
    let base = match ctx.old() {
      Some(@abi.Number(v)) => v
      _ => 0.0
    }
    @abi.Number(base + 1.0)
  })
}

///|
test "DR-114 §6.1 × DR-081 §2: parse の env 供給が明示 default 後の old に効く (W2-4 §3.2 の閉じ)" {
  let counter : Ref[Int] = { val: 0 }
  let ast = firing_ast(
    (
      #|{"options":[{"name":"n","type":"number","env":"N","default":3,
      #|  "long":[":bump","reset:default"]}]}
    ),
    firing_bump_registry(counter),
  )
  let args = ["--reset-n", "--n"]
  let sources = value_sources(env=env_from_map(Map([("N", "5")])))
  guard parse(ast, args, sources~) is Success(binds) else {
    fail("should parse")
  }
  let effects = binds.effects(ast)
  guard resolve(ast, binds, args, sources~) is Success(resolved) else {
    fail("should resolve")
  }
  // 明示 `default` 効果の落ち先は書き換え済み default = env の 5 (DR-081 §2)。後続の
  // `ctx.old` 依存 fn は 5 を読んで 6 — parse 相 fold が ladder を引けるようになったので、
  // effects 射影 (record の消費者) と result が一致する (W2-4 findings §3.2 の残差の閉じ)。
  assert_eq(effects.length(), 2)
  assert_eq(effects[0].op, @abi.EffectOp::Default)
  assert_eq(effects[1].operand, Some(@abi.Number(6)))
  assert_eq(@engine.element_value(resolved.raw, [], "n"), Some(@abi.Number(6)))
  // 実行は parse 相 fold の 1 回のみ = resolve は record を消費した (old 一致 gate の通過)。
  assert_eq(counter.val, 1)
}

///|
test "DR-114 §6.1 × DR-081 §2: parse の config 供給も明示 default 後の old に効く" {
  let counter : Ref[Int] = { val: 0 }
  let ast = firing_ast(
    (
      #|{"options":[
      #|  {"name":"config","type":"config_file","long":true,"default":"/app.toml"},
      #|  {"name":"n","type":"number","config_key":["n"],"default":3,
      #|   "long":[":bump","reset:default"]}]}
    ),
    firing_bump_registry(counter),
  )
  let args = ["--reset-n", "--n"]
  let sources = value_sources(config=fn(path) {
    if path == "/app.toml" {
      Some(config_from_json({ "n": 7 }))
    } else {
      None
    }
  })
  guard parse(ast, args, sources~) is Success(binds) else {
    fail("should parse")
  }
  let effects = binds.effects(ast)
  guard resolve(ast, binds, args, sources~) is Success(resolved) else {
    fail("should resolve")
  }
  assert_eq(effects.length(), 2)
  assert_eq(effects[0].op, @abi.EffectOp::Default)
  assert_eq(effects[1].operand, Some(@abi.Number(8)))
  assert_eq(@engine.element_value(resolved.raw, [], "n"), Some(@abi.Number(8)))
  assert_eq(counter.val, 1)
}

///|
test "DR-114 §6.1: parse と resolve の値源が食い違えば record は消費されない (old 一致 gate)" {
  let counter : Ref[Int] = { val: 0 }
  let ast = firing_ast(
    (
      #|{"options":[{"name":"n","type":"number","env":"N","default":3,
      #|  "long":[":bump","reset:default"]}]}
    ),
    firing_bump_registry(counter),
  )
  let args = ["--reset-n", "--n"]
  // 契約違反 (facade doc の「両相で同一値」) の形: parse は env なし、resolve だけ env あり。
  guard parse(ast, args) is Success(binds) else { fail("should parse") }
  guard resolve(
      ast,
      binds,
      args,
      sources=value_sources(env=env_from_map(Map([("N", "5")]))),
    )
    is Success(resolved) else {
    fail("should resolve")
  }
  // resolve 側の old (env 5) は record の old_used (宣言 default 3) と一致しない → 再実行。
  // 実行回数は parse 相 fold の 1 回 + resolve の再実行 1 回 = 2 (現行挙動の防衛線)。
  assert_eq(counter.val, 2)
  // result は従来どおり resolve 自身の値源で決まる (5+1=6)。
  assert_eq(@engine.element_value(resolved.raw, [], "n"), Some(@abi.Number(6)))
}
