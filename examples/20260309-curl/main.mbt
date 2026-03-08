///|
/// curl — A sample curl-like CLI built with kuu to exercise flat option parsing.
///
/// 200+ options を持つ curl をモデルに、kuu の表現力を検証:
///   - 大量のフラグ・値付きオプション定義
///   - append_string による繰り返しオプション (-H, -d, -F)
///   - variation_false による --no-xxx 反転パターン
///   - flag, string_opt, int_opt の各種パラメータ
///   - rest による複数ポジショナル引数 (URL)
///   - サブコマンドなしのフラットな構造
fn main {
  let scenarios : Array[(String, Array[String])] = [
    ("Basic GET", ["https://example.com"]),
    (
      "POST with JSON",
      [
        "-X",
        "POST",
        "-H",
        "Content-Type: application/json",
        "-d",
        "{\"key\": \"value\"}",
        "https://api.example.com",
      ],
    ),
    (
      "Repeatable headers",
      [
        "-H",
        "Accept: application/json",
        "-H",
        "X-Custom: foo",
        "-H",
        "X-Custom: bar",
        "https://example.com",
      ],
    ),
    (
      "--no-xxx inversion (last wins)",
      [
        "--verbose",
        "--no-verbose",
        "-L",
        "--no-location",
        "https://example.com",
      ],
    ),
    (
      "Multiple URLs",
      ["https://example.com", "https://example.org", "https://example.net"],
    ),
    (
      "Complex scenario",
      [
        "-X",
        "PUT",
        "-H",
        "Authorization: Bearer xxx",
        "-d",
        "@data.json",
        "--retry",
        "5",
        "--connect-timeout",
        "10",
        "-k",
        "-L",
        "--max-redirs",
        "3",
        "-o",
        "result.json",
        "https://api.example.com/upload",
      ],
    ),
    ("Help display", ["--help"]),
    (
      "Silent + Verbose (coexist)",
      ["-s", "-v", "https://example.com"],
    ),
  ]
  for i, scenario in scenarios {
    let (name, args) = scenario
    if i > 0 {
      println("")
    }
    println(
      "\u{2501}\u{2501}\u{2501} Scenario: " +
      name +
      " \u{2501}\u{2501}\u{2501}",
    )
    println("Args: " + args.to_string())
    let result = run(args)
    match result {
      Ok(_) => ()
      Err(msg) => println(msg)
    }
  }
}

///|
fn run(args : Array[String]) -> Result[Unit, String] {
  let p = @core.Parser::new()
  p.set_description("curl - transfer a URL")

  // ─── HTTP Method & Request Control ───

  let request = p.string_opt(
    name="request", default="", shorts="X",
    description="HTTP method to use",
    value_name="METHOD",
  )
  let data = p.append_string(
    name="data", shorts="d",
    description="HTTP POST data",
  )
  let data_raw = p.append_string(
    name="data-raw",
    description="HTTP POST data (@ treated literally)",
  )
  let data_urlencode = p.append_string(
    name="data-urlencode",
    description="URL-encode HTTP POST data",
  )
  let form = p.append_string(
    name="form", shorts="F",
    description="Multipart form data",
  )
  let json_data = p.append_string(
    name="json",
    description="JSON POST data (sets Content-Type automatically)",
  )
  let upload_file = p.string_opt(
    name="upload-file", default="", shorts="T",
    description="Upload file via PUT",
    value_name="FILE",
  )

  // ─── Headers & Authentication ───

  let header = p.append_string(
    name="header", shorts="H",
    description="Custom request header",
  )
  let user_agent = p.string_opt(
    name="user-agent", default="", shorts="A",
    description="User-Agent header",
    value_name="AGENT",
  )
  let referer = p.string_opt(
    name="referer", default="", shorts="e",
    description="Referer header",
    value_name="URL",
  )
  let user = p.string_opt(
    name="user", default="", shorts="u",
    description="Server user:password",
    value_name="USER:PASS",
  )
  let oauth2_bearer = p.string_opt(
    name="oauth2-bearer", default="",
    description="OAuth 2.0 Bearer token",
    value_name="TOKEN",
  )

  // ─── Output Control ───

  let output = p.string_opt(
    name="output", default="", shorts="o",
    description="Write output to file",
    value_name="FILE",
  )
  let remote_name = p.flag(
    name="remote-name", shorts="O",
    description="Save with remote filename",
  )
  let output_dir = p.string_opt(
    name="output-dir", default="",
    description="Output directory",
    value_name="DIR",
  )
  let silent = p.flag(
    name="silent", shorts="s",
    description="Silent mode",
    variation_false=Some("no"),
  )
  let show_error = p.flag(
    name="show-error", shorts="S",
    description="Show error even with --silent",
    variation_false=Some("no"),
  )
  let verbose = p.flag(
    name="verbose", shorts="v",
    description="Verbose output",
    variation_false=Some("no"),
  )
  let write_out = p.string_opt(
    name="write-out", default="", shorts="w",
    description="Output format after transfer",
    value_name="FORMAT",
  )
  let show_headers = p.flag(
    name="show-headers", shorts="i",
    aliases=["include"],
    description="Show response headers in output",
    variation_false=Some("no"),
  )

  // ─── Connection & Timeout ───

  // Design rationale: curl は小数秒（例: 1.5）を受け付けるため string_opt を使用。
  // kuu に float_opt がないため。
  let connect_timeout = p.string_opt(
    name="connect-timeout", default="",
    description="Connection timeout (seconds)",
    value_name="SECONDS",
  )
  // Design rationale: curl は小数秒（例: 1.5）を受け付けるため string_opt を使用。
  // kuu に float_opt がないため。
  let max_time = p.string_opt(
    name="max-time", default="", shorts="m",
    description="Maximum transfer time (seconds)",
    value_name="SECONDS",
  )
  let retry = p.int_opt(
    name="retry", default=0,
    description="Number of retries on transient errors",
    value_name="NUM",
  )
  let retry_delay = p.int_opt(
    name="retry-delay", default=0,
    description="Delay between retries (seconds)",
    value_name="SECONDS",
  )
  let retry_max_time = p.int_opt(
    name="retry-max-time", default=0,
    description="Maximum retry time (seconds)",
    value_name="SECONDS",
  )
  let limit_rate = p.string_opt(
    name="limit-rate", default="",
    description="Transfer speed limit (e.g. 100K, 1M)",
    value_name="SPEED",
  )

  // ─── TLS/SSL ───

  let insecure = p.flag(
    name="insecure", shorts="k",
    description="Allow insecure SSL connections",
    variation_false=Some("no"),
  )
  let cacert = p.string_opt(
    name="cacert", default="",
    description="CA certificate file",
    value_name="FILE",
  )
  let cert = p.string_opt(
    name="cert", default="", shorts="E",
    description="Client certificate",
    value_name="CERT[:PASSWD]",
  )

  // ─── Proxy ───

  let proxy = p.string_opt(
    name="proxy", default="", shorts="x",
    description="Proxy server",
    value_name="[protocol://]host[:port]",
  )
  let proxy_user = p.string_opt(
    name="proxy-user", default="", shorts="U",
    description="Proxy authentication",
    value_name="USER:PASS",
  )
  let noproxy = p.string_opt(
    name="noproxy", default="",
    description="Hosts that bypass proxy (comma-separated)",
    value_name="HOSTS",
  )

  // ─── Redirect & Cookie ───

  let location = p.flag(
    name="location", shorts="L",
    description="Follow redirects",
    variation_false=Some("no"),
  )
  let max_redirs = p.int_opt(
    name="max-redirs", default=50,
    description="Maximum number of redirects",
    value_name="NUM",
  )
  let cookie = p.string_opt(
    name="cookie", default="", shorts="b",
    description="Send cookies (name=value or filename)",
    value_name="DATA|FILE",
  )
  let cookie_jar = p.string_opt(
    name="cookie-jar", default="", shorts="c",
    description="Save cookies to file",
    value_name="FILE",
  )

  // ─── Misc Flags ───

  let compressed = p.flag(
    name="compressed",
    description="Request compressed response",
    variation_false=Some("no"),
  )
  let head = p.flag(
    name="head", shorts="I",
    description="HEAD request (headers only)",
    variation_false=Some("no"),
  )
  let http2 = p.flag(
    name="http2",
    description="Use HTTP/2",
    variation_false=Some("no"),
  )
  let fail = p.flag(
    name="fail", shorts="f",
    description="Fail silently on HTTP errors",
    variation_false=Some("no"),
  )
  let fail_with_body = p.flag(
    name="fail-with-body",
    description="Fail on HTTP errors but show body",
    variation_false=Some("no"),
  )
  // Design rationale: --no-buffer is curl's primary form; --buffer doesn't exist.
  // Modeled as a simple flag named "no-buffer" since there's no positive counterpart.
  let no_buffer = p.flag(
    name="no-buffer", shorts="N",
    description="Disable output buffering",
  )

  // Design rationale: curl では -s と -v は共存可能。
  // また exclusive + variation_false は --silent --no-verbose で誤発火するため、
  // 排他制約は設定しない。exclusive のデモは他の example で十分カバーされている。

  // ─── Positional Arguments (URL) ───

  let url = p.rest(name="url", description="URL(s) to transfer")

  // ─── Parse ───

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(args)
  match result {
    Err(@core.HelpRequested(text)) => {
      println(text)
      return Ok(())
    }
    Err(@core.ParseError(info)) => return Err("Error: " + info.message)
    Ok(_) => ()
  }

  // ─── Display Results ───

  println("=== HTTP Method & Request ===")
  print_str("request (-X)", request)
  print_arr("data (-d)", data)
  print_arr("data-raw", data_raw)
  print_arr("data-urlencode", data_urlencode)
  print_arr("form (-F)", form)
  print_arr("json", json_data)
  print_str("upload-file (-T)", upload_file)

  println("")
  println("=== Headers & Auth ===")
  print_arr("header (-H)", header)
  print_str("user-agent (-A)", user_agent)
  print_str("referer (-e)", referer)
  print_str("user (-u)", user)
  print_str("oauth2-bearer", oauth2_bearer)

  println("")
  println("=== Output Control ===")
  print_str("output (-o)", output)
  print_bool("remote-name (-O)", remote_name)
  print_str("output-dir", output_dir)
  print_bool("silent (-s)", silent)
  print_bool("show-error (-S)", show_error)
  print_bool("verbose (-v)", verbose)
  print_str("write-out (-w)", write_out)
  print_bool("show-headers (-i)", show_headers)

  println("")
  println("=== Connection & Timeout ===")
  print_str("connect-timeout", connect_timeout)
  print_str("max-time (-m)", max_time)
  print_int("retry", retry)
  print_int("retry-delay", retry_delay)
  print_int("retry-max-time", retry_max_time)
  print_str("limit-rate", limit_rate)

  println("")
  println("=== TLS/SSL ===")
  print_bool("insecure (-k)", insecure)
  print_str("cacert", cacert)
  print_str("cert (-E)", cert)

  println("")
  println("=== Proxy ===")
  print_str("proxy (-x)", proxy)
  print_str("proxy-user (-U)", proxy_user)
  print_str("noproxy", noproxy)

  println("")
  println("=== Redirect & Cookie ===")
  print_bool("location (-L)", location)
  print_int("max-redirs", max_redirs)
  print_str("cookie (-b)", cookie)
  print_str("cookie-jar (-c)", cookie_jar)

  println("")
  println("=== Misc Flags ===")
  print_bool("compressed", compressed)
  print_bool("head (-I)", head)
  print_bool("http2", http2)
  print_bool("fail (-f)", fail)
  print_bool("fail-with-body", fail_with_body)
  print_bool("no-buffer (-N)", no_buffer)

  println("")
  println("=== Positional ===")
  print_arr("url", url)

  Ok(())
}

///|
fn print_str(label : String, opt : @core.Opt[String]) -> Unit {
  let v = opt.get().unwrap()
  if v != "" {
    println("  " + label + ": " + v)
  }
}

///|
fn print_bool(label : String, opt : @core.Opt[Bool]) -> Unit {
  if opt.get().unwrap() {
    println("  " + label + ": true")
  }
}

///|
fn print_int(label : String, opt : @core.Opt[Int]) -> Unit {
  let v = opt.get().unwrap()
  if v != 0 {
    println("  " + label + ": " + v.to_string())
  }
}

///|
fn print_arr(label : String, opt : @core.Opt[Array[String]]) -> Unit {
  let v = opt.get().unwrap()
  if v.length() > 0 {
    println("  " + label + ": " + v.to_string())
  }
}
