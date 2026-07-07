///|
/// `kuu` core — MoonBit reference implementation of the kuu spec.
///
/// The evaluator core (node / value / matcher / result / eval / complete /
/// installer) is not implemented yet. It is designed from scratch in Phase B
/// with the two spec-side breakages as design inputs; see
/// `docs/decisions/MDR-001-bootstrap-policy.md`.
///
/// `spec_repo` names the specification's source of truth. The definition of
/// a "port" is: pass the conformance fixtures published there.
pub let spec_repo : String = "kawaz/kuu"
