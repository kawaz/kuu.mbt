// Public installer decode ABI.

///|
pub(all) enum DecodeCtx {
  Option
  Positional
  Command
} derive(Eq, Debug)

///|
pub(all) enum OwnedDeclaration {
  Long(LongDeclaration)
  Short(Array[Char])
  Env(Array[String])
  Dd(String?, Bool)
  Global(Bool)
  Inherit(Bool)
  Repeat(RepeatSpec?, Bool)
  Multiple(Bool, String?, CollectorDeclaration?, String?, Bool?)
  Config(Bool, Array[String]?)
  Constraint(Array[String], Array[String], Array[String], Array[String], Bool)
  Alias(AliasDef?)
  Inheritable(Bool)
  HelpMeta(HelpMetaDeclaration)
  Command
} derive(Eq, Debug)

///|
pub(all) struct DecodedOwnedDeclaration {
  vocab : Array[String]
  declaration : OwnedDeclaration
}
