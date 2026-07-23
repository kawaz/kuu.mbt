// Public extension traits for types, entities, and matchers.

///|
/// Input to a type resident's default-seat resolver. `declared` is the explicit
/// scalar default, if any. `observed` is provider data selected by the resident's
/// opaque key; engine transports the JSON value without knowing its schema.
pub struct SeatCtx {
  priv declared : Value?
  priv observed : Json?
}

///|
pub fn SeatCtx::new(declared : Value?, observed? : Json? = None) -> SeatCtx {
  { declared, observed }
}

///|
pub fn SeatCtx::declared(self : SeatCtx) -> Value? {
  self.declared
}

///|
pub fn SeatCtx::observed(self : SeatCtx) -> Json? {
  self.observed
}

///|
/// Open type-category contract. Value lexicons and preset defaults belong to
/// residents; the evaluator sees only this capability surface. A resident may
/// request one provider observation by opaque key and interpret its JSON payload
/// inside `default_seat_resolver`.
pub(open) trait TypeExt {
  fn name(Self) -> String
  fn encode(Self) -> Json = _
  fn has_value_slot(Self) -> Bool
  fn parse_token(Self, String) -> Result[Value, TypeParseFail]
  fn completion_values(Self) -> Array[String] = _
  fn default_seat_observation_key(Self) -> String? = _
  fn default_seat_resolver(Self, SeatCtx) -> Value?
}

///|
impl TypeExt with fn encode(_self) {
  ().to_json()
}

///|
/// Optional finite suggestions for a value position. The empty default keeps ordinary open value
/// spaces unchanged; preset residents may offer candidates without changing `parse_token`'s accepted
/// domain.
impl TypeExt with fn completion_values(_self) {
  []
}

///|
impl TypeExt with fn default_seat_observation_key(_self) {
  None
}

///|
/// Opaque declaration metadata attached to an Entity. Engine dispatches the
/// capability without inspecting builtin-owned fields; the resident projects
/// them onto the stable candidate wire structure.
pub(open) trait EntityExt {
  fn encode(Self) -> Json = _
  fn complete_candidate(Self, Candidate) -> Candidate
}

///|
impl EntityExt with fn encode(_self) {
  ().to_json()
}

///|
pub impl Eq for &EntityExt with fn equal(self, other) {
  self.encode() == other.encode()
}

///|
pub impl Debug for &EntityExt with fn to_repr(self) {
  Debug::to_repr(self.encode())
}

///|
/// A type resident's structural identity includes both its registry name and
/// parser configuration, matching NodeExt's kind-plus-encode contract.
pub impl Eq for &TypeExt with fn equal(self, other) {
  self.name() == other.name() && self.encode() == other.encode()
}

///|
pub impl Debug for &TypeExt with fn to_repr(self) {
  Debug::to_repr((self.name(), self.encode()))
}

///|
/// Open native-matcher contract. Concrete reading semantics and configuration
/// live in residents. `candidates` is required because every matcher owns its
/// boundary completion spellings; `interpret` may receive an exhausted position
/// and must treat it as no reading. The engine invokes both capability surfaces.
pub(open) trait MatcherExt {
  fn kind(Self) -> String
  fn encode(Self) -> Json
  fn equal(Self, &MatcherExt) -> Bool = _
  fn candidates(Self) -> Array[Candidate]
  fn interpret(Self, Ctx, Int, Array[Binding], Resume) -> Array[Branch]
}

///|
impl MatcherExt with fn equal(self, other) {
  self.kind() == other.kind() && self.encode() == other.encode()
}

///|
pub impl Eq for &MatcherExt with fn equal(self, other) {
  self.equal(other)
}

///|
pub impl Debug for &MatcherExt with fn to_repr(self) {
  Debug::to_repr((self.kind(), self.encode()))
}
