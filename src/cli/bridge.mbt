///|
/// CLI bridge for kuu core.
///
/// Architecture:
///   JSON schema + args  ->  kuu core (native)  ->  JSON result

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

// --- Parser builder ---

///|
fn build_parser(
  parser : @core.Parser,
  opts_json : Array[Json],
  scope_json : Map[String, Json],
) -> Result[SchemaResult, String] {
  let entries : Array[OptEntry] = []
  let children : Map[String, SchemaResult] = {}
  let opt_refs : Map[String, @core.OptRef] = {}
  // deprecated 2-pass: opt name -> deprecation registration closure (type-erased)
  let deprecate_fns : Map[String, (String, String) -> Unit] = {}
  // clone/link/adjust: opt name -> type-erased handle
  let opt_handles : Map[String, OptHandle] = {}
  // Typed Opt maps (for link source/target type matching)
  let opts_bool : Map[String, @core.Opt[Bool]] = {}
  let opts_string : Map[String, @core.Opt[String]] = {}
  let opts_int : Map[String, @core.Opt[Int]] = {}
  let opts_double : Map[String, @core.Opt[Double]] = {}
  let opts_arr_string : Map[String, @core.Opt[Array[String]]] = {}
  let opts_arr_int : Map[String, @core.Opt[Array[Int]]] = {}
  let opts_arr_double : Map[String, @core.Opt[Array[Double]]] = {}
  // Deferred entries for multi-pass processing
  let deferred_deprecated : Array[Map[String, Json]] = []
  let deferred_clones : Array[Map[String, Json]] = []
  // Pass 1: Register all opts
  for opt_json in opts_json {
    match opt_json {
      Object(obj) => {
        let kind = match obj.get("kind") {
          Some(String(s)) => s
          _ => return Err("opt definition missing 'kind'")
        }
        // deprecated, clone deferred to pass 2/3
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
            // backward compat: "hidden": true -> Hidden
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
        match register_opt_by_kind(
          parser,
          kind,
          name,
          obj,
          description~,
          shorts~,
          global~,
          visibility~,
          aliases~,
          variations~,
          env~,
          entries~,
          opt_refs~,
          deprecate_fns~,
          opt_handles~,
          opts_bool~,
          opts_string~,
          opts_int~,
          opts_double~,
          opts_arr_string~,
          opts_arr_int~,
          opts_arr_double~,
          children~,
        ) {
          Ok(_) => ()
          Err(e) => return Err(e)
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
  // Pass 6: Handle constraints
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

// --- Value extraction ---

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

// --- JSON output formatters ---

///|
fn make_error_json(
  message : String,
  error_context : String,
  tip~ : String = "",
  kind~ : String = "",
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
