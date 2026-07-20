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
      HGroup(group) => output.push("group:" + group.name)
      HOption(option) =>
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
  guard model.options[0] is HOption(port) else { abort("port option missing") }
  assert_eq(port.spellings, ["--port", "-p"])
  guard port.value_structure is Some(HVSingle(port_single)) else {
    abort("port value_structure missing")
  }
  assert_eq(port_single.value_name, Some("PORT"))
  assert_eq(port_single.type_, Some("number"))
  assert_eq(port.env, ["PORT"])
  guard model.positionals[0].value_structure is HVSingle(file_single) else {
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
  guard model.options[2] is HOption(old_port) else {
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
