// sf-b-ref: Ref バインド方式 struct-first CLIパーサ PoC

// === RefBinder ===

struct RefBinder {
  parser : @core.Parser
  copiers : Array[() -> Unit]
}

fn RefBinder::new() -> RefBinder {
  { parser: @core.Parser::new(), copiers: [] }
}

fn RefBinder::flag(
  self : RefBinder,
  name~ : String,
  target~ : Ref[Bool],
  global? : Bool = false,
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = self.parser.flag(name~, global~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::string(
  self : RefBinder,
  name~ : String,
  target~ : Ref[String],
  default? : String = "",
  global? : Bool = false,
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = self.parser.string_opt(name~, default~, global~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::int(
  self : RefBinder,
  name~ : String,
  target~ : Ref[Int],
  default? : Int = 0,
  global? : Bool = false,
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = self.parser.int_opt(name~, default~, global~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::count(
  self : RefBinder,
  name~ : String,
  target~ : Ref[Int],
  global? : Bool = false,
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = self.parser.count(name~, global~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::append_string(
  self : RefBinder,
  name~ : String,
  target~ : Ref[Array[String]],
  global? : Bool = false,
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = self.parser.append_string(name~, global~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::sub(
  self : RefBinder,
  name~ : String,
  description? : String = "",
) -> @core.Parser {
  self.parser.sub(name~, description~)
}

fn RefBinder::positional(
  self : RefBinder,
  parser~ : @core.Parser,
  name~ : String,
  target~ : Ref[String],
  description? : String = "",
) -> Unit {
  let opt = parser.positional(name~, description~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::sub_flag(
  self : RefBinder,
  parser~ : @core.Parser,
  name~ : String,
  target~ : Ref[Bool],
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = parser.flag(name~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::sub_string(
  self : RefBinder,
  parser~ : @core.Parser,
  name~ : String,
  target~ : Ref[String],
  default? : String = "",
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = parser.string_opt(name~, default~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::sub_int(
  self : RefBinder,
  parser~ : @core.Parser,
  name~ : String,
  target~ : Ref[Int],
  default? : Int = 0,
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = parser.int_opt(name~, default~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::sub_count(
  self : RefBinder,
  parser~ : @core.Parser,
  name~ : String,
  target~ : Ref[Int],
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = parser.count(name~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::sub_append_string(
  self : RefBinder,
  parser~ : @core.Parser,
  name~ : String,
  target~ : Ref[Array[String]],
  description? : String = "",
  shorts? : String = "",
) -> Unit {
  let opt = parser.append_string(name~, description~, shorts~)
  self.copiers.push(fn() {
    match opt.get() {
      Some(v) => target.val = v
      None => ()
    }
  })
}

fn RefBinder::require_cmd(self : RefBinder) -> Unit {
  self.parser.require_cmd()
}

fn RefBinder::parse(
  self : RefBinder,
  args : Array[String],
) -> @core.ParseResult raise @core.ParseError {
  let result = self.parser.parse(args)
  for copier in self.copiers {
    copier()
  }
  result
}

// === Git demo structs ===

struct GitGlobal {
  verbose : Ref[Bool]
  config_entries : Ref[Array[String]]
}

fn GitGlobal::new() -> GitGlobal {
  { verbose: { val: false }, config_entries: { val: [] } }
}

struct CloneOpts {
  url : Ref[String]
  depth : Ref[Int]
  branch : Ref[String]
}

fn CloneOpts::new() -> CloneOpts {
  { url: { val: "" }, depth: { val: 0 }, branch: { val: "" } }
}

struct CommitOpts {
  message : Ref[String]
  all : Ref[Bool]
}

fn CommitOpts::new() -> CommitOpts {
  { message: { val: "" }, all: { val: false } }
}

struct LogOpts {
  oneline : Ref[Bool]
  count : Ref[Int]
}

fn LogOpts::new() -> LogOpts {
  { oneline: { val: false }, count: { val: 0 } }
}

struct RemoteAddOpts {
  name : Ref[String]
  url : Ref[String]
}

fn RemoteAddOpts::new() -> RemoteAddOpts {
  { name: { val: "" }, url: { val: "" } }
}

struct RemoteRemoveOpts {
  name : Ref[String]
}

fn RemoteRemoveOpts::new() -> RemoteRemoveOpts {
  { name: { val: "" } }
}

// === main ===

fn main {
  println("sf-b-ref: Ref bind struct-first CLI parser PoC")
}
