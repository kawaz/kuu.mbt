///|
/// valuepath.mbt — Struct-first CLI parser PoC: core types and parse function
///
/// Design rationale: ユーザーの元スケッチでは Commit の Value が (T)->T だったが、
/// CLI引数は常にStringなので (String)->T に変更。

/// 値注入の戦略
enum Commit[T] {
  /// フラグ: 存在したらTを返す
  Exist(() -> T)
  /// 値: CLI文字列からTを生成（エラー時は Some(msg) を返す）
  Value((String) -> (T, String?))
}

/// 型消去されたパスエントリ（パースループ用）
/// on_match は None=成功、Some(msg)=エラー を返す
struct PathEntry {
  name : String
  needs_value : Bool
  on_match : (String) -> String?
}

/// `--name=value` を分割するヘルパー
fn split_eq(arg : String) -> (String, String?) {
  let len = arg.length()
  let mut i = 0
  while i < len {
    if arg[i] == '=' {
      let name = arg[:i].to_string()
      let value = arg[i + 1:].to_string()
      return (name, Some(value))
    }
    i = i + 1
  }
  (arg, None)
}

/// 汎用 PathEntry 構築（Commit[T] を実際に使用）
fn[T] vp_custom(name : String, target : Ref[T], commit : Commit[T]) -> PathEntry {
  match commit {
    Exist(f) =>
      PathEntry::{
        name,
        needs_value: false,
        on_match: fn(_s) {
          target.val = f()
          None
        },
      }
    Value(f) =>
      PathEntry::{
        name,
        needs_value: true,
        on_match: fn(s) {
          let (val, err) = f(s)
          match err {
            Some(msg) => Some(msg)
            None => {
              target.val = val
              None
            }
          }
        },
      }
  }
}

/// フラグ（Bool）用のPathEntry
fn vp_flag(name : String, target : Ref[Bool]) -> PathEntry {
  vp_custom(name, target, Exist(fn() { true }))
}

/// 文字列オプション用のPathEntry
fn vp_string(name : String, target : Ref[String]) -> PathEntry {
  vp_custom(name, target, Value(fn(s) { (s, None) }))
}

/// 整数オプション用のPathEntry
fn vp_int(name : String, target : Ref[Int]) -> PathEntry {
  vp_custom(
    name,
    target,
    Value(
      fn(s) {
        match parse_int_simple(s) {
          Ok(n) => (n, None)
          Err(msg) => (0, Some(msg))
        }
      },
    ),
  )
}

/// カウンタ用のPathEntry（needs_value=false, 出現回数をカウント）
fn vp_count(name : String, target : Ref[Int]) -> PathEntry {
  PathEntry::{
    name,
    needs_value: false,
    on_match: fn(_s) {
      target.val = target.val + 1
      None
    },
  }
}

/// 文字列配列追記用のPathEntry
fn vp_append(name : String, target : Ref[Array[String]]) -> PathEntry {
  vp_custom(name, target, Value(fn(s) { ([s], None) }))
  // Design rationale: vp_append は append セマンティクスなので vp_custom の Value で
  // 配列ごと置き換わってしまう。直接構築に戻す。
  |> ignore
  PathEntry::{
    name,
    needs_value: true,
    on_match: fn(s) {
      target.val.push(s)
      None
    },
  }
}

/// 簡易 Int パース（負数対応、非数字文字はエラー）
fn parse_int_simple(s : String) -> Result[Int, String] {
  let len = s.length()
  if len == 0 {
    return Err("Invalid integer: empty string")
  }
  let mut result = 0
  let mut i = 0
  let mut negative = false
  if s[0] == '-' {
    negative = true
    i = 1
  }
  if i >= len {
    return Err("Invalid integer: " + s)
  }
  while i < len {
    let c = s[i]
    if c < '0' || c > '9' {
      return Err("Invalid integer: " + s)
    }
    let digit = c.to_int() - '0'.to_int()
    result = result * 10 + digit
    i = i + 1
  }
  if negative {
    Ok(-result)
  } else {
    Ok(result)
  }
}

/// サブコマンド付きパース
///
/// paths: 現在のレベルで認識するオプション
/// subcmds: (名前, サブコマンドのパス配列, rest引数格納先)
/// rest_target: このレベルでの残余引数格納先（None なら未知引数はエラー）
fn vp_parse(
  args : Array[String],
  paths : Array[PathEntry],
  subcmds~ : Array[(String, Array[PathEntry], Ref[Array[String]]?)]? = None,
  rest_target~ : Ref[Array[String]]? = None,
  matched_cmd~ : Ref[String?]? = None
) -> Result[Unit, String] {
  // name 重複検出
  let mut di = 0
  while di < paths.length() {
    let mut dj = di + 1
    while dj < paths.length() {
      if paths[di].name == paths[dj].name {
        return Err("Duplicate path entry name: " + paths[di].name)
      }
      dj = dj + 1
    }
    di = di + 1
  }
  let len = args.length()
  let mut i = 0
  while i < len {
    let raw_arg = args[i]
    let (arg_name, eq_value) = split_eq(raw_arg)
    // オプションマッチを試みる
    let mut found = false
    let mut j = 0
    while j < paths.length() {
      let entry = paths[j]
      if arg_name == entry.name {
        found = true
        if entry.needs_value {
          match eq_value {
            Some(v) => {
              let err = (entry.on_match)(v)
              match err {
                Some(msg) => return Err(msg)
                None => ()
              }
            }
            None => {
              i = i + 1
              if i >= len {
                return Err("Missing value for " + entry.name)
              }
              let err = (entry.on_match)(args[i])
              match err {
                Some(msg) => return Err(msg)
                None => ()
              }
            }
          }
        } else {
          match eq_value {
            Some(_) =>
              return Err(
                "Flag " + entry.name + " does not accept a value",
              )
            None => {
              let err = (entry.on_match)("")
              match err {
                Some(msg) => return Err(msg)
                None => ()
              }
            }
          }
        }
        break
      }
      j = j + 1
    }
    if not(found) {
      // サブコマンドマッチを試みる
      let mut cmd_found = false
      match subcmds {
        Some(cmds) => {
          let mut k = 0
          while k < cmds.length() {
            let (cmd_name, cmd_paths, cmd_rest) = cmds[k]
            if raw_arg == cmd_name {
              cmd_found = true
              match matched_cmd {
                Some(r) => r.val = Some(cmd_name)
                None => ()
              }
              // 残りの引数をサブコマンドに渡す
              let sub_args : Array[String] = []
              let mut si = i + 1
              while si < len {
                sub_args.push(args[si])
                si = si + 1
              }
              return vp_parse(sub_args, cmd_paths, rest_target=cmd_rest)
            }
            k = k + 1
          }
        }
        None => ()
      }
      if not(cmd_found) {
        // rest 引数として扱う
        match rest_target {
          Some(rest) => rest.val.push(raw_arg)
          None => return Err("Unknown argument: " + raw_arg)
        }
      }
    }
    i = i + 1
  }
  Ok(())
}
