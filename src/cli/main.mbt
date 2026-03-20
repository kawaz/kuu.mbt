///|
fn main {
  let args = get_argv()
  // Self-hosting: parse kuu-cli's own arguments using kuu core
  let parser = @core.Parser::new()
  parser.set_description("kuu - Language-agnostic CLI argument parser")
  // Global options
  let version_flag = parser.flag(
    name="version",
    description="Show version information",
  )
  // parse subcommand
  let parse_cmd = parser.sub(
    name="parse",
    description="Parse CLI arguments using a JSON schema",
    dashdash=false,
  )
  let parse_schema = parse_cmd.positional(
    name="schema",
    description="Schema file path or - for stdin",
  )
  let parse_dashdash = parse_cmd.dashdash()
  // completions subcommand
  let completions_cmd = parser.sub(
    name="completions",
    description="Generate shell completion script",
  )
  let comp_schema = completions_cmd.positional(
    name="schema",
    description="Schema file path or - for stdin",
  )
  let comp_shell = completions_cmd.string(
    name="shell",
    description="Shell type (bash/zsh/fish)",
    default="zsh",
  )
  let comp_command = completions_cmd.string(
    name="command",
    description="Command name for the completion script",
    default="myapp",
  )
  // validate subcommand
  let validate_cmd = parser.sub(
    name="validate",
    description="Validate a JSON schema",
  )
  let val_schema = validate_cmd.positional(
    name="schema",
    description="Schema file path or - for stdin",
  )
  // Parse argv
  let result : Result[@core.ParseResult, @core.ParseError] = try? parser.parse(
    args,
  )
  match result {
    Ok(parse_result) => {
      // --version
      if version_flag.get() == Some(true) {
        println(get_program_name() + " 0.1.0")
        return
      }
      // parse subcommand
      match parse_result.child("parse") {
        Some(_) => {
          let schema_path = match parse_schema.get() {
            Some(s) =>
              if s == "" {
                write_stderr_ffi(
                  "error: schema path is required\nUsage: kuu parse <schema> [-- <args>...]\n",
                )
                exit_ffi(1)
                return
              } else {
                s
              }
            None => {
              write_stderr_ffi(
                "error: schema path is required\nUsage: kuu parse <schema> [-- <args>...]\n",
              )
              exit_ffi(1)
              return // unreachable, but needed for type checker
            }
          }
          let schema_json = if schema_path == "-" {
            read_stdin_ffi()
          } else {
            let content = read_file_ffi(schema_path)
            if content == "" {
              write_stderr_ffi(
                "error: could not read file: " + schema_path + "\n",
              )
              exit_ffi(1)
              return
            }
            content
          }
          // If extra args after -- are provided, inject them into the schema
          let extra_args = parse_dashdash.get()
          let output = match extra_args {
            Some(extra) =>
              if extra.length() > 0 {
                kuu_parse_with_args(schema_json, extra)
              } else {
                kuu_parse(schema_json)
              }
            None => kuu_parse(schema_json)
          }
          println(output)
          return
        }
        None => ()
      }
      // completions subcommand
      match parse_result.child("completions") {
        Some(_) => {
          let schema_path = match comp_schema.get() {
            Some(s) =>
              if s == "" {
                write_stderr_ffi(
                  "error: schema path is required\nUsage: kuu completions [--shell <shell>] [--command <name>] <schema>\n",
                )
                exit_ffi(1)
                return
              } else {
                s
              }
            None => {
              write_stderr_ffi(
                "error: schema path is required\nUsage: kuu completions [--shell <shell>] [--command <name>] <schema>\n",
              )
              exit_ffi(1)
              return
            }
          }
          let schema_json = if schema_path == "-" {
            read_stdin_ffi()
          } else {
            let content = read_file_ffi(schema_path)
            if content == "" {
              write_stderr_ffi(
                "error: could not read file: " + schema_path + "\n",
              )
              exit_ffi(1)
              return
            }
            content
          }
          let shell = comp_shell.get().unwrap_or("zsh")
          let command_name = comp_command.get().unwrap_or("myapp")
          let output = kuu_completions(schema_json, shell, command_name)
          println(output)
          return
        }
        None => ()
      }
      // validate subcommand
      match parse_result.child("validate") {
        Some(_) => {
          let schema_path = match val_schema.get() {
            Some(s) =>
              if s == "" {
                write_stderr_ffi(
                  "error: schema path is required\nUsage: kuu validate <schema>\n",
                )
                exit_ffi(1)
                return
              } else {
                s
              }
            None => {
              write_stderr_ffi(
                "error: schema path is required\nUsage: kuu validate <schema>\n",
              )
              exit_ffi(1)
              return
            }
          }
          let schema_json = if schema_path == "-" {
            read_stdin_ffi()
          } else {
            let content = read_file_ffi(schema_path)
            if content == "" {
              write_stderr_ffi(
                "error: could not read file: " + schema_path + "\n",
              )
              exit_ffi(1)
              return
            }
            content
          }
          let output = kuu_validate(schema_json)
          println(output)
          return
        }
        None => ()
      }
      // No subcommand: show help (same as --help)
      println(parser.generate_help())
    }
    Err(@core.HelpRequested(text)) => {
      println(text)
    }
    Err(@core.ParseError(info)) => {
      write_stderr_ffi("error: " + info.message + "\n")
      if info.error_context != "" {
        write_stderr_ffi(info.error_context + "\n")
      }
      if info.tip != "" {
        write_stderr_ffi("tip: " + info.tip + "\n")
      }
      exit_ffi(1)
    }
  }
}

// --- Schema parsing helpers ---

///|
/// Parse JSON string into a validated schema object.
/// Returns the parsed JSON object or an error message.
fn parse_schema_json(input : String) -> Result[Map[String, Json], String] {
  let parse_json_result : Result[Json, _] = try? @json.parse(input.view())
  let json : Json = match parse_json_result {
    Ok(j) => j
    Err(_) => return Err("invalid input JSON")
  }
  let obj = match json {
    Object(o) => o
    _ => return Err("input must be a JSON object")
  }
  // Validate schema version
  match obj.get("version") {
    Some(Number(n, ..)) => {
      let ver = n.to_int()
      if ver != 1 {
        return Err("unsupported schema version: " + ver.to_string())
      }
    }
    None => () // omitted: treat as version 1 (backward compat)
    _ => return Err("'version' must be a number")
  }
  Ok(obj)
}

///|
/// Build a parser from a schema object. Returns (parser, schema_result).
fn build_parser_from_schema(
  obj : Map[String, Json],
) -> Result[(@core.Parser, SchemaResult), String] {
  let opts_json : Array[Json] = match obj.get("opts") {
    Some(Array(arr)) => arr
    Some(_) => return Err("'opts' must be an array")
    None => []
  }
  let description = match obj.get("description") {
    Some(String(s)) => s
    _ => ""
  }
  let has_dashdash_kind = has_dashdash_opt(opts_json)
  let parser = @core.Parser::new(dashdash=not(has_dashdash_kind))
  if description != "" {
    parser.set_description(description)
  }
  match obj.get("env_prefix") {
    Some(String(prefix)) => parser.env_prefix(prefix)
    _ => ()
  }
  match obj.get("auto_env") {
    Some(True) => parser.auto_env(true)
    _ => ()
  }
  let schema = match build_parser(parser, opts_json, obj) {
    Ok(s) => s
    Err(msg) => return Err(msg)
  }
  Ok((parser, schema))
}

// --- Subcommand implementations ---

///|
/// Main parse entry point: receives JSON input, returns JSON output.
/// Same protocol as WASM bridge kuu_parse.
fn kuu_parse(input : String) -> String {
  let obj = match parse_schema_json(input) {
    Ok(o) => o
    Err(msg) => return make_error_json(msg, "")
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
  let (parser, schema) = match build_parser_from_schema(obj) {
    Ok(pair) => pair
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
/// Parse with explicit args (from -- separator).
/// Injects args into the schema JSON, overriding any existing "args" field.
fn kuu_parse_with_args(schema_json : String, args : Array[String]) -> String {
  // Parse the schema JSON to inject args
  let parse_json_result : Result[Json, _] = try? @json.parse(schema_json.view())
  let obj = match parse_json_result {
    Ok(Object(o)) => o
    Ok(_) => return make_error_json("input must be a JSON object", "")
    Err(_) => return make_error_json("invalid input JSON", "")
  }
  // Override args
  let json_args : Array[Json] = args.map(fn(s) -> Json { Json::string(s) })
  obj["args"] = Json::array(json_args)
  // Re-stringify and parse through kuu_parse
  kuu_parse(Json::object(obj).stringify())
}

///|
/// Completions entry point: generates shell completion script from schema.
fn kuu_completions(
  schema_json : String,
  shell : String,
  command_name : String,
) -> String {
  let obj = match parse_schema_json(schema_json) {
    Ok(o) => o
    Err(msg) => return "# Error: " + msg + "\n"
  }
  let (parser, _schema) = match build_parser_from_schema(obj) {
    Ok(pair) => pair
    Err(msg) => return "# Error: " + msg + "\n"
  }
  parser.generate_completion_script(shell~, command_name~)
}

///|
/// Validate entry point: checks if a schema is valid.
fn kuu_validate(schema_json : String) -> String {
  let obj = match parse_schema_json(schema_json) {
    Ok(o) => o
    Err(msg) => {
      let r : Map[String, Json] = {}
      r["ok"] = Json::boolean(false)
      r["error"] = Json::string(msg)
      return Json::object(r).stringify()
    }
  }
  match build_parser_from_schema(obj) {
    Ok(_) => {
      let r : Map[String, Json] = {}
      r["ok"] = Json::boolean(true)
      Json::object(r).stringify()
    }
    Err(msg) => {
      let r : Map[String, Json] = {}
      r["ok"] = Json::boolean(false)
      r["error"] = Json::string(msg)
      Json::object(r).stringify()
    }
  }
}
