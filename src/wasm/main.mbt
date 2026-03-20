///|
/// WASM bridge for kuu core.
///
/// Architecture:
///   JSON schema + args  ->  kuu core (WASM)  ->  JSON result
///
/// Input JSON format:
/// {
///   "version": 1,
///   "opts": [
///     { "kind": "flag", "name": "verbose", "shorts": "v", "global": true, "description": "...", "env": "VERBOSE" },
///     { "kind": "string", "name": "host", "default": "localhost", "description": "...", "env": "HOST" },
///     { "kind": "int", "name": "port", "default": 8080, "description": "..." },
///     { "kind": "float", "name": "rate", "default": 1.0, "description": "..." },
///     { "kind": "count", "name": "verbose", "shorts": "v", "description": "..." },
///     { "kind": "positional", "name": "file", "description": "..." },
///     { "kind": "rest", "name": "args", "description": "..." },
///     { "kind": "dashdash" },
///     { "kind": "command", "name": "serve", "description": "...", "opts": [...] },
///     { "kind": "serial", "opts": [...] },
///     { "kind": "deprecated", "name": "--old", "target": "host", "msg": "Use --host" },
///     { "kind": "clone", "name": "alt_host", "clone_of": "host" }
///   ],
///   "args": ["--verbose", "--host", "example.com", "file.txt"],
///   "env": { "VERBOSE": "1", "HOST": "fallback.example.com" },
///   "description": "My CLI tool",
///   "auto_env": true,
///   "env_prefix": "MYAPP",
///   "require_cmd": true,
///   "exclusive": [["shared", "static"]],
///   "required": ["filename"],
///   "at_least_one": [["json", "csv"]],
///   "requires": [{ "source": "key_file", "target": "output" }],
///   "links": [{ "source": "verbose", "target": "debug", "propagate_set": true }],
///   "adjusts": [{ "target": "port", "filter": { "in_range": [1, 65535] } }]
/// }
///
/// Output JSON format (success):
/// {
///   "ok": true,
///   "values": { "verbose": true, "host": "example.com", "port": 8080, "file": "file.txt" },
///   "command": { "name": "serve", "values": { ... } },
///   "deprecated_warnings": [{ "name": "--old", "msg": "Use --host" }]
/// }
///
/// Output JSON format (error):
/// {
///   "ok": false,
///   "error": "error message",
///   "help": "help text",
///   "tip": "suggested option (omitted if empty)",
///   "kind": "UnknownOption"
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
/// Type-erased opt handle for clone/link/adjust operations.
/// Stores closures that capture the typed Opt[T] to enable cross-opt
/// operations without exposing generic type parameters.
struct OptHandle {
  // clone: create a new opt with same parse behavior but independent value
  clone_fn : (String) -> (OptEntry, @core.OptRef)
  // link_as_target: register link from named source to this opt.
  // Captures the target Opt[T], looks up source from typed maps.
  // (source_name, propagate_set) -> Result
  link_as_target_fn : (String, Bool) -> Result[Unit, String]
  // adjust: register post-parse filter on this opt.
  // Takes filter spec (String or Object) and returns Err on invalid filter.
  adjust_fn : (Json) -> Result[Unit, String]
}

///|
struct SchemaResult {
  entries : Array[OptEntry]
  children : Map[String, SchemaResult]
}

// --- Helpers ---

///|
/// Extract optional String from JSON object field.
fn get_opt_string(obj : Map[String, Json], key : String) -> String? {
  match obj.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// Extract variation parameters from a JSON object and build Variation array.
fn extract_variations(obj : Map[String, Json]) -> Array[@core.Variation] {
  let variations : Array[@core.Variation] = []
  match get_opt_string(obj, "variation_toggle") {
    Some(p) => variations.push(@core.Toggle(p))
    None => ()
  }
  match get_opt_string(obj, "variation_true") {
    Some(p) => variations.push(@core.True(p))
    None => ()
  }
  match get_opt_string(obj, "variation_false") {
    Some(p) => variations.push(@core.False(p))
    None => ()
  }
  match get_opt_string(obj, "variation_reset") {
    Some(p) => variations.push(@core.Reset(p))
    None => ()
  }
  match get_opt_string(obj, "variation_unset") {
    Some(p) => variations.push(@core.Unset(p))
    None => ()
  }
  variations
}

///|
/// Parse a post filter for String from JSON.
fn parse_string_post(
  obj : Map[String, Json],
) -> @core.FilterChain[String, String]? {
  match obj.get("post") {
    Some(String("trim")) => Some(@core.Filter::trim())
    Some(String("non_empty")) => Some(@core.Filter::non_empty())
    _ => None
  }
}

///|
/// Check if an opts array contains a "dashdash" kind entry.
fn has_dashdash_opt(opts : Array[Json]) -> Bool {
  opts
  .iter()
  .any(fn(j) {
    match j {
      Object(o) =>
        match o.get("kind") {
          Some(String("dashdash")) => true
          _ => false
        }
      _ => false
    }
  })
}

///|
/// Parse a string filter from JSON spec.
/// Supports: "trim", "non_empty", "to_lower", "to_upper"
fn parse_string_filter(filter : Json) -> @core.FilterChain[String, String]? {
  match filter {
    String("trim") => Some(@core.Filter::trim())
    String("non_empty") => Some(@core.Filter::non_empty())
    String("to_lower") => Some(@core.Filter::to_lower())
    String("to_upper") => Some(@core.Filter::to_upper())
    _ => None
  }
}

///|
/// Parse an int filter from JSON spec.
/// Supports: { "in_range": [min, max] }, { "clamp": [min, max] }
fn parse_int_filter(filter : Json) -> @core.FilterChain[Int, Int]? {
  match filter {
    Object(obj) => {
      match obj.get("in_range") {
        Some(Array(arr)) =>
          if arr.length() == 2 {
            let min = match arr[0] {
              Number(n, ..) => n.to_int()
              _ => return None
            }
            let max = match arr[1] {
              Number(n, ..) => n.to_int()
              _ => return None
            }
            return Some(@core.Filter::in_range(min, max))
          }
        _ => ()
      }
      match obj.get("clamp") {
        Some(Array(arr)) =>
          if arr.length() == 2 {
            let min = match arr[0] {
              Number(n, ..) => n.to_int()
              _ => return None
            }
            let max = match arr[1] {
              Number(n, ..) => n.to_int()
              _ => return None
            }
            return Some(@core.Filter::clamp(min, max))
          }
        _ => ()
      }
      None
    }
    _ => None
  }
}

///|
/// Parse a float filter from JSON spec.
/// Supports: { "float_in_range": [min, max] }
fn parse_float_filter(filter : Json) -> @core.FilterChain[Double, Double]? {
  match filter {
    Object(obj) =>
      match obj.get("float_in_range") {
        Some(Array(arr)) =>
          if arr.length() == 2 {
            let min = match arr[0] {
              Number(n, ..) => n
              _ => return None
            }
            let max = match arr[1] {
              Number(n, ..) => n
              _ => return None
            }
            Some(@core.Filter::float_in_range(min, max))
          } else {
            None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// Parse a post filter for Int from JSON.
fn parse_int_post(obj : Map[String, Json]) -> @core.FilterChain[Int, Int]? {
  match obj.get("post") {
    Some(filter) => parse_int_filter(filter)
    _ => None
  }
}

///|
/// Parse a post filter for Double from JSON.
fn parse_float_post(
  obj : Map[String, Json],
) -> @core.FilterChain[Double, Double]? {
  match obj.get("post") {
    Some(filter) => parse_float_filter(filter)
    _ => None
  }
}

///|
fn build_parser(
  parser : @core.Parser,
  opts_json : Array[Json],
  scope_json : Map[String, Json],
) -> Result[SchemaResult, String] {
  let entries : Array[OptEntry] = []
  let children : Map[String, SchemaResult] = {}
  let opt_refs : Map[String, @core.OptRef] = {}
  // deprecated 2パス用: opt 名 → deprecated 登録クロージャ（型消去済み）
  let deprecate_fns : Map[String, (String, String) -> Unit] = {}
  // clone/link/adjust 用: opt 名 → 型消去済みハンドル
  let opt_handles : Map[String, OptHandle] = {}
  // 型別 Opt マップ（link で source/target の型マッチングに使用）
  let opts_bool : Map[String, @core.Opt[Bool]] = {}
  let opts_string : Map[String, @core.Opt[String]] = {}
  let opts_int : Map[String, @core.Opt[Int]] = {}
  let opts_double : Map[String, @core.Opt[Double]] = {}
  let opts_arr_string : Map[String, @core.Opt[Array[String]]] = {}
  let opts_arr_int : Map[String, @core.Opt[Array[Int]]] = {}
  let opts_arr_double : Map[String, @core.Opt[Array[Double]]] = {}
  // deprecated エントリを遅延処理するために収集
  let deferred_deprecated : Array[Map[String, Json]] = []
  // clone エントリを遅延処理するために収集
  let deferred_clones : Array[Map[String, Json]] = []
  for opt_json in opts_json {
    match opt_json {
      Object(obj) => {
        let kind = match obj.get("kind") {
          Some(String(s)) => s
          _ => return Err("opt definition missing 'kind'")
        }
        // deprecated, clone は pass 2 で処理するため収集して skip
        if kind == "deprecated" {
          deferred_deprecated.push(obj)
          continue
        }
        if kind == "clone" {
          deferred_clones.push(obj)
          continue
        }
        // dashdash and serial don't need name
        let name = match kind {
          "dashdash" | "serial" =>
            match obj.get("name") {
              Some(String(s)) => s
              _ => ""
            }
          _ =>
            match obj.get("name") {
              Some(String(s)) => s
              _ => return Err("opt definition missing 'name'")
            }
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
        let visibility : @core.Visibility = match obj.get("visibility") {
          Some(String("hidden")) => Hidden
          Some(String("advanced")) => Advanced
          _ =>
            // backward compat: "hidden": true → Hidden
            match obj.get("hidden") {
              Some(True) => Hidden
              _ => Visible
            }
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
        let variations = extract_variations(obj)
        let env = match obj.get("env") {
          Some(String(s)) => s
          _ => ""
        }
        match kind {
          "flag" => {
            let default_val = match obj.get("default") {
              Some(True) => true
              _ => false
            }
            let opt = parser.flag(
              name~,
              default=default_val,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              variations~,
              env~,
            )
            opt_refs[name] = opt.as_ref()
            opts_bool[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let flag_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_bool[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(v) => Json::boolean(v)
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_bool.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      flag_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(_filter) {
                // Bool opts don't have meaningful adjust filters
                Err("adjust not supported for flag type")
              },
            }
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(v) => Json::boolean(v)
                  None => Json::null()
                }
              },
            })
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
            let implicit_value : @core.Lazy[String]? = match
              obj.get("implicit_value") {
              Some(String(s)) => Some(@core.Val(s))
              _ => None
            }
            let post = parse_string_post(obj)
            let opt = parser.custom(
              name~,
              default=default_val,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              choices~,
              implicit_value~,
              post~,
              variations~,
              env~,
              pre=@core.Filter::map(fn(s) { s }),
            )
            opt_refs[name] = opt.as_ref()
            opts_string[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let str_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_string[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(v) => Json::string(v)
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_string.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      str_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(filter) {
                match parse_string_filter(filter) {
                  Some(chain) => {
                    parser.adjust(opt, after_post=chain)
                    Ok(())
                  }
                  None => Err("unsupported adjust filter for string type")
                }
              },
            }
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(v) => Json::string(v)
                  None => Json::null()
                }
              },
            })
          }
          "int" => {
            let default_val = match obj.get("default") {
              Some(Number(n, ..)) => n.to_int()
              _ => 0
            }
            let implicit_value : @core.Lazy[Int]? = match
              obj.get("implicit_value") {
              Some(Number(n, ..)) => Some(@core.Val(n.to_int()))
              _ => None
            }
            let post = parse_int_post(obj)
            let opt = parser.custom(
              name~,
              default=default_val,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              implicit_value~,
              post~,
              variations~,
              env~,
              pre=@core.Filter::parse_int(),
            )
            opt_refs[name] = opt.as_ref()
            opts_int[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let int_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_int[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(v) => Json::number(v.to_double())
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_int.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      int_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(filter) {
                match parse_int_filter(filter) {
                  Some(chain) => {
                    parser.adjust(opt, after_post=chain)
                    Ok(())
                  }
                  None => Err("unsupported adjust filter for int type")
                }
              },
            }
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(v) => Json::number(v.to_double())
                  None => Json::null()
                }
              },
            })
          }
          "float" => {
            let default_val = match obj.get("default") {
              Some(Number(n, ..)) => n
              _ => 0.0
            }
            let implicit_value : @core.Lazy[Double]? = match
              obj.get("implicit_value") {
              Some(Number(n, ..)) => Some(@core.Val(n))
              _ => None
            }
            let post = parse_float_post(obj)
            let opt = parser.custom(
              name~,
              default=default_val,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              implicit_value~,
              post~,
              variations~,
              env~,
              pre=@core.Filter::parse_float(),
            )
            opt_refs[name] = opt.as_ref()
            opts_double[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let float_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_double[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(v) => Json::number(v)
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_double.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      float_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(filter) {
                match parse_float_filter(filter) {
                  Some(chain) => {
                    parser.adjust(opt, after_post=chain)
                    Ok(())
                  }
                  None => Err("unsupported adjust filter for float type")
                }
              },
            }
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(v) => Json::number(v)
                  None => Json::null()
                }
              },
            })
          }
          "boolean" => {
            let default_val = match obj.get("default") {
              Some(True) => true
              _ => false
            }
            let implicit_value : @core.Lazy[Bool]? = match
              obj.get("implicit_value") {
              Some(True) => Some(@core.Val(true))
              Some(False) => Some(@core.Val(false))
              _ => None
            }
            let opt = parser.custom(
              name~,
              default=default_val,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              implicit_value~,
              variations~,
              env~,
              pre=@core.Filter::parse_bool(),
            )
            opt_refs[name] = opt.as_ref()
            opts_bool[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let bool_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_bool[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(v) => Json::boolean(v)
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_bool.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      bool_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(_filter) {
                Err("adjust not supported for boolean type")
              },
            }
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(v) => Json::boolean(v)
                  None => Json::null()
                }
              },
            })
          }
          "count" => {
            let opt = parser.count(
              name~,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              variations~,
              env~,
            )
            opt_refs[name] = opt.as_ref()
            opts_int[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let count_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_int[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(v) => Json::number(v.to_double())
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_int.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      count_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(filter) {
                match parse_int_filter(filter) {
                  Some(chain) => {
                    parser.adjust(opt, after_post=chain)
                    Ok(())
                  }
                  None => Err("unsupported adjust filter for count type")
                }
              },
            }
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(v) => Json::number(v.to_double())
                  None => Json::null()
                }
              },
            })
          }
          "append_string" => {
            let opt = parser.custom_append(
              name~,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              variations~,
              env~,
              pre=@core.Filter::map(fn(s) { s }),
            )
            opt_refs[name] = opt.as_ref()
            opts_arr_string[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let astr_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_arr_string[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(arr) =>
                        Json::array(arr.map(fn(s) -> Json { Json::string(s) }))
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_arr_string.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      astr_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(_filter) {
                Err("adjust not supported for append_string type")
              },
            }
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(arr) =>
                    Json::array(arr.map(fn(s) -> Json { Json::string(s) }))
                  None => Json::null()
                }
              },
            })
          }
          "append_int" => {
            let opt = parser.custom_append(
              name~,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              variations~,
              env~,
              pre=@core.Filter::parse_int(),
            )
            opt_refs[name] = opt.as_ref()
            opts_arr_int[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let aint_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_arr_int[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(arr) =>
                        Json::array(
                          arr.map(fn(n) -> Json { Json::number(n.to_double()) }),
                        )
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_arr_int.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      aint_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(_filter) {
                Err("adjust not supported for append_int type")
              },
            }
            entries.push(OptEntry::{
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
            })
          }
          "append_float" => {
            let opt = parser.custom_append(
              name~,
              global~,
              shorts~,
              description~,
              visibility~,
              aliases~,
              variations~,
              env~,
              pre=@core.Filter::parse_float(),
            )
            opt_refs[name] = opt.as_ref()
            opts_arr_double[name] = opt
            deprecate_fns[name] = fn(alias_name, dep_msg) {
              let _ = parser.deprecated(alias_name, opt, msg=dep_msg)
            }
            let afloat_name = name
            opt_handles[name] = OptHandle::{
              clone_fn: fn(new_name) {
                let cloned = parser.clone("--" + new_name, opt)
                opt_refs[new_name] = cloned.as_ref()
                opts_arr_double[new_name] = cloned
                let entry = OptEntry::{
                  name: new_name,
                  extract: fn() -> Json {
                    match cloned.get() {
                      Some(arr) =>
                        Json::array(arr.map(fn(n) -> Json { Json::number(n) }))
                      None => Json::null()
                    }
                  },
                }
                (entry, cloned.as_ref())
              },
              link_as_target_fn: fn(source_name, propagate_set) {
                match opts_arr_double.get(source_name) {
                  Some(source) => {
                    parser.link(opt, source~, propagate_set~)
                    Ok(())
                  }
                  None =>
                    Err(
                      "link type mismatch: " +
                      source_name +
                      " and " +
                      afloat_name +
                      " must be the same type",
                    )
                }
              },
              adjust_fn: fn(_filter) {
                Err("adjust not supported for append_float type")
              },
            }
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(arr) =>
                    Json::array(arr.map(fn(n) -> Json { Json::number(n) }))
                  None => Json::null()
                }
              },
            })
          }
          "positional" => {
            let opt = parser.positional(name~, description~)
            opt_refs[name] = opt.as_ref()
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(v) => Json::string(v)
                  None => Json::null()
                }
              },
            })
          }
          "rest" => {
            let opt = parser.rest(name~, description~)
            opt_refs[name] = opt.as_ref()
            entries.push(OptEntry::{
              name,
              extract: fn() -> Json {
                match opt.get() {
                  Some(arr) =>
                    Json::array(arr.map(fn(s) -> Json { Json::string(s) }))
                  None => Json::null()
                }
              },
            })
          }
          "dashdash" => {
            let opt = parser.dashdash()
            entries.push(OptEntry::{
              name: "--",
              extract: fn() -> Json {
                match opt.get() {
                  Some(arr) =>
                    Json::array(arr.map(fn(s) -> Json { Json::string(s) }))
                  None => Json::null()
                }
              },
            })
          }
          "serial" => {
            let child_opts : Array[Json] = match obj.get("opts") {
              Some(Array(arr)) => arr
              _ => []
            }
            // serial uses a sub-parser setup function
            // We need to collect entries from the serial's positionals
            let serial_entries : Array[OptEntry] = []
            let serial_opt_refs : Map[String, @core.OptRef] = {}
            let serial_child_opts = child_opts
            parser.serial(setup=fn(sub) {
              for sub_opt_json in serial_child_opts {
                match sub_opt_json {
                  Object(sub_obj) => {
                    let sub_kind = match sub_obj.get("kind") {
                      Some(String(s)) => s
                      _ => ""
                    }
                    let sub_name = match sub_obj.get("name") {
                      Some(String(s)) => s
                      _ => ""
                    }
                    let sub_desc = match sub_obj.get("description") {
                      Some(String(s)) => s
                      _ => ""
                    }
                    match sub_kind {
                      "positional" => {
                        let opt = sub.positional(
                          name=sub_name,
                          description=sub_desc,
                        )
                        serial_opt_refs[sub_name] = opt.as_ref()
                        serial_entries.push(OptEntry::{
                          name: sub_name,
                          extract: fn() -> Json {
                            match opt.get() {
                              Some(v) => Json::string(v)
                              None => Json::null()
                            }
                          },
                        })
                      }
                      "rest" => {
                        let opt = sub.rest(name=sub_name, description=sub_desc)
                        serial_opt_refs[sub_name] = opt.as_ref()
                        serial_entries.push(OptEntry::{
                          name: sub_name,
                          extract: fn() -> Json {
                            match opt.get() {
                              Some(arr) =>
                                Json::array(
                                  arr.map(fn(s) -> Json { Json::string(s) }),
                                )
                              None => Json::null()
                            }
                          },
                        })
                      }
                      _ => () // serial only supports positional and rest
                    }
                  }
                  _ => ()
                }
              }
            })
            // Add serial entries to parent
            for entry in serial_entries {
              entries.push(entry)
            }
            for k, v in serial_opt_refs {
              opt_refs[k] = v
            }
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
            let child_dashdash = not(has_dashdash_opt(child_opts))
            let child_parser = parser.sub(
              name~,
              description~,
              aliases~,
              dashdash=child_dashdash,
            )
            if child_desc != "" {
              child_parser.set_description(child_desc)
            }
            // require_cmd inside command
            let require_cmd = match obj.get("require_cmd") {
              Some(True) => true
              _ => false
            }
            if require_cmd {
              child_parser.require_cmd()
            }
            let child_result = match
              build_parser(child_parser, child_opts, obj) {
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
  // Handle require_cmd at scope level
  let require_cmd = match scope_json.get("require_cmd") {
    Some(True) => true
    _ => false
  }
  if require_cmd {
    parser.require_cmd()
  }
  // Pass 2: Handle deprecated entries (deferred from pass 1)
  for dep_obj in deferred_deprecated {
    let dep_name = match dep_obj.get("name") {
      Some(String(s)) => s
      _ => return Err("deprecated opt missing 'name'")
    }
    let target_name = match dep_obj.get("target") {
      Some(String(s)) => s
      _ => return Err("deprecated opt missing 'target'")
    }
    let dep_msg = match dep_obj.get("msg") {
      Some(String(s)) => s
      _ => ""
    }
    match deprecate_fns.get(target_name) {
      Some(register_fn) => register_fn(dep_name, dep_msg)
      None => return Err("deprecated target not found: " + target_name)
    }
  }
  // Pass 3: Handle clone entries (deferred from pass 1)
  for clone_obj in deferred_clones {
    let clone_name = match clone_obj.get("name") {
      Some(String(s)) => s
      _ => return Err("clone opt missing 'name'")
    }
    let clone_of = match clone_obj.get("clone_of") {
      Some(String(s)) => s
      _ => return Err("clone opt missing 'clone_of'")
    }
    match opt_handles.get(clone_of) {
      Some(handle) => {
        // clone_fn internally calls Parser::clone which expects "--" prefix,
        // but the entry name should be bare for the values map key.
        let (entry, opt_ref) = (handle.clone_fn)(clone_name)
        entries.push(entry)
        opt_refs[clone_name] = opt_ref
      }
      None => return Err("clone target not found: " + clone_of)
    }
  }
  // Pass 4: Handle link entries
  match scope_json.get("links") {
    Some(Array(items)) =>
      for item in items {
        match item {
          Object(link_obj) => {
            let source_name = match link_obj.get("source") {
              Some(String(s)) => s
              _ => continue
            }
            let target_name = match link_obj.get("target") {
              Some(String(s)) => s
              _ => continue
            }
            let propagate_set = match link_obj.get("propagate_set") {
              Some(True) => true
              _ => false
            }
            // Validate source exists
            match opt_handles.get(source_name) {
              None => return Err("link source not found: " + source_name)
              Some(_) => ()
            }
            // Look up target handle and call link_as_target_fn
            match opt_handles.get(target_name) {
              None => return Err("link target not found: " + target_name)
              Some(handle) =>
                match (handle.link_as_target_fn)(source_name, propagate_set) {
                  Ok(_) => ()
                  Err(msg) => return Err(msg)
                }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  // Pass 5: Handle adjust entries
  match scope_json.get("adjusts") {
    Some(Array(items)) =>
      for item in items {
        match item {
          Object(adj_obj) => {
            let target_name = match adj_obj.get("target") {
              Some(String(s)) => s
              _ => continue
            }
            let filter = match adj_obj.get("filter") {
              Some(f) => f
              _ => continue
            }
            match opt_handles.get(target_name) {
              None => return Err("adjust target not found: " + target_name)
              Some(handle) =>
                match (handle.adjust_fn)(filter) {
                  Ok(_) => ()
                  Err(msg) => return Err(msg)
                }
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  // Pass 6: Handle constraints (after link/adjust so that propagated values are visible)
  // Handle exclusive constraints
  match scope_json.get("exclusive") {
    Some(Array(groups)) =>
      for group in groups {
        match group {
          Array(names) => {
            let refs : Array[@core.OptRef] = []
            for name_json in names {
              match name_json {
                String(n) =>
                  match opt_refs.get(n) {
                    Some(r) => refs.push(r)
                    None => ()
                  }
                _ => ()
              }
            }
            if refs.length() > 1 {
              parser.exclusive(refs)
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  // Handle required constraints
  match scope_json.get("required") {
    Some(Array(names)) =>
      for name_json in names {
        match name_json {
          String(n) =>
            match opt_refs.get(n) {
              Some(r) => parser.required(r)
              None => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  // Handle at_least_one constraints
  match scope_json.get("at_least_one") {
    Some(Array(groups)) =>
      for group in groups {
        match group {
          Array(names) => {
            let refs : Array[@core.OptRef] = []
            for name_json in names {
              match name_json {
                String(n) =>
                  match opt_refs.get(n) {
                    Some(r) => refs.push(r)
                    None => ()
                  }
                _ => ()
              }
            }
            if refs.length() > 1 {
              parser.at_least_one(refs)
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  // Handle requires constraints
  match scope_json.get("requires") {
    Some(Array(items)) =>
      for item in items {
        match item {
          Object(req_obj) => {
            let source_name = match req_obj.get("source") {
              Some(String(s)) => s
              _ => continue
            }
            let target_name = match req_obj.get("target") {
              Some(String(s)) => s
              _ => continue
            }
            let msg = match req_obj.get("msg") {
              Some(String(s)) => s
              _ => ""
            }
            match (opt_refs.get(source_name), opt_refs.get(target_name)) {
              (Some(source_ref), Some(target_ref)) =>
                parser.requires(target_ref, source=source_ref, msg~)
              _ => ()
            }
          }
          _ => ()
        }
      }
    _ => ()
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
  let parse_json_result : Result[Json, _] = try? @json.parse(input.view())
  let json : Json = match parse_json_result {
    Ok(j) => j
    Err(_) => return make_error_json("invalid input JSON", "")
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
        return make_error_json(
          "unsupported schema version: " + ver.to_string(),
          "",
        )
      }
    }
    None => () // omitted: treat as version 1 (backward compat)
    _ => return make_error_json("'version' must be a number", "")
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
  // Check if opts contain explicit "dashdash" kind (if so, disable default separator)
  let has_dashdash_kind = has_dashdash_opt(opts_json)
  // Build parser from schema
  let parser = @core.Parser::new(dashdash=not(has_dashdash_kind))
  if description != "" {
    parser.set_description(description)
  }
  // Handle env_prefix (must be before build_parser — used during opt registration)
  match obj.get("env_prefix") {
    Some(String(prefix)) => parser.env_prefix(prefix)
    _ => ()
  }
  // Handle auto_env (must be before build_parser — used during opt registration)
  match obj.get("auto_env") {
    Some(True) => parser.auto_env(true)
    _ => ()
  }
  let schema = match build_parser(parser, opts_json, obj) {
    Ok(s) => s
    Err(msg) => return make_error_json(msg, "")
  }
  // Extract env (environment variables)
  let env_map : Map[String, String] = match obj.get("env") {
    Some(Object(env_obj)) => {
      let m : Map[String, String] = {}
      for k, v in env_obj {
        match v {
          String(s) => m[k] = s
          _ => ()
        }
      }
      m
    }
    _ => {}
  }
  // Parse
  let result : Result[@core.ParseResult, @core.ParseError] = try? parser.parse(
    args,
    env=env_map,
  )
  match result {
    Ok(parse_result) => {
      let output = extract_values(schema, parse_result)
      // Append deprecated_warnings if any
      match output {
        Object(result_obj) => {
          let warnings = parser.deprecated_warnings()
          if warnings.length() > 0 {
            let warn_arr : Array[Json] = []
            for pair in warnings {
              let w : Map[String, Json] = {}
              w["name"] = Json::string(pair.0)
              w["msg"] = Json::string(pair.1)
              warn_arr.push(Json::object(w))
            }
            result_obj["deprecated_warnings"] = Json::array(warn_arr)
          }
          Json::object(result_obj).stringify()
        }
        other => other.stringify()
      }
    }
    Err(@core.HelpRequested(text)) => make_help_json(text)
    Err(@core.ParseError(info)) =>
      make_error_json(
        info.message,
        info.error_context,
        tip=info.tip,
        kind=info.kind.to_string(),
      )
  }
}

///|
fn make_error_json(
  message : String,
  error_context : String,
  tip? : String = "",
  kind? : String = "",
) -> String {
  let obj : Map[String, Json] = {}
  obj["ok"] = Json::boolean(false)
  obj["error"] = Json::string(message)
  if error_context != "" {
    obj["help"] = Json::string(error_context)
  }
  if tip != "" {
    obj["tip"] = Json::string(tip)
  }
  if kind != "" {
    obj["kind"] = Json::string(kind)
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
