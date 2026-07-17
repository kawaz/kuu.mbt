// result_value.mbt — engine-owned recursive result projection value.

///|
/// A built result value. The engine contract owns this general recursive shape;
/// the kuu front door decides when and how it is exposed to users.
pub(all) enum RVal {
  RScalar(Value)
  RArr(Array[RVal])
  RObj(Array[(String, RVal)])
} derive(Eq, Debug)

///|
pub fn rval_scalar(value : Value) -> RVal {
  RScalar(value)
}

///|
pub fn rval_array(values : Array[RVal]) -> RVal {
  RArr(values)
}

///|
pub fn rval_object(fields : Array[(String, RVal)]) -> RVal {
  RObj(fields)
}
