///|
/// env_applicator を登録する共通ヘルパー。
/// env が非空の場合のみ、committed=false なら env から値を取得して適用する。
/// env_prefix が設定されている場合は prefix + "_" + env をキーとして参照する。
fn[T] register_env_applicator(
  parser : Parser,
  env : String,
  vc : ValCell[T],
  converter : (String) -> T raise ParseError,
) -> Unit {
  if env != "" {
    let prefix_ref = parser.env_prefix
    parser.env_applicators.push(fn(env_map) raise ParseError {
      if !vc.committed.val {
        let key = if prefix_ref.val == "" {
          env
        } else {
          prefix_ref.val + "_" + env
        }
        match env_map.get(key) {
          Some(raw) =>
            if raw != "" {
              vc.cell.val = converter(raw)
              vc.committed.val = true
            }
          None => ()
        }
      }
    })
  }
}

///|
/// Variation sugar パラメータを variations 配列に展開するヘルパー
fn apply_variation_sugar(
  variations : Array[Variation],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Unit {
  if variation_toggle is Some(p) {
    variations.push(Toggle(p))
  }
  if variation_true is Some(p) {
    variations.push(True(p))
  }
  if variation_false is Some(p) {
    variations.push(False(p))
  }
  if variation_reset is Some(p) {
    variations.push(Reset(p))
  }
  if variation_unset is Some(p) {
    variations.push(Unset(p))
  }
}

///|
/// Creates a boolean flag option (no value argument).
///
/// When the flag is present on the command line, its value flips from the
/// default. Repeated occurrences do not stack (use `count` for that).
///
/// Parameters:
/// - `name` - Long option name (e.g. "verbose" for `--verbose`)
/// - `default` - Default value when not specified (default: `false`)
/// - `description` - Help text shown in `--help` output
/// - `shorts` - Single-character aliases (e.g. "v" for `-v`)
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Toggle, True, False, Reset, Unset)
///
/// Returns an `Opt[Bool]` that can be queried after parsing.
///
/// Example:
/// ```
/// let verbose = parser.flag(name="verbose", shorts="v", description="Enable verbose output")
/// parser.parse!(["--verbose"])
/// assert_eq!(verbose.get(), Some(true))
/// ```
pub fn Parser::flag(
  self : Parser,
  name~ : String,
  default? : Bool = false,
  default_fn? : (() -> Bool)? = None,
  global? : Bool = false,
  aliases? : Array[String] = [],
  shorts? : String = "",
  description? : String = "",
  env? : String = "",
  visibility? : Visibility = Visible,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Bool] {
  let env = self.effective_env_name(env, name, visibility)
  apply_variation_sugar(
    variations,
    variation_toggle~,
    variation_true~,
    variation_false~,
    variation_reset~,
    variation_unset~,
  )
  // default_fn があれば default を上書き
  let initial_val = match default_fn {
    Some(f) => f()
    None => default
  }
  let (vc, acc) = make_value_cell(initial=initial_val)
  let pending : Ref[Bool] = { val: initial_val }
  let reset_fn = fn() {
    vc.cell.val = initial_val
    pending.val = initial_val
  }
  let positive_match = make_flag_on_match(pending, vc.cell, fn(_p) {
    !initial_val
  })
  let opt = self.register_option(
    name~,
    aliases~,
    shorts~,
    global~,
    visibility~,
    help=description,
    value_name="",
    default_display="",
    env_name=env,
    kind=Flag,
    variations~,
    valcell=vc,
    accessor=acc,
    make_main_node=fn(n) { make_flag_node(n, positive_match, reset_fn) },
    make_node_for_variation=fn(vn, v) {
      let var_reset = fn() {
        vc.cell.val = initial_val
        pending.val = initial_val
        vc.committed.val = false
      }
      match v {
        Toggle(_) =>
          make_flag_node(
            vn,
            make_flag_on_match_with_committed(
              pending,
              vc.cell,
              vc.committed,
              fn(p) { !p },
              true,
            ),
            var_reset,
          )
        True(_) =>
          make_flag_node(
            vn,
            make_flag_on_match_with_committed(
              pending,
              vc.cell,
              vc.committed,
              fn(_p) { true },
              true,
            ),
            var_reset,
          )
        False(_) =>
          make_flag_node(
            vn,
            make_flag_on_match_with_committed(
              pending,
              vc.cell,
              vc.committed,
              fn(_p) { false },
              true,
            ),
            var_reset,
          )
        Reset(_) =>
          make_flag_node(
            vn,
            make_flag_on_match_with_committed(
              pending,
              vc.cell,
              vc.committed,
              fn(_p) { initial_val },
              true,
            ),
            var_reset,
          )
        Unset(_) =>
          make_flag_node(
            vn,
            make_flag_on_match_with_committed(
              pending,
              vc.cell,
              vc.committed,
              fn(_p) { initial_val },
              false,
            ),
            var_reset,
          )
      }
    },
  )
  register_env_applicator(self, env, vc, raw => {
    let lower = raw.to_lower()
    if lower == "true" || lower == "1" {
      true
    } else if lower == "false" || lower == "0" {
      false
    } else {
      raise parse_error(
        "invalid value for env " +
        env +
        ": " +
        raw +
        " (expected true/false/1/0)",
      )
    }
  })
  opt
}

///|
/// File path sugar combinator. Wraps `custom[String]` with `implicit_value`
/// to support a 3-state pattern: not specified → default, flag-only → default_path,
/// value specified → the given path.
pub fn Parser::file(
  self : Parser,
  name~ : String,
  default~ : String,
  default_path~ : String,
  default_fn? : (() -> String)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "PATH",
  visibility? : Visibility = Visible,
  aliases? : Array[String] = [],
  shorts? : String = "",
  global? : Bool = false,
  post? : FilterChain[String, String]? = None,
  choices? : Array[String] = [],
) -> Opt[String] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    aliases~,
    shorts~,
    global~,
    post~,
    choices~,
    implicit_value=Some(Val(default_path)),
    pre=Filter::map(fn(s) { s }),
  )
}

///|
/// Creates a string-valued option.
///
/// A convenience wrapper around `custom` with an identity `pre` filter.
/// The raw CLI argument string is stored as-is without conversion.
///
/// Parameters:
/// - `name` - Long option name (e.g. "output" for `--output`)
/// - `default` - Default value when the option is not specified
/// - `description` - Help text shown in `--help` output
/// - `choices` - Restrict accepted values to this list
/// - `implicit_value` - Value used when the flag is present without `=value`
/// - `shorts` - Single-character aliases (e.g. "o" for `-o`)
/// - `aliases` - Alternative long option names
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Toggle, True, False, Reset, Unset)
///
/// Returns an `Opt[String]` that can be queried after parsing.
///
/// Example:
/// ```
/// let output = parser.string(name="output", default="stdout", description="Output file")
/// parser.parse!(["--output", "result.txt"])
/// assert_eq!(output.get(), Some("result.txt"))
/// ```
pub fn Parser::string(
  self : Parser,
  name~ : String,
  default~ : String,
  default_fn? : (() -> String)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
  shorts? : String = "",
  aliases? : Array[String] = [],
  global? : Bool = false,
  variations? : Array[Variation] = [],
  post? : FilterChain[String, String]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[String]? = None,
) -> Opt[String] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    shorts~,
    aliases~,
    global~,
    variations~,
    post~,
    choices~,
    implicit_value~,
    pre=Filter::map(fn(s) { s }),
  )
}

///|
/// Creates an integer-valued option.
///
/// A convenience wrapper around `custom` with a `parse_int` pre filter.
/// The raw CLI string is parsed as an integer; invalid values raise `ParseError`.
///
/// Parameters:
/// - `name` - Long option name (e.g. "count" for `--count`)
/// - `default` - Default value when the option is not specified
/// - `description` - Help text shown in `--help` output
/// - `choices` - Restrict accepted values (as strings) to this list
/// - `shorts` - Single-character aliases (e.g. "p" for `-p`)
/// - `aliases` - Alternative long option names
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Toggle, True, False, Reset, Unset)
///
/// Returns an `Opt[Int]` that can be queried after parsing.
///
/// Example:
/// ```
/// let port = parser.int(name="port", default=8080, description="Listen port")
/// parser.parse!(["--port", "3000"])
/// assert_eq!(port.get(), Some(3000))
/// ```
pub fn Parser::int(
  self : Parser,
  name~ : String,
  default~ : Int,
  default_fn? : (() -> Int)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "INT",
  visibility? : Visibility = Visible,
  shorts? : String = "",
  aliases? : Array[String] = [],
  global? : Bool = false,
  variations? : Array[Variation] = [],
  post? : FilterChain[Int, Int]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[Int]? = None,
) -> Opt[Int] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    shorts~,
    aliases~,
    global~,
    variations~,
    post~,
    choices~,
    implicit_value~,
    pre=Filter::parse_int(),
  )
}

///|
/// Creates a floating-point-valued option.
///
/// A convenience wrapper around `custom` with a `parse_float` pre filter.
/// The raw CLI string is parsed as a `Double`; invalid values raise `ParseError`.
///
/// Parameters:
/// - `name` - Long option name (e.g. "threshold" for `--threshold`)
/// - `default` - Default value when the option is not specified
/// - `description` - Help text shown in `--help` output
/// - `shorts` - Single-character aliases (e.g. "r" for `-r`)
/// - `aliases` - Alternative long option names
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Toggle, True, False, Reset, Unset)
///
/// Returns an `Opt[Double]` that can be queried after parsing.
///
/// Example:
/// ```
/// let rate = parser.float(name="rate", default=1.0, description="Sampling rate")
/// parser.parse!(["--rate", "0.5"])
/// assert_eq!(rate.get(), Some(0.5))
/// ```
pub fn Parser::float(
  self : Parser,
  name~ : String,
  default~ : Double,
  default_fn? : (() -> Double)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "FLOAT",
  visibility? : Visibility = Visible,
  shorts? : String = "",
  aliases? : Array[String] = [],
  global? : Bool = false,
  variations? : Array[Variation] = [],
  post? : FilterChain[Double, Double]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[Double]? = None,
) -> Opt[Double] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    shorts~,
    aliases~,
    global~,
    variations~,
    post~,
    choices~,
    implicit_value~,
    pre=Filter::parse_float(),
  )
}

///|
/// Creates a boolean-valued option that takes an explicit value argument.
///
/// Unlike `flag` (which toggles on presence), `boolean` requires a value
/// such as `--color true`, `--color false`, `--color on`, `--color off`,
/// `--color 1`, or `--color 0`.
///
/// Parameters:
/// - `name` - Long option name (e.g. "color" for `--color`)
/// - `default` - Default value when the option is not specified (default: `false`)
/// - `description` - Help text shown in `--help` output
/// - `shorts` - Single-character aliases (e.g. "c" for `-c`)
/// - `aliases` - Alternative long option names
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Toggle, True, False, Reset, Unset)
///
/// Returns an `Opt[Bool]` that can be queried after parsing.
///
/// Example:
/// ```
/// let color = parser.boolean(name="color", description="Enable color output")
/// parser.parse!(["--color", "true"])
/// assert_eq!(color.get(), Some(true))
/// ```
pub fn Parser::boolean(
  self : Parser,
  name~ : String,
  default? : Bool = false,
  default_fn? : (() -> Bool)? = None,
  description? : String = "",
  env? : String = "",
  value_name? : String = "BOOL",
  visibility? : Visibility = Visible,
  shorts? : String = "",
  aliases? : Array[String] = [],
  global? : Bool = false,
  variations? : Array[Variation] = [],
  post? : FilterChain[Bool, Bool]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[Bool]? = None,
) -> Opt[Bool] {
  self.custom(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    default~,
    default_fn~,
    shorts~,
    aliases~,
    global~,
    variations~,
    post~,
    choices~,
    implicit_value~,
    pre=Filter::parse_bool(),
  )
}

///|
/// Creates a multi-value string option that collects values into an array.
///
/// A convenience wrapper around `append` with an identity `pre` filter.
///
/// Parameters:
/// - `shorts` - Single-character aliases (e.g. "f" for `-f`)
/// - `aliases` - Alternative long option names
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Toggle, True, False, Reset, Unset)
///
/// Example:
/// ```
/// let files = parser.append_string(name="file", description="Input files")
/// parser.parse!(["--file", "a.txt", "--file", "b.txt"])
/// assert_eq!(files.get(), Some(["a.txt", "b.txt"]))
/// ```
pub fn Parser::append_string(
  self : Parser,
  name~ : String,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
  shorts? : String = "",
  aliases? : Array[String] = [],
  global? : Bool = false,
  variations? : Array[Variation] = [],
) -> Opt[Array[String]] {
  self.append(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    shorts~,
    aliases~,
    global~,
    variations~,
    pre=Filter::map(fn(s) { s }),
  )
}

///|
/// Creates a multi-value integer option that collects values into an array.
///
/// A convenience wrapper around `append` with a `parse_int` pre filter.
///
/// Parameters:
/// - `shorts` - Single-character aliases (e.g. "p" for `-p`)
/// - `aliases` - Alternative long option names
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Toggle, True, False, Reset, Unset)
///
/// Example:
/// ```
/// let ports = parser.append_int(name="port", description="Listen ports")
/// parser.parse!(["--port", "80", "--port", "443"])
/// assert_eq!(ports.get(), Some([80, 443]))
/// ```
pub fn Parser::append_int(
  self : Parser,
  name~ : String,
  description? : String = "",
  env? : String = "",
  value_name? : String = "INT",
  visibility? : Visibility = Visible,
  shorts? : String = "",
  aliases? : Array[String] = [],
  global? : Bool = false,
  variations? : Array[Variation] = [],
) -> Opt[Array[Int]] {
  self.append(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    shorts~,
    aliases~,
    global~,
    variations~,
    pre=Filter::parse_int(),
  )
}

///|
/// Creates a multi-value floating-point option that collects values into an array.
///
/// A convenience wrapper around `append` with a `parse_float` pre filter.
///
/// Parameters:
/// - `shorts` - Single-character aliases (e.g. "w" for `-w`)
/// - `aliases` - Alternative long option names
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Toggle, True, False, Reset, Unset)
///
/// Example:
/// ```
/// let weights = parser.append_float(name="weight", description="Weight values")
/// parser.parse!(["--weight", "0.5", "--weight", "1.5"])
/// assert_eq!(weights.get(), Some([0.5, 1.5]))
/// ```
pub fn Parser::append_float(
  self : Parser,
  name~ : String,
  description? : String = "",
  env? : String = "",
  value_name? : String = "FLOAT",
  visibility? : Visibility = Visible,
  shorts? : String = "",
  aliases? : Array[String] = [],
  global? : Bool = false,
  variations? : Array[Variation] = [],
) -> Opt[Array[Double]] {
  self.append(
    name~,
    visibility~,
    description~,
    value_name~,
    env~,
    shorts~,
    aliases~,
    global~,
    variations~,
    pre=Filter::parse_float(),
  )
}

///|
/// Creates a counter option that increments on each occurrence.
///
/// Each time the flag appears on the command line, the counter increases by 1.
/// Useful for verbosity levels like `-v`, `-vv`, `-vvv`.
///
/// Parameters:
/// - `name` - Long option name (e.g. "verbose" for `--verbose`)
/// - `shorts` - Single-character aliases (e.g. "v" for `-v`)
/// - `description` - Help text shown in `--help` output
/// - `global` - If true, propagated to subcommand parsers
/// - `variations` - Variation modifiers (Reset, Unset, etc.)
///
/// Returns an `Opt[Int]` whose value is the number of occurrences.
///
/// Example:
/// ```
/// let verbose = parser.count(name="verbose", shorts="v", description="Increase verbosity")
/// parser.parse!(["-vvv"])
/// assert_eq!(verbose.get(), Some(3))
/// ```
pub fn Parser::count(
  self : Parser,
  name~ : String,
  global? : Bool = false,
  aliases? : Array[String] = [],
  shorts? : String = "",
  description? : String = "",
  env? : String = "",
  visibility? : Visibility = Visible,
  variations? : Array[Variation] = [],
  variation_toggle? : String? = None,
  variation_true? : String? = None,
  variation_false? : String? = None,
  variation_reset? : String? = None,
  variation_unset? : String? = None,
) -> Opt[Int] {
  let env = self.effective_env_name(env, name, visibility)
  apply_variation_sugar(
    variations,
    variation_toggle~,
    variation_true~,
    variation_false~,
    variation_reset~,
    variation_unset~,
  )
  let (vc, acc) = make_value_cell(initial=0)
  let pending : Ref[Int] = { val: 0 }
  let reset_fn = fn() {
    vc.cell.val = 0
    pending.val = 0
  }
  let positive_match = make_flag_on_match(pending, vc.cell, fn(p) { p + 1 })
  let opt = self.register_option(
    name~,
    aliases~,
    shorts~,
    global~,
    visibility~,
    help=description,
    value_name="",
    default_display="",
    env_name=env,
    kind=Flag,
    variations~,
    valcell=vc,
    accessor=acc,
    make_main_node=fn(n) { make_flag_node(n, positive_match, reset_fn) },
    make_node_for_variation=fn(vn, v) {
      let var_reset = fn() {
        vc.cell.val = 0
        pending.val = 0
        vc.committed.val = false
      }
      match v {
        Reset(_) | Toggle(_) | True(_) | False(_) =>
          make_flag_node(
            vn,
            make_flag_on_match_with_committed(
              pending,
              vc.cell,
              vc.committed,
              fn(_p) { 0 },
              true,
            ),
            var_reset,
          )
        Unset(_) =>
          make_flag_node(
            vn,
            make_flag_on_match_with_committed(
              pending,
              vc.cell,
              vc.committed,
              fn(_p) { 0 },
              false,
            ),
            var_reset,
          )
      }
    },
  )
  register_env_applicator(self, env, vc, raw => {
    @string.parse_int(raw) catch {
      _ =>
        raise parse_error(
          "invalid value for env " + env + ": " + raw + " (expected integer)",
        )
    }
  })
  opt
}

///|
/// Creates a custom-typed option — the foundational combinator for all value options.
///
/// All typed option combinators (`string`, `int`, `float`, `boolean`) are
/// thin wrappers around `custom` with appropriate `pre` filters. Use `custom`
/// directly when you need a user-defined type or custom parsing logic.
///
/// Parameters:
/// - `name` - Long option name (e.g. "format" for `--format`)
/// - `default` - Default value when the option is not specified
/// - `pre` - Filter chain that converts the raw CLI string to type `T`
/// - `description` - Help text shown in `--help` output
/// - `post` - Optional filter chain applied after parsing (validation/transform)
/// - `choices` - Restrict accepted raw values to this list
/// - `implicit_value` - Value used when the flag is present without `=value`
/// - `shorts` - Single-character aliases (e.g. "f" for `-f`)
/// - `global` - If true, propagated to subcommand parsers
///
/// Returns an `Opt[T]` that can be queried after parsing.
///
/// Example:
/// ```
/// let level = parser.custom(
///   name="level",
///   default=Level::Info,
///   pre=Filter::map(fn(s) {
///     match s {
///       "debug" => Level::Debug
///       "info" => Level::Info
///       _ => Level::Warn
///     }
///   }),
///   description="Log level",
/// )
/// ```
pub fn[T : Show] Parser::custom(
  self : Parser,
  name~ : String,
  aliases? : Array[String] = [],
  shorts? : String = "",
  global? : Bool = false,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  default_display? : String? = None,
  visibility? : Visibility = Visible,
  variations? : Array[Variation] = [],
  default~ : T,
  default_fn? : (() -> T)? = None,
  pre~ : FilterChain[String, T],
  post? : FilterChain[T, T]? = None,
  choices? : Array[String] = [],
  implicit_value? : Lazy[T]? = None,
) -> Opt[T] {
  let env = self.effective_env_name(env, name, visibility)
  let initial_val = match default_fn {
    Some(f) => f()
    None => default
  }
  let effective_display = match default_display {
    Some(s) => s
    None => initial_val.to_string()
  }
  // choices 情報を help 文字列に付加（OptMeta にフィールドを持たない設計）
  let effective_help : String = if choices.length() > 0 {
    description + " [possible values: " + choices.join(", ") + "]"
  } else {
    description
  }
  let (vc, acc) = make_value_cell(initial=initial_val)
  let has_choices = choices.length() > 0
  let has_implicit = implicit_value is Some(_)

  // variation ノード: Toggle/True/False は Reset 相当にフォールバック（値コンビネータに Bool 反転の意味論なし）
  let make_var_node = fn(vn : String, v : Variation) -> ExactNode {
    match v {
      Reset(_) | Toggle(_) | True(_) | False(_) =>
        wrap_node_with_set(
          make_flag_node(vn, fn() { fn() { vc.cell.val = initial_val } }, fn() {
            vc.cell.val = initial_val
          }),
          vc.committed,
        )
      Unset(_) =>
        make_flag_node(
          vn,
          fn() {
            fn() {
              vc.cell.val = initial_val
              vc.committed.val = false
            }
          },
          fn() {
            vc.cell.val = initial_val
            vc.committed.val = false
          },
        )
    }
  }

  // before_pre_ref: adjust(before_pre=...) で後から修正可能。
  // None = 未使用（identity として振る舞い、追加コストなし）。
  let before_pre_ref : Ref[FilterChain[String, String]?] = { val: None }

  let make_main : (String) -> ExactNode = if has_implicit {
    let iv = match implicit_value {
      Some(v) => v
      None => Val(default) // unreachable
    }
    fn(opt_name : String) -> ExactNode {
      let children : Array[ExactNode] = []
      if has_choices {
        for choice in choices {
          children.push(
            make_custom_choice_value_node(
              opt_name,
              choice,
              pre,
              vc.cell,
              initial_val,
            ),
          )
        }
      } else {
        children.push(
          make_soft_custom_value_node(opt_name, pre, vc.cell, initial_val),
        )
      }
      children.push(make_implicit_flag_node(opt_name, iv, vc.cell, initial_val))
      make_or_node(opt_name, true, children)
    }
  } else {
    let pending : Ref[T] = { val: initial_val }
    let reset = fn() { vc.cell.val = initial_val }
    let accum : Accumulator[T, T] = fn(_current, piece) { piece }
    // choices がある場合は one_of → pre の合成。FilterChain::then で Kleisli composition
    let effective_pre : FilterChain[String, T] = if has_choices {
      Filter::one_of(choices).then(pre)
    } else {
      pre
    }
    // before_pre_ref を経由する最終 pre チェーン（None なら effective_pre をそのまま使用）
    let final_pre : FilterChain[String, T] = {
      run: fn(s) raise ParseError {
        let raw = match before_pre_ref.val {
          Some(chain) => (chain.run)(s)
          None => s
        }
        (effective_pre.run)(raw)
      },
    }
    let reducer = make_reducer(final_pre, accum)
    fn(opt_name : String) -> ExactNode {
      make_reduced_value_node(opt_name, reducer, vc.cell, pending, reset)
    }
  }

  let display_value_name = if value_name == "" {
    name.to_upper()
  } else {
    value_name
  }
  let opt = self.register_option(
    name~,
    aliases~,
    shorts~,
    global~,
    visibility~,
    help=effective_help,
    value_name=display_value_name,
    default_display=effective_display,
    env_name=env,
    kind=ValueOpt,
    variations~,
    valcell=vc,
    accessor=acc,
    make_main_node=make_main,
    make_node_for_variation=make_var_node,
  )
  // adjust(before_pre=...) 用に before_pre_ref を登録
  self.before_pre_refs[opt.id] = before_pre_ref
  // H-1 fix: implicit_value 付き (choices なし) の場合、eq_split 用に
  // "--" ガードなしの value ノードを追加。make_soft_custom_value_node の
  // "--" prefix ガードは通常パースで必要だが、eq_split 経由の明示的な値には不要。
  if has_implicit && !has_choices {
    let eq_on_match = fn(s : String) -> Result[() -> Unit, ParseError] {
      let r : Result[T, ParseError] = try? (pre.run)(s)
      match r {
        Ok(v) =>
          Ok(fn() {
            vc.cell.val = v
            vc.committed.val = true
          })
        Err(e) => Err(e)
      }
    }
    let eq_reset = fn() { () }
    let make_eq_fb : (String) -> ExactNode = fn(n) {
      make_value_node(n, eq_on_match, eq_reset)
    }
    self.eq_fallback_nodes.push(make_eq_fb("--" + name))
    for alt in aliases {
      self.eq_fallback_nodes.push(make_eq_fb("--" + alt))
    }
    // alias 登録時にも eq_fallback_nodes に追加できるようファクトリを保存
    match self.node_templates.get(opt.id) {
      Some(src) =>
        self.node_templates[opt.id] = NodeTemplate::{
          make_node: src.make_node,
          is_global: src.is_global,
          make_eq_fallback: Some(make_eq_fb),
        }
      None => ()
    }
  }
  match post {
    Some(filter) =>
      self.post_hooks.push(fn() raise ParseError {
        vc.cell.val = (filter.run)(vc.cell.val)
      })
    None => ()
  }
  // env applicator でも choices バリデーションを適用する
  let env_pre : FilterChain[String, T] = if has_choices {
    Filter::one_of(choices).then(pre)
  } else {
    pre
  }
  register_env_applicator(self, env, vc, raw => (env_pre.run)(raw))
  opt
}

///|
/// Creates a multi-value option that collects values into an array.
///
/// Each occurrence of the option on the command line appends a value to
/// the array. The `pre` filter converts each raw string to type `T`.
///
/// Parameters:
/// - `name` - Long option name (e.g. "include" for `--include`)
/// - `pre` - Filter chain that converts each raw CLI string to type `T`
/// - `description` - Help text shown in `--help` output
/// - `shorts` - Single-character aliases
/// - `global` - If true, propagated to subcommand parsers
///
/// Returns an `Opt[Array[T]]` that collects all occurrences.
///
/// Example:
/// ```
/// let tags = parser.append(name="tag", pre=Filter::map(fn(s) { s }), description="Add a tag")
/// parser.parse!(["--tag", "a", "--tag", "b"])
/// assert_eq!(tags.get(), Some(["a", "b"]))
/// ```
pub fn[T] Parser::append(
  self : Parser,
  name~ : String,
  aliases? : Array[String] = [],
  shorts? : String = "",
  global? : Bool = false,
  description? : String = "",
  env? : String = "",
  value_name? : String = "",
  visibility? : Visibility = Visible,
  variations? : Array[Variation] = [],
  pre~ : FilterChain[String, T],
) -> Opt[Array[T]] {
  let env = self.effective_env_name(env, name, visibility)
  // DR-0061 Phase 2: make_parallel_cell で ValCell + accessor + push/reset を一括生成
  let (vc, acc, push_fn, reset_fn) = make_parallel_cell()
  let display_value_name = if value_name == "" {
    name.to_upper()
  } else {
    value_name
  }
  let opt = self.register_option(
    name~,
    aliases~,
    shorts~,
    global~,
    visibility~,
    help=description,
    value_name=display_value_name,
    default_display="",
    env_name=env,
    kind=ValueOpt,
    variations~,
    valcell=vc,
    accessor=acc,
    make_main_node=fn(opt_n) {
      make_value_node(
        opt_n,
        fn(s) {
          let r : Result[T, ParseError] = try? (pre.run)(s)
          match r {
            Ok(v) => Ok(fn() { push_fn(v) })
            Err(e) => Err(e)
          }
        },
        reset_fn,
      )
    },
    make_node_for_variation=fn(vn, v) {
      match v {
        Reset(_) | Toggle(_) | True(_) | False(_) =>
          make_flag_node(
            vn,
            fn() {
              fn() {
                reset_fn()
                vc.committed.val = true
              }
            },
            fn() { reset_fn() },
          )
        Unset(_) =>
          make_flag_node(vn, fn() { fn() { reset_fn() } }, fn() { reset_fn() })
      }
    },
  )
  register_env_applicator(self, env, vc, raw => {
    let arr : Array[T] = []
    for part in raw.split(",") {
      arr.push((pre.run)(part.to_string()))
    }
    arr
  })
  opt
}
