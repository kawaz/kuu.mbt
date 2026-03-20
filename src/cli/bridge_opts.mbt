///|
/// Register an opt by kind into the parser.
/// Called from build_parser Pass 1 for each non-deferred opt entry.
fn register_opt_by_kind(
  parser : @core.Parser,
  kind : String,
  name : String,
  obj : Map[String, Json],
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_bool~ : Map[String, @core.Opt[Bool]],
  opts_string~ : Map[String, @core.Opt[String]],
  opts_int~ : Map[String, @core.Opt[Int]],
  opts_double~ : Map[String, @core.Opt[Double]],
  opts_arr_string~ : Map[String, @core.Opt[Array[String]]],
  opts_arr_int~ : Map[String, @core.Opt[Array[Int]]],
  opts_arr_double~ : Map[String, @core.Opt[Array[Double]]],
  children~ : Map[String, SchemaResult],
) -> Result[Unit, String] {
  match kind {
    "flag" =>
      register_flag(
        parser, name, obj, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_bool~,
      )
    "string" =>
      register_string(
        parser, name, obj, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_string~,
      )
    "int" =>
      register_int(
        parser, name, obj, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_int~,
      )
    "float" =>
      register_float(
        parser, name, obj, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_double~,
      )
    "boolean" =>
      register_boolean(
        parser, name, obj, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_bool~,
      )
    "count" =>
      register_count(
        parser, name, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_int~,
      )
    "append_string" =>
      register_append_string(
        parser, name, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_arr_string~,
      )
    "append_int" =>
      register_append_int(
        parser, name, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_arr_int~,
      )
    "append_float" =>
      register_append_float(
        parser, name, description~, shorts~, global~, visibility~,
        aliases~, variations~, env~, entries~, opt_refs~, deprecate_fns~,
        opt_handles~, opts_arr_double~,
      )
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
      Ok(())
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
      Ok(())
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
      Ok(())
    }
    "serial" => {
      let child_opts : Array[Json] = match obj.get("opts") {
        Some(Array(arr)) => arr
        _ => []
      }
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
      Ok(())
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
      let child_result = match build_parser(child_parser, child_opts, obj) {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      children[name] = child_result
      Ok(())
    }
    _ => Err("unknown opt kind: " + kind)
  }
}

// --- Individual opt kind registrations ---

///|
fn register_flag(
  parser : @core.Parser,
  name : String,
  obj : Map[String, Json],
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_bool~ : Map[String, @core.Opt[Bool]],
) -> Result[Unit, String] {
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
  Ok(())
}

///|
fn register_string(
  parser : @core.Parser,
  name : String,
  obj : Map[String, Json],
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_string~ : Map[String, @core.Opt[String]],
) -> Result[Unit, String] {
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
  Ok(())
}

///|
fn register_int(
  parser : @core.Parser,
  name : String,
  obj : Map[String, Json],
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_int~ : Map[String, @core.Opt[Int]],
) -> Result[Unit, String] {
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
  Ok(())
}

///|
fn register_float(
  parser : @core.Parser,
  name : String,
  obj : Map[String, Json],
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_double~ : Map[String, @core.Opt[Double]],
) -> Result[Unit, String] {
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
  Ok(())
}

///|
fn register_boolean(
  parser : @core.Parser,
  name : String,
  obj : Map[String, Json],
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_bool~ : Map[String, @core.Opt[Bool]],
) -> Result[Unit, String] {
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
  Ok(())
}

///|
fn register_count(
  parser : @core.Parser,
  name : String,
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_int~ : Map[String, @core.Opt[Int]],
) -> Result[Unit, String] {
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
  Ok(())
}

///|
fn register_append_string(
  parser : @core.Parser,
  name : String,
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_arr_string~ : Map[String, @core.Opt[Array[String]]],
) -> Result[Unit, String] {
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
  Ok(())
}

///|
fn register_append_int(
  parser : @core.Parser,
  name : String,
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_arr_int~ : Map[String, @core.Opt[Array[Int]]],
) -> Result[Unit, String] {
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
  Ok(())
}

///|
fn register_append_float(
  parser : @core.Parser,
  name : String,
  description~ : String,
  shorts~ : String,
  global~ : Bool,
  visibility~ : @core.Visibility,
  aliases~ : Array[String],
  variations~ : Array[@core.Variation],
  env~ : String,
  entries~ : Array[OptEntry],
  opt_refs~ : Map[String, @core.OptRef],
  deprecate_fns~ : Map[String, (String, String) -> Unit],
  opt_handles~ : Map[String, OptHandle],
  opts_arr_double~ : Map[String, @core.Opt[Array[Double]]],
) -> Result[Unit, String] {
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
  Ok(())
}
