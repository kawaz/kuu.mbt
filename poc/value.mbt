// value.mbt — value cells, provenance tags, and the tolerant number parser.
//
// These are the leaf currency of the evaluator: a parsed CLI token becomes a
// `Value`, tagged with the `Source` seat it came from (DR-031 ladder), and
// collected as `Binding`s onto a result path.

/// A resolved value that can land in the result object.
pub(all) enum Value {
  VStr(String)
  VNum(Double)
  VBool(Bool)
} derive(Eq, Show)

/// Provenance of a value cell (DR-031 / DR-016 source tag).
/// The evaluator preserves this so an appconfig store (DR-030) can ask
/// "where did this value come from" without the ladder order being movable.
pub(all) enum Source {
  Cli // CLI explicit / link — highest seat (DR-031 #1)
  Env // environment variable seat (DR-031 #2)
  Config // config-file seat (DR-050 #3) — below env, above inherit
  Inherit // nearest ancestor scope's same-named value (DR-031 #4 / DR-013)
  Default // fixed fallback (DR-031 #5)
} derive(Eq, Show)

/// A JSON-同型 hierarchical config value (DR-050 §2): what a config_provider returns. kuu core
/// never sees TOML/YAML — only this shape. Leaf values are typed (string / number / bool); arrays
/// feed a multiple element's pieces; objects mirror the name-scope hierarchy (同型対応).
pub(all) enum ConfigVal {
  CStr(String)
  CNum(Double)
  CBool(Bool)
  CArr(Array[ConfigVal])
  CObj(Array[(String, ConfigVal)])
  CNull // JSON null (DR-050 §4 / DR-051): treated as 供給なし — the config seat supplies nothing
} derive(Eq, Show)

/// Whether a double is integer-valued (for the int type's constraint, DESIGN §3.3 / DR-050 §4).
pub fn is_integer(d : Double) -> Bool {
  d.to_int().to_double() == d
}

/// The category of a held Error (DR-053 §2 / DR-037 / DR-047): `parse` = type parse failure,
/// `filter` = a post_filter reject (a value that parsed but failed a filter), `constraint` = a
/// delayed-predicate violation (required 未充足 etc., DR-047). All three ride the errors array.
pub(all) enum ErrKind {
  KParse
  KFilter
  KConstraint
} derive(Eq, Show)

/// One held Error (DR-053 §2): which element, the argv position it failed at, its kind, and the
/// message. The errors array keeps ALL of them (別候補経路の別 Error); primary = max argv_pos.
pub(all) struct ParseError {
  element : String
  argv_pos : Int
  kind : ErrKind
  message : String
} derive(Eq, Show)

/// JSON-standard string form of a config number (DR-050 §4 stringification). An integer-valued
/// double renders without a fractional part (1.0 → "1"); otherwise the decimal form (1.5 → "1.5").
/// NB: whether an integer-valued float keeps ".0" is a serialize choice — see the 第 10 弾 flag.
fn num_to_string(d : Double) -> String {
  let i = d.to_int()
  if i.to_double() == d {
    i.to_string()
  } else {
    d.to_string()
  }
}

/// Convert one leaf config value to the element's expected type (DR-050 §4). The element's `type`
/// IS the expected type. Leniency is BIDIRECTIONALLY SYMMETRIC (kawaz 裁定 a, DR-040 canonical 最寛容):
/// a string parses into any type (`"8080"` → number), AND a JSON scalar stringifies into a string
/// element (`1.5` → "1.5", `true` → "true") — a string element accepts anything in CLI/env, so
/// config observes the same (引用符の有無で挙動が割れない). Only the 意味の飛躍 (bool ↔ number
/// coercion) and 構造不一致 (array/object → a scalar element) are DR-037 Errors.
pub fn config_to_value(cv : ConfigVal, ty : Ty) -> Result[Value, String] {
  match (cv, ty) {
    // string element: accept anything — string / lenient parse / JSON stringification
    (CStr(s), TStr) => Ok(VStr(s))
    (CNum(d), TStr) => Ok(VStr(num_to_string(d))) // 1.5 → "1.5" (寛容の双方向対称)
    (CBool(b), TStr) => Ok(VStr(if b { "true" } else { "false" })) // true → "true"
    // string → number: lenient parse (テキストから型へ)
    (CStr(s), TNum) =>
      match parse_number(s) {
        Some(d) => Ok(VNum(d))
        None => Err("config value \"\{s}\" is not a number")
      }
    // string → int: parse AND require integer (DR-050 §4 int 行: 整数構文のみ)
    (CStr(s), TInt) =>
      match parse_number(s) {
        Some(d) =>
          if is_integer(d) {
            Ok(VNum(d))
          } else {
            Err("config value \"\{s}\" is not an integer")
          }
        None => Err("config value \"\{s}\" is not a number")
      }
    (CStr(s), TFlag) => Ok(VBool(s == "true" || s == "1"))
    // typed number matching a number element (any) / an int element (integer only)
    (CNum(d), TNum) => Ok(VNum(d))
    (CNum(d), TInt) =>
      if is_integer(d) {
        Ok(VNum(d))
      } else {
        Err("config value \"\{num_to_string(d)}\" is not an integer")
      }
    (CBool(b), TFlag) => Ok(VBool(b))
    // 意味の飛躍 (bool ↔ number) は Error — no coercion
    (CNum(_), TFlag) => Err("config number for a bool element (no number↔bool coercion)")
    (CBool(_), TNum) => Err("config bool for a number element (no number↔bool coercion)")
    (CBool(_), TInt) => Err("config bool for an int element (no number↔bool coercion)")
    // 構造不一致 (array / object → scalar element) は Error
    (CArr(_), _) => Err("config array for a scalar element (structural mismatch)")
    (CObj(_), _) => Err("config object for a scalar element (structural mismatch)")
    // null is 供給なし (handled before this by resolve; defensive arm for exhaustiveness, DR-050 §4)
    (CNull, _) => Err("config null is 供給なし (should be handled as no-supply, not converted)")
  }
}

/// The effect an entry's firing applies to a value cell (DR-045). It is PURE DATA
/// `{op, operand?}`: the op names the operation, the operand is the Binding's `value`.
/// A normal value bind (a value slot consuming a token and writing it) is the SET
/// degenerate form, so every effect-column element is uniform (entity, op, operand,
/// source, order). `default`/`unset`/`empty` carry NO operand (the Binding's value is a
/// placeholder). The four ops correspond 1:1 to DR-011's variant effect vocabulary.
pub(all) enum EffectOp {
  Set // write the operand; committed (the degenerate form of a plain value bind)
  Default // reset to the default value; committed (the user explicitly wants default)
  Unset // reset to the default; NOT committed — later ladder seats (env/config/inherit) may override
  Empty // clear a collection (array / map) to empty; committed
} derive(Eq, Show)

/// committed is DERIVED from the op, never a separate field (DR-045 §2: selected and
/// committed are independent, and the effect explicitly controls committed). Only `unset`
/// is un-committed, which is exactly what opens the later value-source ladder seats.
pub fn committed(op : EffectOp) -> Bool {
  match op {
    Unset => false
    _ => true
  }
}

/// One EFFECT written onto a result path: `key`'s cell gets operation `op` with operand
/// `value`, from `source` (DR-045). `key` is the leaf name; same-key bindings from
/// different entries (e.g. `--port` satellite and `-p` matcher) merge onto one cell =
/// link 合流. `scope` is the result nesting path (DR-025): a binding produced inside a
/// command / name scope carries that scope's labels, outermost first.
///
/// Path-counting (DR-038) treats the whole binding as identity, so op/operand are part of
/// the effect-sequence key (DR-045 §1 精密化): the same cell reset by `unset` vs written by
/// `set` are DIFFERENT effects even at the same position. A value in `serve` differs from
/// the same leaf at root (scope is in the key too).
pub(all) struct Binding {
  key : String
  op : EffectOp // the operation on the cell (DR-045); Set for a plain value bind
  value : Value // the operand (a placeholder for default/unset/empty, which carry none)
  source : Source
  scope : Array[String]
  link : Bool // a link/root-targeted binding (DR-042/007): stays at the declaring (root)
  //           scope — result nesting (CmdSat/Scoped) does NOT prepend a label to it.
} derive(Eq, Show)

/// Tolerant number parser used by `Num` primitives and value-attach matchers.
///
/// Accepts an optional leading sign, digits with an optional single decimal
/// point, and an optional trailing `f` float marker. The `f` marker is the
/// crux of DR-038's `-n1.0f` example: it makes BOTH `"1.0f"` and `"1.0"` parse,
/// so the short value-attach matcher yields two readings (value="1.0f" vs
/// value="1.0" + `-f` flag) and the path-search correctly reports ambiguous.
pub fn parse_number(s : String) -> Double? {
  if s.length() == 0 {
    return None
  }
  let mut i = 0
  let n = s.length()
  let mut neg = false
  if s[0] == '+' || s[0] == '-' {
    neg = s[0] == '-'
    i = 1
  }
  let mut int_part = 0.0
  let mut saw_digit = false
  while i < n && s[i] >= '0' && s[i] <= '9' {
    int_part = int_part * 10.0 + (s[i].to_int() - '0'.to_int()).to_double()
    saw_digit = true
    i = i + 1
  }
  let mut frac = 0.0
  let mut scale = 1.0
  if i < n && s[i] == '.' {
    i = i + 1
    while i < n && s[i] >= '0' && s[i] <= '9' {
      scale = scale / 10.0
      frac = frac + (s[i].to_int() - '0'.to_int()).to_double() * scale
      saw_digit = true
      i = i + 1
    }
  }
  // optional single trailing float marker
  if i < n && (s[i] == 'f' || s[i] == 'F') {
    i = i + 1
  }
  if !saw_digit || i != n {
    return None
  }
  let mag = int_part + frac
  Some(if neg { -mag } else { mag })
}
