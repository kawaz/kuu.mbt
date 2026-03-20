///|
fn main {
  let input = read_stdin_ffi()
  let result = kuu_parse(input)
  println(result)
}

///|
/// Main parse entry point: receives JSON input, returns JSON output.
/// Same protocol as WASM bridge kuu_parse.
fn kuu_parse(input : String) -> String {
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
  // Check if opts contain explicit "dashdash" kind
  let has_dashdash_kind = has_dashdash_opt(opts_json)
  // Build parser from schema
  let parser = @core.Parser::new(dashdash=not(has_dashdash_kind))
  if description != "" {
    parser.set_description(description)
  }
  // Handle env_prefix (must be before build_parser)
  match obj.get("env_prefix") {
    Some(String(prefix)) => parser.env_prefix(prefix)
    _ => ()
  }
  // Handle auto_env (must be before build_parser)
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
