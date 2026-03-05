fn main {
  let p = @core.Parser::new()
  p.set_description("test")
  let _verbose = p.flag(name="verbose", short='v', description="Verbose")
  let _port = p.int_opt(name="port", default=8080, description="Port")
  let _host = p.string_opt(name="host", default="localhost", description="Host")
  let _tags = p.append_string(name="tag", description="Tags")
  let _nums = p.append_int(name="num", description="Numbers")
  let _count = p.count(name="count", short='c', description="Count")
  let _file = p.positional(name="file", description="File")
  let _rest = p.rest(name="args", description="Rest args")
  let _serve = p.cmd(name="serve", setup=fn(child) {
    let _ = child.int_opt(name="port", default=3000)
  }, description="Serve")
  let result : Result[@core.ParseResult, _] = try? p.parse(["--verbose"])
  match result {
    Ok(r) => {
      let _ = r.get(_verbose)
      let _ = r.child("serve")
      let _ = r.as_map()
    }
    Err(@core.HelpRequested(text)) => {
      let _ = text
    }
    Err(@core.ParseError(info)) => {
      let _ = info.to_string()
    }
  }
}
