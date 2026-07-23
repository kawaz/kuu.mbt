///|
/// Evaluation context exposed to node and matcher residents.
pub struct Ctx {
  priv tokens : Array[String]
  priv extensions_ : Registry
  priv complete_mode : Bool
}

///|
/// Construct an evaluation context. This constructor is reserved for the evaluator.
pub fn Ctx::new(
  tokens : Array[String],
  extensions : Registry,
  complete_mode : Bool,
) -> Ctx {
  { tokens, extensions_: extensions, complete_mode }
}

///|
pub fn Ctx::token_at(self : Ctx, position : Int) -> String? {
  if position >= 0 && position < self.tokens.length() {
    Some(self.tokens[position])
  } else {
    None
  }
}

///|
pub fn Ctx::is_complete_mode(self : Ctx) -> Bool {
  self.complete_mode
}

///|
pub fn Ctx::extensions(self : Ctx) -> Registry {
  self.extensions_
}

///|
/// A resume capability belongs to the current eval call and must not be retained.
pub type Resume = (Ctx, Int, Array[Binding]) -> Array[Branch]

///|
/// Resume every matcher reading through one evaluator continuation.
pub fn continue_matcher(
  readings : Array[Branch],
  ctx : Ctx,
  accumulated : Array[Binding],
  next : Resume,
) -> Array[Branch] {
  let output : Array[Branch] = []
  for reading in readings {
    match reading {
      Accept(next_position, bindings) =>
        for branch in next(ctx, next_position, accumulated + bindings) {
          output.push(branch)
        }
      Held(error, bindings) => output.push(Held(error, accumulated + bindings))
      Pending(candidates, bindings) =>
        output.push(Pending(candidates, accumulated + bindings))
    }
  }
  output
}
