///|
/// myhttp — A simple HTTP client CLI demonstrating kuu DX layer.
///
/// Usage:
///   myhttp [options] get <url>
///   myhttp [options] post <url> --data <body>
///
/// This example showcases the struct-first DX API:
/// - Parseable trait implementation
/// - Subcommands with nested options
/// - Various option types: flag, string, int, count, append_string, boolean
/// - Constraints: exclusive, required
/// - Global options, shorts, aliases
struct Config {
  mut verbose : Int
  mut format : String
  mut compact : Bool
  mut timeout : Int
  mut follow_redirects : Bool
  mut command : Command
  mut get_url : String
  mut get_accept : String
  mut post_url : String
  mut post_data : String
  mut post_content_type : String
  mut post_header : Array[String]
} derive(Show, Eq)

enum Command {
  None
  Get
  Post
} derive(Show, Eq)

fn Config::default() -> Config {
  {
    verbose: 0,
    format: "text",
    compact: false,
    timeout: 30,
    follow_redirects: true,
    command: None,
    get_url: "",
    get_accept: "*/*",
    post_url: "",
    post_data: "",
    post_content_type: "application/json",
    post_header: [],
  }
}

impl @dx.Parseable for Config with register(self, reg) {
  // --- Global options ---
  reg.set_description("A simple HTTP client")
  reg.count(name="verbose", shorts="v", global=true, set=fn(v) { self.verbose = v })
  let format_ref = reg.string_ref(
    name="format",
    default="text",
    description="Output format",
    global=true,
    set=fn(v) { self.format = v },
  )
  let compact_ref = reg.flag_ref(
    name="compact",
    description="Compact output (exclusive with --format)",
    global=true,
    set=fn(v) { self.compact = v },
  )
  reg.exclusive([format_ref, compact_ref])
  reg.int(
    name="timeout",
    shorts="t",
    default=30,
    description="Request timeout in seconds",
    global=true,
    set=fn(v) { self.timeout = v },
  )
  reg.boolean(
    name="follow-redirects",
    default=true,
    aliases=["follow"],
    description="Follow HTTP redirects",
    global=true,
    set=fn(v) { self.follow_redirects = v },
  )

  // --- GET subcommand ---
  reg.sub(
    name="get",
    description="Send a GET request",
    on_match=fn() { self.command = Get },
    setup=fn(r) {
      r.positional(name="url", description="Request URL", set=fn(v) { self.get_url = v })
      r.string(
        name="accept",
        default="*/*",
        description="Accept header value",
        set=fn(v) { self.get_accept = v },
      )
    },
  )

  // --- POST subcommand ---
  reg.sub(
    name="post",
    description="Send a POST request",
    on_match=fn() { self.command = Post },
    setup=fn(r) {
      r.positional(
        name="url",
        description="Request URL",
        set=fn(v) { self.post_url = v },
      )
      let data_ref = r.string_ref(
        name="data",
        shorts="d",
        description="Request body",
        set=fn(v) { self.post_data = v },
      )
      r.required(data_ref)
      r.string(
        name="content-type",
        default="application/json",
        aliases=["ct"],
        description="Content-Type header",
        set=fn(v) { self.post_content_type = v },
      )
      r.append_string(
        name="header",
        shorts="H",
        description="Additional headers",
        set=fn(v) { self.post_header = v },
      )
    },
  )

  reg.require_cmd()
}

fn main {
  let config = Config::default()
  let result : Result[Unit, @core.ParseError] = try? @dx.parse_into(
    ["get", "https://example.com", "--accept", "application/json", "-vv"],
    config,
  )
  match result {
    Ok(_) => println("Config: \{config}")
    Err(@core.ParseError(info)) => println("Error: \{info.to_string()}")
    Err(@core.HelpRequested(help)) => println(help)
  }
}
