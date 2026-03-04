///|
test "Opt equality is id-based" {
  let meta : OptMeta = {
    name: "a",
    kind: Kind::Option,
    help: "",
    shorts: [],
    aliases: [],
    inversion: None,
    env: None,
    auto_env: None,
    choices: [],
    value_name: "",
    required: false,
    visibility: Visible,
    global: false,
    greedy: false,
  }
  let opt1 : Opt[Int] = {
    id: 1,
    initial: Val(0),
    reducer: fn(ctx) { Some(ctx.current) },
    meta,
    getter: fn(_id) { 0 },
    setter: fn(_id, _v) {  },
    children_opts: Opts::Array([]),
  }
  let opt2 : Opt[Int] = {
    id: 1,
    initial: Val(0),
    reducer: fn(ctx) { Some(ctx.current) },
    meta,
    getter: fn(_id) { 0 },
    setter: fn(_id, _v) {  },
    children_opts: Opts::Array([]),
  }
  let opt3 : Opt[Int] = {
    id: 2,
    initial: Val(0),
    reducer: fn(ctx) { Some(ctx.current) },
    meta,
    getter: fn(_id) { 0 },
    setter: fn(_id, _v) {  },
    children_opts: Opts::Array([]),
  }
  assert_true(opt1 == opt2)
  assert_true(opt1 != opt3)
}
