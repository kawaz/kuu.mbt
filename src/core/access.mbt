///|
/// Returns the parsed value of this option, or `None` if parsing has not completed.
/// After `parse()` succeeds, always returns `Some(value)` (including the default).
pub fn[T] Opt::get(self : Opt[T]) -> T? {
  if self.parsed.val {
    Some((self.accessor.get)())
  } else {
    None
  }
}

///|
/// Returns `true` if this option was explicitly provided by the user
/// or resolved from an environment variable.
/// Returns `false` if only the default value is in effect.
pub fn[T] Opt::is_set(self : Opt[T]) -> Bool {
  (self.used)()
}

///|
/// Attempts to interpret this result as a key-value map (e.g. from a subcommand's values).
/// Returns `None` if the underlying kind is not `Map_`.
pub fn ParseResult::as_map(self : ParseResult) -> Map[String, ParseResult]? {
  match self.kind {
    Map_(m) => Some(m)
    _ => None
  }
}

///|
/// Attempts to interpret this result as an ordered list.
/// Returns `None` if the underlying kind is not `List_`.
pub fn ParseResult::as_list(self : ParseResult) -> Array[ParseResult]? {
  match self.kind {
    List_(l) => Some(l)
    _ => None
  }
}

///|
/// Looks up a child entry by key in a map-typed result.
/// Shorthand for `self.as_map()?.get(key)`.
pub fn ParseResult::child(self : ParseResult, key : String) -> ParseResult? {
  match self.kind {
    Map_(m) => m.get(key)
    _ => None
  }
}

///|
/// Looks up an element by index in a list-typed result.
/// Returns `None` if the index is out of bounds or the kind is not `List_`.
pub fn ParseResult::at(self : ParseResult, index : Int) -> ParseResult? {
  match self.kind {
    List_(l) =>
      if index >= 0 && index < l.length() {
        Some(l[index])
      } else {
        None
      }
    _ => None
  }
}

///|
/// Deprecated: Use `opt.get()` instead. This method delegates to Parser::get()
/// which only checks the parser's own parsed state, not the opt's owning parser.
pub fn[T] ParseResult::get(self : ParseResult, opt : Opt[T]) -> T? {
  self.parser.get(opt)
}

///|
/// Returns the list of deprecated option usages recorded during parsing.
/// Each entry is a (name, msg) tuple where name is the deprecated option name
/// and msg is the deprecation message provided by the developer.
pub fn Parser::deprecated_warnings(self : Parser) -> Array[(String, String)] {
  self.deprecated_usages
}

///|
/// Deprecated: Use `opt.get()` instead. This method checks this parser's parsed
/// state, which may differ from the opt's owning parser (e.g. for subcommand opts).
pub fn[T] Parser::get(self : Parser, opt : Opt[T]) -> T? {
  if !(self.parsed.val) {
    None
  } else {
    Some((opt.accessor.get)())
  }
}
