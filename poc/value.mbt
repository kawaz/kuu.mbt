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
  Inherit // nearest ancestor scope's same-named value (DR-031 #4 / DR-013)
  Default // fixed fallback (DR-031 #5)
} derive(Eq, Show)

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
