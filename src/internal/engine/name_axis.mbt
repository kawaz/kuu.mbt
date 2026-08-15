// name_axis.mbt — DR-136 §3: the character map that supplies `name` to each axis.
//
// `name` is a generic name-source: it never reaches the CLI surface nor the result
// object by itself. Each axis that leaves `name` unspecified is filled by a
// **character-wise 1:1 map** (no pre-pass, no folding of runs):
//
//   | source char                     | id / export_key / value_name | trigger_name |
//   |---------------------------------|------------------------------|--------------|
//   | ASCII alnum (`0-9A-Za-z`)       | kept                         | kept         |
//   | non-ASCII (Japanese etc.)       | kept                         | kept         |
//   | any other ASCII (symbol/space)  | `_`                          | `-`          |
//
// `value_name` additionally upper-cases ASCII letters; `display_name` takes the raw
// `name` and never passes through here (DR-136 §1/§3).
//
// The map is deliberately non-folding — `foo  bar` becomes `foo__bar`, not `foo_bar` — so it
// stays length-preserving and position-wise: every character of the axis value traces back to
// exactly one character of the name. The map is NOT injective (every replaced symbol shares one
// replacement, so `a-b` and `a b` both yield `a_b`); folding would collapse names differing in the
// NUMBER of symbols on top of that, which is the extra merging DR-136 §3 rules out.

///|
/// True for the characters every axis keeps verbatim: ASCII alphanumerics and the whole
/// non-ASCII range (i18n names are a first-class use case, DR-136 §3).
fn axis_char_is_kept(c : Char) -> Bool {
  let code = c.to_int()
  if code >= 0x80 {
    return true
  }
  (code >= 0x30 && code <= 0x39) ||
  (code >= 0x41 && code <= 0x5A) ||
  (code >= 0x61 && code <= 0x7A)
}

///|
/// DR-136 §3 の文字写像本体。保持対象以外の ASCII (記号・空白) を `filler` へ 1:1 で置換する。
fn map_name_axis(name : String, filler : Char) -> String {
  let buf = StringBuilder::new()
  for c in name {
    if axis_char_is_kept(c) {
      buf.write_char(c)
    } else {
      buf.write_char(filler)
    }
  }
  buf.to_string()
}

///|
/// `name` → 参照識別子軸 / 結果キー軸の綴り (ASCII 非英数 → `_`、DR-136 §3)。
pub fn name_axis_id(name : String) -> String {
  map_name_axis(name, '_')
}

///|
/// `name` → 綴り (トリガ) 軸の綴り (ASCII 非英数 → `-`、DR-136 §3)。long の基幹綴り・
/// command のトリガ照合・alias の入口綴りはこの軸から取る。
pub fn name_axis_trigger(name : String) -> String {
  map_name_axis(name, '-')
}

///|
/// `name` → 値プレースホルダ軸の綴り (id 系の写像 + ASCII 英字の大文字化、DR-136 §3)。
pub fn name_axis_value_name(name : String) -> String {
  let buf = StringBuilder::new()
  for c in map_name_axis(name, '_') {
    let code = c.to_int()
    if code >= 0x61 && code <= 0x7A {
      buf.write_char((code - 32).unsafe_to_char())
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}
