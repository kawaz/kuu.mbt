// accumulator_ext.mbt — open accumulator and collector resident contracts.

///|
/// Resolve the value-source ladder below the CLI seat. An accumulator resident
/// invokes this capability only when its CLI fold does not commit a value or an
/// operation explicitly requests the current lower-seat value.
pub type LowerSeat = (Bool) -> Result[Array[Binding], ParseError]

///|
/// Open accumulator contract. `resolve_cli` owns the accumulator-specific CLI
/// fold, while `collect` projects the resulting value sequence into the recursive
/// result shape. `kind + encode` is the resident's structural identity.
pub(open) trait AccumulatorExt {
  fn kind(Self) -> String
  fn encode(Self) -> Json
  fn equal(Self, &AccumulatorExt) -> Bool = _
  fn resolve_cli(Self, String, Array[Binding], Bool, LowerSeat) -> Result[
    Array[Binding],
    ParseError,
  ]
  fn collect(Self, Array[Value]) -> ResultValue
}

///|
impl AccumulatorExt with fn equal(self, other) {
  self.kind() == other.kind() && self.encode() == other.encode()
}

///|
pub impl Eq for &AccumulatorExt with fn equal(self, other) {
  self.equal(other)
}

///|
pub impl Debug for &AccumulatorExt with fn to_repr(self) {
  Debug::to_repr((self.kind(), self.encode()))
}

///|
/// Open collector contract applied after an accumulator has produced its result
/// value. Configured collectors include their configuration in `encode`.
pub(open) trait CollectorExt {
  fn kind(Self) -> String
  fn encode(Self) -> Json
  fn equal(Self, &CollectorExt) -> Bool = _
  fn collect(Self, ResultValue) -> ResultValue
}

///|
impl CollectorExt with fn equal(self, other) {
  self.kind() == other.kind() && self.encode() == other.encode()
}

///|
pub impl Eq for &CollectorExt with fn equal(self, other) {
  self.equal(other)
}

///|
pub impl Debug for &CollectorExt with fn to_repr(self) {
  Debug::to_repr((self.kind(), self.encode()))
}
