// fn_ctx_wbtest.mbt — unified context mode and observation capability ABI.

///|
test "FnCtx mode and specialization accessors agree" {
  let default_ctx = fn_ctx_default("target", old=Some(VNum(2.0)))
  assert_eq(default_ctx.mode(), "default")
  assert_true(default_ctx.as_effect() is None)
  assert_true(default_ctx.as_filter() is None)
  match default_ctx.as_default() {
    Some(specialized) => assert_eq(specialized.target(), "target")
    None => fail("default mode must expose DefaultCtx")
  }
  assert_eq(default_ctx.old(), Some(VNum(2.0)))

  let effect_ctx = fn_ctx_effect("target", "--count")
  assert_eq(effect_ctx.mode(), "effect")
  assert_true(effect_ctx.as_default() is None)
  assert_true(effect_ctx.as_filter() is None)
  match effect_ctx.as_effect() {
    Some(specialized) => {
      assert_eq(specialized.target(), "target")
      assert_eq(specialized.trigger(), "--count")
    }
    None => fail("effect mode must expose EffectCtx")
  }

  let filter_ctx = fn_ctx_filter(ScalarInput(VStr("input")))
  assert_eq(filter_ctx.mode(), "filter")
  assert_true(filter_ctx.as_default() is None)
  assert_true(filter_ctx.as_effect() is None)
  match filter_ctx.as_filter() {
    Some(specialized) =>
      assert_eq(specialized.input(), ScalarInput(VStr("input")))
    None => fail("filter mode must expose FilterCtx")
  }
}

///|
test "FnCtx option env and system reads are restricted to concrete observes edges" {
  let ctx = fn_ctx_default(
    "target",
    observes=["option:source", "env:VISIBLE", "system:clock"],
    option=fn(name) {
      if name == "source" {
        Some(VStr("dependency"))
      } else {
        None
      }
    },
    env=fn(variable) {
      if variable == "VISIBLE" {
        Some(VStr("env-value"))
      } else {
        None
      }
    },
    system=fn(key) { if key == "clock" { Some(VNum(12.0)) } else { None } },
  )
  assert_eq(ctx.option("source"), Some(VStr("dependency")))
  assert_true(ctx.option("hidden") is None)
  match ctx.as_default() {
    Some(specialized) => {
      assert_eq(specialized.dependency("source"), Some(VStr("dependency")))
      assert_true(specialized.dependency("hidden") is None)
    }
    None => fail("default mode must expose DefaultCtx")
  }
  assert_eq(ctx.env("VISIBLE"), Some(VStr("env-value")))
  assert_true(ctx.env("HIDDEN") is None)
  assert_eq(ctx.system("clock"), Some(VNum(12.0)))
  assert_true(ctx.system("secret") is None)

  let observations = ctx.observes()
  observations.push("option:hidden")
  assert_eq(ctx.observes(), ["option:source", "env:VISIBLE", "system:clock"])
  assert_true(ctx.option("hidden") is None)
}
