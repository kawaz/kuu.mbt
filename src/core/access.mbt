///|
pub fn[T] Opt::get(self : Opt[T]) -> T? {
  if self.parsed.val {
    Some((self.getter)())
  } else {
    None
  }
}

///|
pub fn ParseResult::as_map(self : ParseResult) -> Map[String, ParseResult]? {
  match self.kind {
    Map_(m) => Some(m)
    _ => None
  }
}

///|
pub fn ParseResult::as_list(self : ParseResult) -> Array[ParseResult]? {
  match self.kind {
    List_(l) => Some(l)
    _ => None
  }
}

///|
pub fn ParseResult::child(self : ParseResult, key : String) -> ParseResult? {
  match self.kind {
    Map_(m) => m.get(key)
    _ => None
  }
}

///|
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
  if not(self.parsed.val) {
    None
  } else {
    Some((opt.getter)())
  }
}
