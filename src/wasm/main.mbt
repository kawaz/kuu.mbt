///|
/// WASM bridge for kuu core.
///
/// Architecture:
///   JSON schema + args  →  kuu core (WASM)  →  JSON result
///
/// Input JSON format:
/// {
///   "version": 1,
///   "opts": [
///     { "kind": "flag", "name": "verbose", "shorts": "v", "global": true, "description": "..." },
///     { "kind": "string", "name": "host", "default": "localhost", "description": "..." },
///     { "kind": "int", "name": "port", "default": 8080, "description": "..." },
///     { "kind": "count", "name": "verbose", "shorts": "v", "description": "..." },
///     { "kind": "positional", "name": "file", "description": "..." },
///     { "kind": "rest", "name": "args", "description": "..." },
///     { "kind": "command", "name": "serve", "description": "...", "opts": [...] }
///   ],
///   "args": ["--verbose", "--host", "example.com", "file.txt"],
///   "description": "My CLI tool"
/// }
///
/// Output JSON format (success):
/// {
///   "ok": true,
///   "values": { "verbose": true, "host": "example.com", "port": 8080, "file": "file.txt" },
///   "command": { "name": "serve", "values": { ... } }
/// }
///
/// Output JSON format (error):
/// {
///   "ok": false,
///   "error": "error message",
///   "help": "help text"
/// }
///
/// Output JSON format (help):
/// {
///   "ok": false,
///   "help_requested": true,
///   "help": "help text"
/// }

// --- Opt registry: tracks Opt handles by name for result extraction ---

///|
struct OptEntry {
  name : String
  extract : () -> Json // produces the JSON value after parse
}

///|
struct SchemaResult {
  entries : Array[OptEntry]
  children : Map[String, SchemaResult]
}

///|
fn build_parser(
  parser : @core.Parser,
  opts_json : Array[Json],
) -> Result[SchemaResult, String] {
  let entries : Array[OptEntry] = []
  let children : Map[String, SchemaResult] = {}
  for opt_json in opts_json {
    match opt_json {
      Object(obj) => {
        let kind = match obj.get("kind") {
          Some(String(s)) => s
          _ => return Err("opt definition missing 'kind'")
        }
        let name = match obj.get("name") {
          Some(String(s)) => s
          _ => return Err("opt definition missing 'name'")
        }
        let description = match obj.get("description") {
          Some(String(s)) => s
          _ => ""
        }
        let shorts = match obj.get("shorts") {
          Some(String(s)) => s
          _ => ""
        }
        let global = match obj.get("global") {
          Some(True) => true
          _ => false
        }
        let hidden = match obj.get("hidden") {
          Some(True) => true
          _ => false
        }
        let aliases : Array[String] = match obj.get("aliases") {
          Some(Array(arr)) => {
            let result : Array[String] = []
            for item in arr {
              match item {
                String(s) => result.push(s)
                _ => ()
              }
            }
            result
          }
          _ => []
        }
        match kind {
          "flag" => {
            let default_val = match obj.get("default") {
              Some(True) => true
              _ => false
            }
            let opt = parser.flag(
              name~, default=default_val, global~, shorts~,
              description~, hidden~, aliases~,
            )
            entries.push(
              OptEntry::{
                name,
                extract: fn() -> Json {
                  match opt.get() {
                    Some(v) => Json::boolean(v)
                    None => Json::null()
                  }
                },
              },
            )
          }
          "string" => {
            let default_val = match obj.get("default") {
              Some(String(s)) => s
              _ => ""
            }
            let choices : Array[String] = match obj.get("choices") {
              Some(Array(arr)) => {
                let result : Array[String] = []
                for item in arr {
                  match item {
                    String(s) => result.push(s)
                    _ => ()
                  }
                }
                result
              }
              _ => []
            }
            let opt = parser.string_opt(
              name~, default=default_val, global~, shorts~,
              description~, hidden~, aliases~, choices~,
            )
            entries.push(
              OptEntry::{
                name,
                extract: fn() -> Json {
                  match opt.get() {
                    Some(v) => Json::string(v)
                    None => Json::null()
                  }
                },
              },
            )
          }
          "int" => {
            let default_val = match obj.get("default") {
              Some(Number(n, ..)) => n.to_int()
              _ => 0
            }
            let opt = parser.int_opt(
              name~, default=default_val, global~, shorts~,
              description~, hidden~, aliases~,
            )
            entries.push(
              OptEntry::{
                name,
                extract: fn() -> Json {
                  match opt.get() {
                    Some(v) => Json::number(v.to_double())
                    None => Json::null()
                  }
                },
              },
            )
          }
          "count" => {
            let opt = parser.count(
              name~, global~, shorts~, description~, hidden~, aliases~,
            )
            entries.push(
              OptEntry::{
                name,
                extract: fn() -> Json {
                  match opt.get() {
                    Some(v) => Json::number(v.to_double())
                    None => Json::null()
                  }
                },
              },
            )
          }
          "append_string" => {
            let opt = parser.append_string(
              name~, global~, shorts~, description~, hidden~, aliases~,
            )
            entries.push(
              OptEntry::{
                name,
                extract: fn() -> Json {
                  match opt.get() {
                    Some(arr) =>
                      Json::array(arr.map(fn(s) -> Json { Json::string(s) }))
                    None => Json::null()
                  }
                },
              },
            )
          }
          "append_int" => {
            let opt = parser.append_int(
              name~, global~, shorts~, description~, hidden~, aliases~,
            )
            entries.push(
              OptEntry::{
                name,
                extract: fn() -> Json {
                  match opt.get() {
                    Some(arr) =>
                      Json::array(
                        arr.map(fn(n) -> Json { Json::number(n.to_double()) }),
                      )
                    None => Json::null()
                  }
                },
              },
            )
          }
          "positional" => {
            let opt = parser.positional(name~, description~)
            entries.push(
              OptEntry::{
                name,
                extract: fn() -> Json {
                  match opt.get() {
                    Some(v) => Json::string(v)
                    None => Json::null()
                  }
                },
              },
            )
          }
          "rest" => {
            let opt = parser.rest(name~, description~)
            entries.push(
              OptEntry::{
                name,
                extract: fn() -> Json {
                  match opt.get() {
                    Some(arr) =>
                      Json::array(arr.map(fn(s) -> Json { Json::string(s) }))
                    None => Json::null()
                  }
                },
              },
            )
          }
          "command" => {
            let child_opts : Array[Json] = match obj.get("opts") {
              Some(Array(arr)) => arr
              _ => []
            }
            let child_desc = match obj.get("description") {
              Some(String(s)) => s
              _ => ""
            }
            let child_parser = parser.sub(name~, description~)
            if child_desc != "" {
              child_parser.set_description(child_desc)
            }
            let child_result = match build_parser(child_parser, child_opts) {
              Ok(s) => s
              Err(e) => return Err(e)
            }
            children[name] = child_result
          }
          _ => return Err("unknown opt kind: " + kind)
        }
      }
      _ => return Err("each element in 'opts' must be an object")
    }
  }
  Ok(SchemaResult::{ entries, children })
}

///|
fn extract_values(
  schema : SchemaResult,
  parse_result : @core.ParseResult,
) -> Json {
  let values : Map[String, Json] = {}
  for entry in schema.entries {
    values[entry.name] = (entry.extract)()
  }
  let result_obj : Map[String, Json] = {}
  result_obj["ok"] = Json::boolean(true)
  result_obj["values"] = Json::object(values)
  // Extract child command results
  for name, child_schema in schema.children {
    match parse_result.child(name) {
      Some(child_result) => {
        let child_json = extract_values(child_schema, child_result)
        match child_json {
          Object(child_obj) => {
            let cmd_obj : Map[String, Json] = {}
            cmd_obj["name"] = Json::string(name)
            match child_obj.get("values") {
              Some(v) => cmd_obj["values"] = v
              None => ()
            }
            // Propagate nested command info
            match child_obj.get("command") {
              Some(v) => cmd_obj["command"] = v
              None => ()
            }
            result_obj["command"] = Json::object(cmd_obj)
          }
          _ => ()
        }
      }
      None => ()
    }
  }
  Json::object(result_obj)
}

///|
/// Main entry point: receives JSON input, returns JSON output.
/// Uses wasm-gc + js-builtin-string for direct String interop.
pub fn kuu_parse(input : String) -> String {
  // Parse input JSON
  let parse_json_result : Result[Json, _] = try? (
    @json.parse(input.view())
  )
  let json : Json = match parse_json_result {
    Ok(j) => j
    Err(_) =>
      return make_error_json("invalid input JSON", "")
  }
  let obj = match json {
    Object(o) => o
    _ => return make_error_json("input must be a JSON object", "")
  }
  // Validate schema version
  match obj.get("version") {
    Some(Number(n, ..)) => {
      let ver = n.to_int()
      if ver != 1 {
        return make_error_json("unsupported schema version: " + ver.to_string(), "")
      }
    }
    None => () // omitted: treat as version 1 (backward compat)
    _ =>
      return make_error_json("'version' must be a number", "")
  }
  // Extract args
  let args : Array[String] = match obj.get("args") {
    Some(Array(arr)) => {
      let result : Array[String] = []
      for item in arr {
        match item {
          String(s) => result.push(s)
          _ => return make_error_json("args must be an array of strings", "")
        }
      }
      result
    }
    Some(_) => return make_error_json("args must be an array of strings", "")
    None => []
  }
  // Extract opts schema
  let opts_json : Array[Json] = match obj.get("opts") {
    Some(Array(arr)) => arr
    Some(_) => return make_error_json("'opts' must be an array", "")
    None => []
  }
  // Extract description
  let description = match obj.get("description") {
    Some(String(s)) => s
    _ => ""
  }
  // Build parser from schema
  let parser = @core.Parser::new()
  if description != "" {
    parser.set_description(description)
  }
  let schema = match build_parser(parser, opts_json) {
    Ok(s) => s
    Err(msg) => return make_error_json(msg, "")
  }
  // Parse
  let result : Result[@core.ParseResult, @core.ParseError] = try? parser.parse(
    args,
  )
  match result {
    Ok(parse_result) => {
      let output = extract_values(schema, parse_result)
      output.stringify()
    }
    Err(@core.HelpRequested(text)) => make_help_json(text)
    Err(@core.ParseError(info)) =>
      make_error_json(info.message, info.help_text)
  }
}

///|
fn make_error_json(message : String, help_text : String) -> String {
  let obj : Map[String, Json] = {}
  obj["ok"] = Json::boolean(false)
  obj["error"] = Json::string(message)
  if help_text != "" {
    obj["help"] = Json::string(help_text)
  }
  Json::object(obj).stringify()
}

///|
fn make_help_json(help_text : String) -> String {
  let obj : Map[String, Json] = {}
  obj["ok"] = Json::boolean(false)
  obj["help_requested"] = Json::boolean(true)
  obj["help"] = Json::string(help_text)
  Json::object(obj).stringify()
}

///|
fn main {
  // Required by is-main; actual entry point is the exported kuu_parse function.
}
