// result_value.mbt — engine-owned recursive result projection value.

///|
/// A built result value. The engine contract owns this general recursive shape;
/// the kuu front door decides when and how it is exposed to users.
pub(all) enum RVal {
  Scalar(Value)
  Array(Array[RVal])
  Object(Array[(String, RVal)])
} derive(Eq, Debug)
