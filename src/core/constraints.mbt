///|
/// Declares that the given options are mutually exclusive.
/// Raises `ParseError` if more than one is set after parsing.
pub fn Parser::exclusive(self : Parser, opts : Array[OptRef]) -> Unit {
  let refs = opts
  self.post_hooks.push(fn() raise ParseError {
    let set_names : Array[String] = []
    for opt_ref in refs {
      if (opt_ref.is_set)() {
        set_names.push(opt_ref.name)
      }
    }
    if set_names.length() > 1 {
      raise parse_error(
        "mutually exclusive options: " + set_names.join(", "),
        kind=ArgumentConflict,
      )
    }
  })
}

///|
/// Requires that at least one of the given options is set.
/// Raises `ParseError` if none of them are provided.
pub fn Parser::at_least_one(self : Parser, opts : Array[OptRef]) -> Unit {
  let refs = opts
  self.post_hooks.push(fn() raise ParseError {
    let names : Array[String] = []
    for opt_ref in refs {
      if (opt_ref.is_set)() {
        return
      }
      names.push(opt_ref.name)
    }
    raise parse_error(
      "at least one required: " + names.join(", "),
      kind=AtLeastOneRequired,
    )
  })
}

///|
/// Marks the given option as required.
/// Raises `ParseError` if not set after parsing.
pub fn Parser::required(self : Parser, opt : OptRef) -> Unit {
  let opt_ref = opt
  self.post_hooks.push(fn() raise ParseError {
    if !(opt_ref.is_set)() {
      raise parse_error(
        "required option missing: " + opt_ref.name,
        kind=MissingRequired,
        opt_name=opt_ref.name,
      )
    }
  })
}

///|
/// Declares a dependency: when `source` is set, `target` must also be set.
/// Raises `ParseError` with `msg` (or a generated message) if the dependency is violated.
pub fn Parser::requires(
  self : Parser,
  target : OptRef,
  source~ : OptRef,
  msg? : String = "",
) -> Unit {
  let target_ref = target
  let source_ref = source
  self.post_hooks.push(fn() raise ParseError {
    if (source_ref.is_set)() && !(target_ref.is_set)() {
      let message = if msg != "" {
        msg
      } else {
        source_ref.name + " requires " + target_ref.name
      }
      raise parse_error(
        message,
        kind=DependencyMissing,
        opt_name=target_ref.name,
      )
    }
  })
}
