///|
/// mycurl — A curl CLI mock built with kuu.
///
/// Demonstrates kuu's ability to handle a complex real-world CLI with:
///   - custom + shorts (string-type options with short flags)
///   - custom_append + shorts (repeatable string-type options with short flags)
///   - exclusive (auth methods, HTTP versions)
///   - deprecated (--sslv3 → --tlsv1.2)
///   - requires (--proxy-user requires --proxy)
///   - variation_false (--no-keepalive)
///   - choices (--cert-type)
///   - post filter / in_range (--max-redirs)
///   - env (HTTP_PROXY)
///   - visibility=Advanced (--trace, --trace-ascii)
///   - rest (URL...)
///   - short combining (-sSLo file)
fn main {
  println("=== Demo 1: basic GET ===")
  run_test(["https://example.com"])
  println("")
  println("=== Demo 2: POST with data ===")
  run_test([
    "-X", "POST", "-H", "Content-Type: application/json", "-d",
    "{\"key\":\"value\"}", "https://api.example.com/data",
  ])
  println("")
  println("=== Demo 3: file download ===")
  run_test(["-L", "-o", "output.html", "-s", "-S", "https://example.com"])
  println("")
  println("=== Demo 4: auth exclusive error ===")
  run_test([
    "--basic", "--digest", "-u", "user:pass", "https://example.com",
  ])
  println("")
  println("=== Demo 5: proxy + env ===")
  run_test(
    ["-v", "https://example.com"],
    env={ "HTTP_PROXY": "http://proxy:8080" },
  )
  println("")
  println("=== Demo 6: help ===")
  run_test(["--help"])
}

///|
fn run_test(
  args : Array[String],
  env~ : Map[String, String] = {},
) -> Unit {
  println("  args: " + args.to_string())
  if env.length() > 0 {
    println("  env: " + env.to_string())
  }
  match build_and_parse(args, env=env) {
    Ok(info) => println(info)
    Err(msg) => println("  ERROR: " + msg)
  }
}

///|
fn build_and_parse(
  args : Array[String],
  env~ : Map[String, String] = {},
) -> Result[String, String] {
  let p = @core.Parser::new()
  p.set_description("mycurl - A curl CLI mock built with kuu")

  // ─── HTTP method ───

  let request = p.custom(
    name="request",
    shorts="X",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Specify request method to use",
    value_name="METHOD",
  )
  let head = p.flag(
    name="head",
    shorts="I",
    description="Fetch the headers only",
  )
  let get = p.flag(
    name="get",
    shorts="G",
    description="Put the post data in the URL and use GET",
  )

  // ─── Data sending ───

  let data = p.custom_append(
    name="data",
    shorts="d",
    pre=@core.Filter::map(fn(s) { s }),
    description="HTTP POST data",
    value_name="DATA",
  )
  let data_raw = p.append_string(
    name="data-raw",
    description="HTTP POST data, '@' allowed",
    value_name="DATA",
  )
  let data_urlencode = p.append_string(
    name="data-urlencode",
    description="HTTP POST data url encoded",
    value_name="DATA",
  )
  let json = p.append_string(
    name="json",
    description="HTTP POST JSON",
    value_name="DATA",
  )
  let form = p.custom_append(
    name="form",
    shorts="F",
    pre=@core.Filter::map(fn(s) { s }),
    description="Specify multipart MIME data",
    value_name="CONTENT",
  )
  let url_query = p.append_string(
    name="url-query",
    description="Add a URL query part",
    value_name="DATA",
  )

  // ─── Headers ───

  let header = p.custom_append(
    name="header",
    shorts="H",
    pre=@core.Filter::map(fn(s) { s }),
    description="Pass custom header(s) to server",
    value_name="HEADER",
  )
  let user_agent = p.custom(
    name="user-agent",
    shorts="A",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Send User-Agent to server",
    value_name="NAME",
  )
  let referer = p.custom(
    name="referer",
    shorts="e",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Referrer URL",
    value_name="URL",
  )
  let compressed = p.flag(
    name="compressed",
    description="Request compressed response",
  )

  // ─── Authentication (exclusive) ───

  let user = p.custom(
    name="user",
    shorts="u",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Server user and password",
    value_name="USER:PASSWORD",
  )
  let basic = p.flag(
    name="basic",
    description="Use HTTP Basic Authentication",
  )
  let digest = p.flag(
    name="digest",
    description="Use HTTP Digest Authentication",
  )
  let ntlm = p.flag(
    name="ntlm",
    description="Use HTTP NTLM authentication",
  )
  let anyauth = p.flag(
    name="anyauth",
    description="Pick any authentication method",
  )
  let oauth2_bearer = p.string(
    name="oauth2-bearer",
    default="",
    description="OAuth 2 Bearer Token",
    value_name="TOKEN",
  )
  p.exclusive([
    basic.as_ref(),
    digest.as_ref(),
    ntlm.as_ref(),
    anyauth.as_ref(),
    oauth2_bearer.as_ref(),
  ])

  // ─── Output control ───

  let output = p.custom(
    name="output",
    shorts="o",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Write to file instead of stdout",
    value_name="FILE",
  )
  let remote_name = p.flag(
    name="remote-name",
    shorts="O",
    description="Write output to a file named as the remote file",
  )
  let output_dir = p.string(
    name="output-dir",
    default="",
    description="Directory to save files in",
    value_name="DIR",
  )
  let create_dirs = p.flag(
    name="create-dirs",
    description="Create necessary local directory hierarchy",
  )
  let silent = p.flag(
    name="silent",
    shorts="s",
    description="Silent mode",
  )
  let show_error = p.flag(
    name="show-error",
    shorts="S",
    description="Show error even when -s is used",
  )
  let verbose = p.flag(
    name="verbose",
    shorts="v",
    description="Make the operation more talkative",
  )
  let show_headers = p.flag(
    name="show-headers",
    shorts="i",
    description="Include protocol response headers in the output",
  )
  let dump_header = p.custom(
    name="dump-header",
    shorts="D",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Dump the headers to FILE",
    value_name="FILE",
  )
  let write_out = p.custom(
    name="write-out",
    shorts="w",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Use output FORMAT after completion",
    value_name="FORMAT",
  )
  let fail = p.flag(
    name="fail",
    shorts="f",
    description="Fail silently on server errors",
  )
  let fail_with_body = p.flag(
    name="fail-with-body",
    description="Fail silently but save the body",
  )
  let no_progress_meter = p.flag(
    name="no-progress-meter",
    description="Do not show the progress meter",
  )
  let progress_bar = p.flag(
    name="progress-bar",
    shorts="#",
    description="Display transfer progress as a bar",
  )
  let trace = p.string(
    name="trace",
    default="",
    description="Write a debug trace to FILE",
    value_name="FILE",
    visibility=@core.Advanced,
  )
  let trace_ascii = p.string(
    name="trace-ascii",
    default="",
    description="Like --trace, but without hex output",
    value_name="FILE",
    visibility=@core.Advanced,
  )

  // ─── TLS/SSL ───

  let insecure = p.flag(
    name="insecure",
    shorts="k",
    description="Allow insecure server connections",
  )
  let cacert = p.string(
    name="cacert",
    default="",
    description="CA certificate to verify peer against",
    value_name="FILE",
  )
  let cert = p.custom(
    name="cert",
    shorts="E",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Client certificate file and password",
    value_name="CERT[:PASSWD]",
  )
  let cert_type = p.string(
    name="cert-type",
    default="",
    description="Certificate type",
    choices=["DER", "PEM", "ENG", "P12"],
    value_name="TYPE",
  )
  let key = p.string(
    name="key",
    default="",
    description="Private key file name",
    value_name="KEY",
  )
  let tlsv1_2 = p.flag(
    name="tlsv1.2",
    description="Use TLSv1.2 or greater",
  )
  let tlsv1_3 = p.flag(
    name="tlsv1.3",
    description="Use TLSv1.3 or greater",
  )
  let _sslv3_deprecated = p.deprecated(
    "--sslv3",
    tlsv1_2,
    msg="use --tlsv1.2 instead",
  )

  // ─── Proxy ───

  let proxy = p.custom(
    name="proxy",
    shorts="x",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Use this proxy",
    value_name="[PROTOCOL://]HOST[:PORT]",
    env="HTTP_PROXY",
  )
  let proxy_user = p.custom(
    name="proxy-user",
    shorts="U",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Proxy user and password",
    value_name="USER:PASSWORD",
  )
  let noproxy = p.string(
    name="noproxy",
    default="",
    description="List of hosts which do not use proxy",
    value_name="HOSTS",
  )
  p.requires(proxy.as_ref(), source=proxy_user.as_ref())

  // ─── Redirect ───

  let location = p.flag(
    name="location",
    shorts="L",
    description="Follow redirects",
  )
  let max_redirs = p.int(
    name="max-redirs",
    default=50,
    description="Maximum number of redirects allowed",
    post=Some(@core.Filter::in_range(-1, 999)),
    value_name="NUM",
  )

  // ─── Timeout / Retry ───

  let connect_timeout = p.float(
    name="connect-timeout",
    default=0.0,
    description="Maximum time allowed for connection",
    value_name="SECONDS",
  )
  let max_time = p.custom(
    name="max-time",
    shorts="m",
    default=0.0,
    pre=@core.Filter::parse_float(),
    description="Maximum time allowed for the transfer",
    value_name="SECONDS",
  )
  let retry = p.int(
    name="retry",
    default=0,
    description="Retry request if transient problems occur",
    value_name="NUM",
  )
  let retry_delay = p.int(
    name="retry-delay",
    default=0,
    description="Wait time between retries",
    value_name="SECONDS",
  )
  let retry_max_time = p.int(
    name="retry-max-time",
    default=0,
    description="Retry only within this period",
    value_name="SECONDS",
  )
  let retry_all_errors = p.flag(
    name="retry-all-errors",
    description="Retry all errors",
  )

  // ─── Cookie ───

  let cookie = p.custom_append(
    name="cookie",
    shorts="b",
    pre=@core.Filter::map(fn(s) { s }),
    description="Send cookies from string/file",
    value_name="DATA|FILE",
  )
  let cookie_jar = p.custom(
    name="cookie-jar",
    shorts="c",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Write cookies to FILE after operation",
    value_name="FILE",
  )

  // ─── HTTP version (exclusive) ───

  let http1_0 = p.flag(
    name="http1.0",
    shorts="0",
    description="Use HTTP 1.0",
  )
  let http1_1 = p.flag(
    name="http1.1",
    description="Use HTTP 1.1",
  )
  let http2 = p.flag(
    name="http2",
    description="Use HTTP 2",
  )
  let http3 = p.flag(
    name="http3",
    description="Use HTTP v3",
  )
  p.exclusive([
    http1_0.as_ref(),
    http1_1.as_ref(),
    http2.as_ref(),
    http3.as_ref(),
  ])

  // ─── Miscellaneous ───

  let limit_rate = p.string(
    name="limit-rate",
    default="",
    description="Limit transfer speed to SPEED",
    value_name="SPEED",
  )
  let resolve = p.append_string(
    name="resolve",
    description="Resolve the host+port to this address",
    value_name="HOST:PORT:ADDR",
  )
  let connect_to = p.append_string(
    name="connect-to",
    description="Connect to host",
    value_name="HOST1:PORT1:HOST2:PORT2",
  )
  let ipv4 = p.flag(
    name="ipv4",
    shorts="4",
    description="Resolve names to IPv4 addresses",
  )
  let ipv6 = p.flag(
    name="ipv6",
    shorts="6",
    description="Resolve names to IPv6 addresses",
  )
  let parallel = p.flag(
    name="parallel",
    shorts="Z",
    description="Perform transfers in parallel",
  )
  let parallel_max = p.int(
    name="parallel-max",
    default=50,
    description="Maximum concurrency for parallel transfers",
    value_name="NUM",
  )
  let continue_at = p.custom(
    name="continue-at",
    shorts="C",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Resumed transfer offset",
    value_name="OFFSET",
  )
  let upload_file = p.custom(
    name="upload-file",
    shorts="T",
    default="",
    pre=@core.Filter::map(fn(s) { s }),
    description="Transfer local FILE to destination",
    value_name="FILE",
  )
  let remote_time = p.flag(
    name="remote-time",
    shorts="R",
    description="Set the remote file's time on the local output",
  )
  let netrc = p.flag(
    name="netrc",
    shorts="n",
    description="Must read .netrc for user name and password",
  )
  let keepalive = p.flag(
    name="keepalive",
    default=true,
    description="Enable TCP keepalive",
    variation_false=Some("no"),
  )
  let url_opt = p.append_string(
    name="url",
    description="URL to work with",
    value_name="URL",
  )

  // ─── Positional: URL... ───

  let urls = p.rest(
    name="urls",
    description="URL(s) to fetch",
  )

  // ─── Parse ───

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(
    args, env=env,
  )
  match result {
    Err(@core.HelpRequested(text)) => Ok(text)
    Err(@core.ParseError(info)) => Err(info.to_string())
    Ok(_) => {
      let buf = StringBuilder::new()

      // Deprecated warnings
      let warnings = p.deprecated_warnings()
      for warn in warnings {
        buf.write_string(
          "  [deprecated] " + warn.0 + ": " + warn.1 + "\n",
        )
      }

      // Data (gather once for method inference and output)
      let data_val = data.get().unwrap()
      let data_raw_val = data_raw.get().unwrap()
      let data_ue_val = data_urlencode.get().unwrap()
      let json_val = json.get().unwrap()
      let form_val = form.get().unwrap()
      let uq_val = url_query.get().unwrap()
      let upload_val = upload_file.get().unwrap()

      // Method (implied logic)
      let req_val = request.get().unwrap()
      let has_data = data_val.length() > 0 ||
        data_raw_val.length() > 0 ||
        data_ue_val.length() > 0 ||
        json_val.length() > 0 ||
        form_val.length() > 0
      if req_val != "" {
        buf.write_string("  method: " + req_val + "\n")
      } else if head.get().unwrap() {
        buf.write_string("  method: HEAD (implied)\n")
      } else if upload_val != "" {
        buf.write_string("  method: PUT (implied)\n")
      } else if get.get().unwrap() {
        buf.write_string("  method: GET (implied)\n")
      } else if has_data {
        buf.write_string("  method: POST (implied)\n")
      }

      // Headers
      let hdr_val = header.get().unwrap()
      if hdr_val.length() > 0 {
        buf.write_string("  headers: " + hdr_val.to_string() + "\n")
      }

      // User-Agent
      let ua_val = user_agent.get().unwrap()
      if ua_val != "" {
        buf.write_string("  user-agent: " + ua_val + "\n")
      }

      // Referer
      let ref_val = referer.get().unwrap()
      if ref_val != "" {
        buf.write_string("  referer: " + ref_val + "\n")
      }

      // Compressed
      if compressed.get().unwrap() {
        buf.write_string("  compressed: true\n")
      }

      // Data output
      if data_val.length() > 0 {
        buf.write_string("  data: " + data_val.to_string() + "\n")
      }
      if data_raw_val.length() > 0 {
        buf.write_string("  data-raw: " + data_raw_val.to_string() + "\n")
      }
      if data_ue_val.length() > 0 {
        buf.write_string(
          "  data-urlencode: " + data_ue_val.to_string() + "\n",
        )
      }
      if json_val.length() > 0 {
        buf.write_string("  json: " + json_val.to_string() + "\n")
      }
      if form_val.length() > 0 {
        buf.write_string("  form: " + form_val.to_string() + "\n")
      }
      if uq_val.length() > 0 {
        buf.write_string("  url-query: " + uq_val.to_string() + "\n")
      }

      // Auth
      let user_val = user.get().unwrap()
      if user_val != "" {
        buf.write_string("  user: " + user_val + "\n")
      }
      let auth_flags : Array[(String, @core.Opt[Bool])] = [
        ("basic", basic), ("digest", digest), ("ntlm", ntlm),
        ("anyauth", anyauth),
      ]
      for pair in auth_flags {
        if pair.1.get().unwrap() {
          buf.write_string("  " + pair.0 + ": true\n")
        }
      }
      let ob_val = oauth2_bearer.get().unwrap()
      if ob_val != "" {
        buf.write_string("  oauth2-bearer: " + ob_val + "\n")
      }

      // Output control
      let out_val = output.get().unwrap()
      if out_val != "" {
        buf.write_string("  output: " + out_val + "\n")
      }
      if remote_name.get().unwrap() {
        buf.write_string("  remote-name: true\n")
      }
      let od_val = output_dir.get().unwrap()
      if od_val != "" {
        buf.write_string("  output-dir: " + od_val + "\n")
      }
      if create_dirs.get().unwrap() {
        buf.write_string("  create-dirs: true\n")
      }
      if silent.get().unwrap() {
        buf.write_string("  silent: true\n")
      }
      if show_error.get().unwrap() {
        buf.write_string("  show-error: true\n")
      }
      if verbose.get().unwrap() {
        buf.write_string("  verbose: true\n")
      }
      if show_headers.get().unwrap() {
        buf.write_string("  show-headers: true\n")
      }
      let dh_val = dump_header.get().unwrap()
      if dh_val != "" {
        buf.write_string("  dump-header: " + dh_val + "\n")
      }
      let wo_val = write_out.get().unwrap()
      if wo_val != "" {
        buf.write_string("  write-out: " + wo_val + "\n")
      }
      if fail.get().unwrap() {
        buf.write_string("  fail: true\n")
      }
      if fail_with_body.get().unwrap() {
        buf.write_string("  fail-with-body: true\n")
      }
      if no_progress_meter.get().unwrap() {
        buf.write_string("  no-progress-meter: true\n")
      }
      if progress_bar.get().unwrap() {
        buf.write_string("  progress-bar: true\n")
      }
      let trace_val = trace.get().unwrap()
      if trace_val != "" {
        buf.write_string("  trace: " + trace_val + "\n")
      }
      let ta_val = trace_ascii.get().unwrap()
      if ta_val != "" {
        buf.write_string("  trace-ascii: " + ta_val + "\n")
      }

      // TLS/SSL
      if insecure.get().unwrap() {
        buf.write_string("  insecure: true\n")
      }
      let cacert_val = cacert.get().unwrap()
      if cacert_val != "" {
        buf.write_string("  cacert: " + cacert_val + "\n")
      }
      let cert_val = cert.get().unwrap()
      if cert_val != "" {
        buf.write_string("  cert: " + cert_val + "\n")
      }
      let ct_val = cert_type.get().unwrap()
      if ct_val != "" {
        buf.write_string("  cert-type: " + ct_val + "\n")
      }
      let key_val = key.get().unwrap()
      if key_val != "" {
        buf.write_string("  key: " + key_val + "\n")
      }
      if tlsv1_2.get().unwrap() {
        buf.write_string("  tlsv1.2: true\n")
      }
      if tlsv1_3.get().unwrap() {
        buf.write_string("  tlsv1.3: true\n")
      }

      // Proxy
      let proxy_val = proxy.get().unwrap()
      if proxy_val != "" {
        buf.write_string("  proxy: " + proxy_val + "\n")
      }
      let pu_val = proxy_user.get().unwrap()
      if pu_val != "" {
        buf.write_string("  proxy-user: " + pu_val + "\n")
      }
      let np_val = noproxy.get().unwrap()
      if np_val != "" {
        buf.write_string("  noproxy: " + np_val + "\n")
      }

      // Redirect
      if location.get().unwrap() {
        buf.write_string("  location: true\n")
      }
      if max_redirs.is_set() {
        buf.write_string(
          "  max-redirs: " + max_redirs.get().unwrap().to_string() + "\n",
        )
      }

      // Timeout / Retry
      let ct_timeout = connect_timeout.get().unwrap()
      if ct_timeout != 0.0 {
        buf.write_string(
          "  connect-timeout: " + ct_timeout.to_string() + "\n",
        )
      }
      let mt_val = max_time.get().unwrap()
      if mt_val != 0.0 {
        buf.write_string("  max-time: " + mt_val.to_string() + "\n")
      }
      let retry_val = retry.get().unwrap()
      if retry_val != 0 {
        buf.write_string("  retry: " + retry_val.to_string() + "\n")
      }
      let rd_val = retry_delay.get().unwrap()
      if rd_val != 0 {
        buf.write_string("  retry-delay: " + rd_val.to_string() + "\n")
      }
      let rmt_val = retry_max_time.get().unwrap()
      if rmt_val != 0 {
        buf.write_string(
          "  retry-max-time: " + rmt_val.to_string() + "\n",
        )
      }
      if retry_all_errors.get().unwrap() {
        buf.write_string("  retry-all-errors: true\n")
      }

      // Cookie
      let cookie_val = cookie.get().unwrap()
      if cookie_val.length() > 0 {
        buf.write_string("  cookie: " + cookie_val.to_string() + "\n")
      }
      let cj_val = cookie_jar.get().unwrap()
      if cj_val != "" {
        buf.write_string("  cookie-jar: " + cj_val + "\n")
      }

      // HTTP version
      let http_versions : Array[(String, @core.Opt[Bool])] = [
        ("http1.0", http1_0), ("http1.1", http1_1), ("http2", http2),
        ("http3", http3),
      ]
      for pair in http_versions {
        if pair.1.get().unwrap() {
          buf.write_string("  " + pair.0 + ": true\n")
        }
      }

      // Miscellaneous
      let lr_val = limit_rate.get().unwrap()
      if lr_val != "" {
        buf.write_string("  limit-rate: " + lr_val + "\n")
      }
      let resolve_val = resolve.get().unwrap()
      if resolve_val.length() > 0 {
        buf.write_string("  resolve: " + resolve_val.to_string() + "\n")
      }
      let ct_to_val = connect_to.get().unwrap()
      if ct_to_val.length() > 0 {
        buf.write_string("  connect-to: " + ct_to_val.to_string() + "\n")
      }
      if ipv4.get().unwrap() {
        buf.write_string("  ipv4: true\n")
      }
      if ipv6.get().unwrap() {
        buf.write_string("  ipv6: true\n")
      }
      if parallel.get().unwrap() {
        buf.write_string("  parallel: true\n")
      }
      if parallel_max.is_set() {
        buf.write_string(
          "  parallel-max: " +
            parallel_max.get().unwrap().to_string() +
            "\n",
        )
      }
      let ca_val = continue_at.get().unwrap()
      if ca_val != "" {
        buf.write_string("  continue-at: " + ca_val + "\n")
      }
      if upload_val != "" {
        buf.write_string("  upload-file: " + upload_val + "\n")
      }
      if remote_time.get().unwrap() {
        buf.write_string("  remote-time: true\n")
      }
      if netrc.get().unwrap() {
        buf.write_string("  netrc: true\n")
      }
      if keepalive.is_set() {
        buf.write_string(
          "  keepalive: " + keepalive.get().unwrap().to_string() + "\n",
        )
      }
      let url_opt_val = url_opt.get().unwrap()
      if url_opt_val.length() > 0 {
        buf.write_string("  url (option): " + url_opt_val.to_string() + "\n")
      }

      // Head / Get flags
      if head.get().unwrap() {
        buf.write_string("  head: true\n")
      }
      if get.get().unwrap() {
        buf.write_string("  get: true\n")
      }

      // URL (positional)
      let urls_val = urls.get().unwrap()
      if urls_val.length() > 0 {
        buf.write_string("  urls: " + urls_val.to_string() + "\n")
      }

      Ok(buf.to_string())
    }
  }
}

// ─── Tests ───

test "basic get" {
  let result = build_and_parse(["https://example.com"])
  inspect(result, content=(
    #|Ok("  urls: [\"https://example.com\"]\n")

  ))
}

test "post with data" {
  let result = build_and_parse(["-d", "key=value", "https://httpbin.org/post"])
  inspect(result, content=(
    #|Ok("  method: POST (implied)\n  data: [\"key=value\"]\n  urls: [\"https://httpbin.org/post\"]\n")

  ))
}

test "multiple headers" {
  let result = build_and_parse([
    "-H", "Accept: application/json", "-H", "X-Custom: test",
    "https://example.com",
  ])
  inspect(result, content=(
    #|Ok("  headers: [\"Accept: application/json\", \"X-Custom: test\"]\n  urls: [\"https://example.com\"]\n")

  ))
}

test "auth exclusive error" {
  match build_and_parse([
    "--basic", "--digest", "-u", "user:pass", "https://example.com",
  ]) {
    Err(msg) =>
      assert_true(
        msg.has_prefix("error: mutually exclusive options: --basic, --digest"),
      )
    Ok(_) => fail("expected error")
  }
}

test "http version exclusive error" {
  match build_and_parse(["--http2", "--http3", "https://example.com"]) {
    Err(msg) =>
      assert_true(
        msg.has_prefix("error: mutually exclusive options: --http2, --http3"),
      )
    Ok(_) => fail("expected error")
  }
}

test "file download" {
  let result = build_and_parse(["-o", "file.html", "-L", "https://example.com"])
  inspect(result, content=(
    #|Ok("  output: file.html\n  location: true\n  urls: [\"https://example.com\"]\n")

  ))
}

test "deprecated sslv3" {
  let result = build_and_parse(["--sslv3", "https://example.com"])
  inspect(result, content=(
    #|Ok("  [deprecated] --sslv3: use --tlsv1.2 instead\n  tlsv1.2: true\n  urls: [\"https://example.com\"]\n")

  ))
}

test "proxy via env" {
  let result = build_and_parse(
    ["https://example.com"],
    env={ "HTTP_PROXY": "http://proxy:8080" },
  )
  inspect(result, content=(
    #|Ok("  proxy: http://proxy:8080\n  urls: [\"https://example.com\"]\n")

  ))
}

test "proxy-user requires proxy" {
  match build_and_parse([
    "--proxy-user", "user:pass", "https://example.com",
  ]) {
    Err(msg) =>
      assert_true(msg.has_prefix("error: --proxy-user requires --proxy"))
    Ok(_) => fail("expected error")
  }
}

test "cert-type choices valid" {
  let result = build_and_parse([
    "--cert-type", "PEM", "--cert", "cert.pem", "https://example.com",
  ])
  inspect(result, content=(
    #|Ok("  cert: cert.pem\n  cert-type: PEM\n  urls: [\"https://example.com\"]\n")

  ))
}

test "cert-type choices invalid" {
  match build_and_parse(["--cert-type", "INVALID", "https://example.com"]) {
    Err(msg) =>
      assert_true(msg.has_prefix("error: value must be one of: DER"))
    Ok(_) => fail("expected error")
  }
}

test "max-redirs range valid" {
  let result = build_and_parse([
    "--max-redirs", "10", "-L", "https://example.com",
  ])
  inspect(result, content=(
    #|Ok("  location: true\n  max-redirs: 10\n  urls: [\"https://example.com\"]\n")

  ))
}

test "max-redirs range invalid" {
  match build_and_parse(["--max-redirs", "-2", "https://example.com"]) {
    Err(msg) => assert_true(msg.has_prefix("error: value -2"))
    Ok(_) => fail("expected error")
  }
}

test "short combining" {
  let result = build_and_parse([
    "-sSLo", "file.html", "https://example.com",
  ])
  inspect(result, content=(
    #|Ok("  output: file.html\n  silent: true\n  show-error: true\n  location: true\n  urls: [\"https://example.com\"]\n")

  ))
}

test "upload file" {
  let result = build_and_parse([
    "-T", "data.txt", "https://example.com/upload",
  ])
  inspect(result, content=(
    #|Ok("  method: PUT (implied)\n  upload-file: data.txt\n  urls: [\"https://example.com/upload\"]\n")

  ))
}

test "cookie send and save" {
  let result = build_and_parse([
    "-b", "session=abc123", "-c", "cookies.txt", "https://example.com",
  ])
  inspect(result, content=(
    #|Ok("  cookie: [\"session=abc123\"]\n  cookie-jar: cookies.txt\n  urls: [\"https://example.com\"]\n")

  ))
}

test "json data" {
  let result = build_and_parse([
    "--json", "{\"key\":\"val\"}", "https://api.example.com",
  ])
  inspect(result, content=(
    #|Ok("  method: POST (implied)\n  json: [\"{\\\"key\\\":\\\"val\\\"}\"]\n  urls: [\"https://api.example.com\"]\n")

  ))
}

test "parallel" {
  let result = build_and_parse([
    "-Z", "--parallel-max", "10", "https://a.example.com",
    "https://b.example.com",
  ])
  inspect(result, content=(
    #|Ok("  parallel: true\n  parallel-max: 10\n  urls: [\"https://a.example.com\", \"https://b.example.com\"]\n")

  ))
}

test "verbose and trace" {
  let result = build_and_parse([
    "-v", "--trace", "trace.log", "https://example.com",
  ])
  inspect(result, content=(
    #|Ok("  verbose: true\n  trace: trace.log\n  urls: [\"https://example.com\"]\n")

  ))
}

test "no-keepalive variation" {
  let result = build_and_parse(["--no-keepalive", "https://example.com"])
  inspect(result, content=(
    #|Ok("  keepalive: false\n  urls: [\"https://example.com\"]\n")

  ))
}

test "ipv4" {
  let result = build_and_parse(["-4", "https://example.com"])
  inspect(result, content=(
    #|Ok("  ipv4: true\n  urls: [\"https://example.com\"]\n")

  ))
}

test "explicit method DELETE" {
  let result = build_and_parse(["-X", "DELETE", "https://example.com/item/1"])
  inspect(result, content=(
    #|Ok("  method: DELETE\n  urls: [\"https://example.com/item/1\"]\n")
  ))
}

test "head implied" {
  let result = build_and_parse(["-I", "https://example.com"])
  inspect(result, content=(
    #|Ok("  method: HEAD (implied)\n  head: true\n  urls: [\"https://example.com\"]\n")
  ))
}

test "form post implied" {
  let result = build_and_parse(["-F", "file=@upload.txt", "https://example.com/upload"])
  inspect(result, content=(
    #|Ok("  method: POST (implied)\n  form: [\"file=@upload.txt\"]\n  urls: [\"https://example.com/upload\"]\n")
  ))
}

test "method priority: explicit over data" {
  let result = build_and_parse(["-X", "GET", "-d", "data", "https://example.com"])
  inspect(result, content=(
    #|Ok("  method: GET\n  data: [\"data\"]\n  urls: [\"https://example.com\"]\n")
  ))
}

test "get flag overrides post implied" {
  let result = build_and_parse([
    "-G", "-d", "query=1", "https://example.com",
  ])
  inspect(result, content=(
    #|Ok("  method: GET (implied)\n  data: [\"query=1\"]\n  get: true\n  urls: [\"https://example.com\"]\n")
  ))
}

test "requires normal case" {
  let result = build_and_parse(["--proxy", "http://p:8080", "--proxy-user", "u:p", "https://example.com"])
  inspect(result, content=(
    #|Ok("  proxy: http://p:8080\n  proxy-user: u:p\n  urls: [\"https://example.com\"]\n")
  ))
}
