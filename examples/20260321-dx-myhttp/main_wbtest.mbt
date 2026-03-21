// --- GET subcommand tests ---

///|
test "get: basic URL" {
  let c = Config::default()
  @dx.parse_into(["get", "https://example.com"], c)
  assert_eq(c.command, Get)
  assert_eq(c.get_url, "https://example.com")
  assert_eq(c.get_accept, "*/*")
}

///|
test "get: with accept header" {
  let c = Config::default()
  @dx.parse_into(["get", "https://api.example.com", "--accept", "application/json"], c)
  assert_eq(c.get_url, "https://api.example.com")
  assert_eq(c.get_accept, "application/json")
}

///|
test "get: with global verbose count" {
  let c = Config::default()
  @dx.parse_into(["-vvv", "get", "https://example.com"], c)
  assert_eq(c.verbose, 3)
  assert_eq(c.command, Get)
}

///|
test "get: verbose after subcommand" {
  let c = Config::default()
  @dx.parse_into(["get", "https://example.com", "-vv"], c)
  assert_eq(c.verbose, 2)
}

///|
test "get: with timeout short option" {
  let c = Config::default()
  @dx.parse_into(["get", "https://example.com", "-t", "60"], c)
  assert_eq(c.timeout, 60)
}

///|
test "get: follow-redirects alias" {
  let c = Config::default()
  @dx.parse_into(["get", "https://example.com", "--follow", "false"], c)
  assert_eq(c.follow_redirects, false)
}

// --- POST subcommand tests ---

///|
test "post: with required data" {
  let c = Config::default()
  @dx.parse_into(
    ["post", "https://api.example.com", "--data", "{\"key\":\"value\"}"],
    c,
  )
  assert_eq(c.command, Post)
  assert_eq(c.post_url, "https://api.example.com")
  assert_eq(c.post_data, "{\"key\":\"value\"}")
  assert_eq(c.post_content_type, "application/json")
}

///|
test "post: data short option" {
  let c = Config::default()
  @dx.parse_into(["post", "https://api.example.com", "-d", "hello"], c)
  assert_eq(c.post_data, "hello")
}

///|
test "post: custom content-type via alias" {
  let c = Config::default()
  @dx.parse_into(
    ["post", "https://example.com", "-d", "x", "--ct", "text/plain"],
    c,
  )
  assert_eq(c.post_content_type, "text/plain")
}

///|
test "post: multiple headers" {
  let c = Config::default()
  @dx.parse_into(
    [
      "post", "https://example.com", "-d", "x", "-H", "Authorization: Bearer tok",
      "-H", "X-Custom: val",
    ],
    c,
  )
  assert_eq(c.post_header, ["Authorization: Bearer tok", "X-Custom: val"])
}

///|
test "post: missing data is error" {
  let c = Config::default()
  let result : Result[Unit, @core.ParseError] = try? @dx.parse_into(
    ["post", "https://example.com"],
    c,
  )
  assert_true(result is Err(_))
}

// --- Global option tests ---

///|
test "global: format option" {
  let c = Config::default()
  @dx.parse_into(["--format", "json", "get", "https://example.com"], c)
  assert_eq(c.format, "json")
}

///|
test "global: compact flag" {
  let c = Config::default()
  @dx.parse_into(["get", "https://example.com", "--compact"], c)
  assert_eq(c.compact, true)
}

///|
test "global: format and compact exclusive" {
  let c = Config::default()
  let result : Result[Unit, @core.ParseError] = try? @dx.parse_into(
    ["get", "https://example.com", "--format", "json", "--compact"],
    c,
  )
  assert_true(result is Err(_))
}

///|
test "global: default timeout" {
  let c = Config::default()
  @dx.parse_into(["get", "https://example.com"], c)
  assert_eq(c.timeout, 30)
}

///|
test "global: default follow-redirects" {
  let c = Config::default()
  @dx.parse_into(["get", "https://example.com"], c)
  assert_eq(c.follow_redirects, true)
}

// --- Error cases ---

///|
test "error: no subcommand" {
  let c = Config::default()
  let result : Result[Unit, @core.ParseError] = try? @dx.parse_into([], c)
  assert_true(result is Err(_))
}

///|
test "error: unknown option" {
  let c = Config::default()
  let result : Result[Unit, @core.ParseError] = try? @dx.parse_into(
    ["get", "https://example.com", "--unknown"],
    c,
  )
  assert_true(result is Err(_))
}

// --- Isolation: unselected subcommand fields stay default ---

///|
test "isolation: get does not affect post fields" {
  let c = Config::default()
  @dx.parse_into(["get", "https://example.com"], c)
  assert_eq(c.post_url, "")
  assert_eq(c.post_data, "")
  assert_eq(c.post_header, [])
}

///|
test "isolation: post does not affect get fields" {
  let c = Config::default()
  @dx.parse_into(["post", "https://example.com", "-d", "body"], c)
  assert_eq(c.get_url, "")
  assert_eq(c.get_accept, "*/*")
}
