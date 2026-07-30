// accumulator_ext.mbt — open accumulator and collector resident contracts.

///|
/// Resolve the value-source ladder below the CLI seat. An accumulator resident
/// invokes this capability only when its CLI fold does not commit a value or an
/// operation explicitly requests the current lower-seat value.
pub type LowerSeat = (Bool) -> Result[Array[Binding], ParseError]

///|
fn source_result(source : Source) -> ResultValue {
  let tag = match source {
    Cli => "cli"
    Link => "link"
    Env => "env"
    Config => "config"
    Tty => "tty"
    Const => "const"
    Default => "default"
  }
  Scalar(String(tag))
}

///|
/// Open accumulator contract. `resolve_cli` owns the accumulator-specific CLI fold. `collect` and
/// `collect_sources` must perform the same structural transformation for values and their paired
/// provenance; shape-changing residents cannot derive one independently from the other.
/// `kind + encode` is the resident's structural identity.
pub(open) trait AccumulatorExt {
  fn kind(Self) -> String
  fn encode(Self) -> Json
  fn equal(Self, &AccumulatorExt) -> Bool = _
  fn resolve_cli(Self, String, Array[Binding], Bool, LowerSeat) -> Result[
    Array[Binding],
    ParseError,
  ]
  fn collect(Self, Array[Value]) -> ResultValue
  fn collect_sources(Self, Array[(Value, Source)]) -> ResultValue
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
/// Open collector contract applied after an accumulator has produced its result value.
/// `collect_sources` receives both the pre-collector value and source trees so key promotion and
/// shape changes can preserve the source of each surviving value seat. Configured collectors include
/// their configuration in `encode`.
pub(open) trait CollectorExt {
  fn kind(Self) -> String
  fn encode(Self) -> Json
  fn equal(Self, &CollectorExt) -> Bool = _
  fn collect(Self, ResultValue) -> ResultValue
  fn collect_sources(Self, ResultValue, ResultValue) -> ResultValue
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
