// help_wbtest.mbt — DR-112 help model の宣言層射影を fixture 相当の輪郭で固定する。

///|
fn help_model(src : String, path? : Array[String] = []) -> HelpModel {
  let json = @json.parse(src) catch { _ => abort("invalid test JSON") }
  let ast = match parse_definition(json) {
    Ok(value) => value
    Err(_) => abort("test definition rejected")
  }
  match help(ast, path~) {
    Ok(model) => model
    Err(_) => abort("test help query rejected") // HelpQueryError の分岐は M3c-A で導入、この wbtest は Ok path のみ
  }
}

///|
fn help_option_spellings(entries : Array[HelpOptionEntry]) -> Array[String] {
  let output : Array[String] = []
  for entry in entries {
    match entry {
      Group(group) => output.push("group:" + group.name)
      Option(option) =>
        if option.spellings.length() > 0 {
          output.push(option.spellings[0])
        } else {
          output.push("")
        }
    }
  }
  output
}

///|
/// ルート基本形は、スコープ素材・入口綴り・値名・default/env・positional・help_entry を
/// パース実行なしで同じ宣言層 snapshot から組み立てる。
test "help: root scope projects semantic materials" {
  let model = help_model(
    (
      #|{"name":"prog","help":"Serve files","options":[{"name":"port","type":"number","long":true,"short":"p","env":"PORT","default":8080,"value_name":"PORT","help":"listen port"},{"name":"help","type":"help","long":true,"help":"show help"}],"positionals":[{"name":"file","type":"string","value_name":"FILE","help":"input file"}]}
    ),
  )
  assert_eq(model.command_path, ["prog"])
  assert_eq(model.description, Some("Serve files"))
  assert_eq(help_option_spellings(model.options), ["--port", "--help"])
  guard model.options[0] is Option(port) else { abort("port option missing") }
  assert_eq(port.spellings, ["--port", "-p"])
  guard port.value_structure is Some(Single(port_single)) else {
    abort("port value_structure missing")
  }
  assert_eq(port_single.value_name, Some("PORT"))
  assert_eq(port_single.value_type, Some("number"))
  assert_eq(port.env, ["PORT"])
  guard model.positionals[0].value_structure is Single(file_single) else {
    abort("file positional value_structure missing")
  }
  assert_eq(file_single.value_name, Some("FILE"))
  assert_eq(model.help_entry, Some("--help"))
}

///|
/// options の規範順は group declaration を含む安定 order sort の後に help_after を適用した
/// フラット列であり、name 付き alias は独立 entry として target 直後へ移動する。
test "help: group order and named alias after compose" {
  let model = help_model(
    (
      #|{"options":[{"help_group_name":"net","help_group_title":"Network options","help_group_description":"socket & TLS"},{"name":"port","type":"number","long":true,"help_group_name":"net","help":"listen port"},{"name":"verbose","type":"flag","long":true,"help":"verbose output"},{"name":"help","type":"help","long":true,"help_order":10001,"help":"show help"},{"name":"old-port","alias":"port","long":true,"deprecated":true,"help_after":"port","help":"use --port instead"}]}
    ),
  )
  assert_eq(help_option_spellings(model.options), [
    "group:net", "--port", "--old-port", "--verbose", "--help",
  ])
  guard model.options[2] is Option(old_port) else {
    abort("named alias entry missing")
  }
  assert_true(old_port.deprecated)
  assert_eq(old_port.help, Some("use --port instead"))
}

///|
/// help_after の連鎖 a after b / b after c は推移的に解決され、無関係な x の相対位置を
/// 壊さず [c,b,a,x] になる。
test "help: after chain resolves transitively" {
  let model = help_model(
    (
      #|{"options":[{"name":"a","type":"flag","long":true,"help_after":"b"},{"name":"b","type":"flag","long":true,"help_after":"c"},{"name":"c","type":"flag","long":true},{"name":"x","type":"flag","long":true}]}
    ),
  )
  assert_eq(help_option_spellings(model.options), ["--c", "--b", "--a", "--x"])
}

///|
/// global installer が不動点中に孫スコープへ追加した宣言コピーも snapshot に残り、path 選択した
/// help から --help と command 自身の description が見える。
test "help: nested path reads post-fixpoint global declaration copy" {
  let model = help_model(
    (
      #|{"name":"prog","options":[{"name":"help","type":"help","long":true,"global":true,"help":"show help"}],"commands":[{"type":"command","name":"remote","help":"manage remotes","commands":[{"type":"command","name":"add","help":"add a remote"}]}]}
    ),
    path=["remote", "add"],
  )
  assert_eq(model.command_path, ["prog", "remote", "add"])
  assert_eq(model.description, Some("add a remote"))
  assert_eq(help_option_spellings(model.options), ["--help"])
}

///|
/// DR-136 §5「alias は綴り軸の別名を追加する入口ノード」: command alias の一覧に出すのは
/// **入口綴り** (alias ノードの trigger_name) であって name 軸の値ではない。name 軸を出すと
/// help が `co_x` と表示するのに実際に打てるのは `co-x` という食い違いになる (option 側の
/// `alias_spellings` は綴り軸なので、command 側だけが非対称だった)。
test "command aliases are listed on the spelling axis (DR-136 §5)" {
  let src =
    #|{"commands":[{"type":"command","name":"co_main","help":"m"},{"alias":"co_main","type":"command","name":"co_x"}]}
  let ast = match parse_definition(@json.parse(src)) {
    Ok(ast) => ast
    Err(_) => {
      fail("definition was rejected")
      return
    }
  }
  let model = match help(ast) {
    Ok(model) => model
    Err(_) => {
      fail("help query failed")
      return
    }
  }
  assert_eq(model.commands.length(), 1)
  assert_eq(model.commands[0].aliases, ["co-x"])
  // 表示した綴りが実際に打てる綴りであること (help と CLI 表面の一致こそが §5 の眼目)。
  match test_resolve(ast, ["co-x"]) {
    Success(_) => ()
    Failure(_) => fail("the spelling listed by help is not accepted on the CLI")
  }
  match test_resolve(ast, ["co_x"]) {
    Success(_) => fail("the name-axis spelling must not be a CLI entry")
    Failure(_) => ()
  }
}

///|
/// DR-053 §4「定義に **help 入口** があれば、その綴り」: help_entry の素材は help 入口であって
/// fail_action 一般ではない。DR-113 §7.2 / DESIGN §15.10 の汎用 `on_failure: true` を素で立てた
/// `--version` も fail_action=true になるので、それだけを見ると本物の `--help` が併存していても
/// 宣言順で `--version` が help_entry に載っていた (実測)。判別は `is_help_preset`。
test "help_entry is a help entry, not any fail_action (DR-053 §4)" {
  let cases : Array[(String, String, String?)] = [
    (
      "help preset only",
      (
        #|{"options":[{"name":"help","type":"help","long":true}]}
      ),
      Some("--help"),
    ),
    (
      "generic on_failure only",
      (
        #|{"options":[{"name":"version","type":"flag","long":true,"on_failure":true}]}
      ),
      None,
    ),
    (
      "generic on_failure declared before the help preset",
      (
        #|{"options":[{"name":"version","type":"flag","long":true,"on_failure":true},{"name":"help","type":"help","long":true}]}
      ),
      Some("--help"),
    ),
  ]
  for case in cases {
    let (label, src, expected) = case
    let ast = match parse_definition(@json.parse(src)) {
      Ok(ast) => ast
      Err(_) => {
        fail(label + ": definition was rejected")
        return
      }
    }
    match help(ast) {
      Ok(model) => assert_eq(model.help_entry, expected)
      Err(_) => fail(label + ": help query failed")
    }
  }
}

///|
/// CONFORMANCE §2 / DR-053 §4: help_entry は failure / ambiguous の**両方**に載る素材であり、
/// 由来が消費 ambiguous かセル union の淘汰かで有無が変わるものではない。union 由来の
/// Failure / Ambiguous だけ `help_entry: None` を固定していた。
test "union-derived failures still carry help_entry (CONFORMANCE §2)" {
  let src =
    #|{"options":[{"name":"help","type":"help","long":true},{"name":"color","type":"fixture/color","long":true},{"name":"r","type":"int","long":true,"link":"color[0]"},{"name":"g","type":"int","long":true,"link":"color[1]"},{"name":"b","type":"int","long":true,"link":"color[2]"}]}
  let registry = @node.Registry::new()
  install_canonical(registry)
  install_conformance_fixture_residents(registry)
  let ast = match parse_definition(@json.parse(src), extensions=registry) {
    Ok(ast) => ast
    Err(_) => {
      fail("definition was rejected")
      return
    }
  }
  // r と g だけを供給 = color の値が揃わない (incomplete_value)。淘汰由来の Failure。
  match parse(ast, ["--r", "0", "--g", "255"]) {
    Failure(f) => assert_eq(f.help_entry, Some("--help"))
    Ambiguous(_) => fail("expected a union-incomplete failure")
    Success(_) => fail("expected a union-incomplete failure")
  }
}
