///|
/// struct を対象に CLI 引数をパースし、結果を直接注入する。
/// エラー時は target の状態はデフォルトのまま（apply_all は呼ばれない）。
pub fn[T : Parseable] parse_into(
  args : Array[String],
  target : T,
  env? : Map[String, String] = {},
) -> Unit raise @core.ParseError {
  let parser = @core.Parser::new()
  let registry = FieldRegistry::new(parser)
  target.register(registry)
  let _ = parser.parse(args, env~)
  registry.apply_all()
}
