///| ParseError を人間可読な文字列にフォーマットする
pub fn format_error(
  err : @core.ParseError,
  nodes~ : Array[@core.ErasedNode] = [],
  program_name~ : String = ""
) -> String {
  let buf = StringBuilder::new()
  match err {
    @core.ParseError::Usage(kind, msg, ctx) => {
      buf.write_string("error: ")
      buf.write_string(msg)
      // Design rationale: did-you-mean は UnknownOption のみに適用する。
      // AmbiguousMatch は「入力が複数候補にプレフィックス一致する」エラーであり、
      // 単一のサジェストではなく候補の絞り込み（より長い名前の入力）が正しい対応。
      // AmbiguousMatch の候補一覧表示は Step 9（ヘルプ生成）で対応予定。
      match kind {
        @core.ErrorKind::UnknownOption =>
          if nodes.length() > 0 {
            let candidates = collect_option_names(nodes)
            match suggest(ctx.option_name, candidates) {
              Some(candidate) => {
                buf.write_string("\n  tip: a similar option exists: '--")
                buf.write_string(candidate)
                buf.write_string("'")
              }
              None => ()
            }
          }
        _ => ()
      }
      // Usage line
      if program_name.length() > 0 {
        buf.write_string("\nUsage: ")
        buf.write_string(program_name)
        buf.write_string(" [OPTIONS]")
      }
    }
    @core.ParseError::Internal(msg) => {
      buf.write_string("internal error: ")
      buf.write_string(msg)
    }
  }
  buf.to_string()
}

///| nodes から option 名（name + aliases）を収集する
fn collect_option_names(nodes : Array[@core.ErasedNode]) -> Array[String] {
  let names : Array[String] = []
  for node in nodes {
    if node.meta.kind == @core.Kind::Option {
      names.push(node.meta.name)
      for alias in node.meta.aliases {
        names.push(alias.name)
      }
    }
  }
  names
}
