// entity_ext.mbt — builtin declaration metadata behind the opaque engine EntityExt slot.

///|
priv struct BuiltinEntityExt {
  hidden : Bool
  completer : String?
}

///|
impl @engine.EntityExt for BuiltinEntityExt with fn encode(self) {
  [self.hidden.to_json(), self.completer.to_json()].to_json()
}

///|
impl @engine.EntityExt for BuiltinEntityExt with fn complete_candidate(
  self,
  candidate,
) {
  {
    ..candidate,
    hidden: self.hidden,
    completer: if candidate.is_value {
      self.completer
    } else {
      None
    },
  }
}

///|
pub fn entity_ext(
  hidden? : Bool = false,
  completer? : String? = None,
) -> &@engine.EntityExt {
  BuiltinEntityExt::{ hidden, completer } as &@engine.EntityExt
}
