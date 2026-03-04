///| ファイル内容を引数に分割する（gcc/javac 方式）
/// 改行と空白で分割し、ダブルクォート/シングルクォートを考慮する。
/// 空行・空白のみの行はスキップ。\r\n 対応。
/// 未閉じクォートは最後までバッファを蓄積してトークン化する（エラーなし）。
/// 末尾のバックスラッシュはリテラル `\` として扱う。
fn split_args(s : String) -> Array[String] {
  let args : Array[String] = []
  let buf = StringBuilder::new()
  let mut in_single_quote = false
  let mut in_double_quote = false
  let mut prev_was_backslash = false
  let mut had_quote = false
  for c in s {
    if prev_was_backslash {
      buf.write_char(c)
      prev_was_backslash = false
      continue
    }
    if c == '\\' && not(in_single_quote) {
      prev_was_backslash = true
      continue
    }
    if c == '\'' && not(in_double_quote) {
      in_single_quote = not(in_single_quote)
      had_quote = true
      continue
    }
    if c == '"' && not(in_single_quote) {
      in_double_quote = not(in_double_quote)
      had_quote = true
      continue
    }
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') &&
      not(in_single_quote) &&
      not(in_double_quote) {
      let token = buf.to_string()
      if token.length() > 0 || had_quote {
        args.push(token)
      }
      buf.reset()
      had_quote = false
      continue
    }
    buf.write_char(c)
  }
  // 末尾のバックスラッシュはリテラルとして扱う
  if prev_was_backslash {
    buf.write_char('\\')
  }
  // 最後のトークン
  let last = buf.to_string()
  if last.length() > 0 || had_quote {
    args.push(last)
  }
  args
}

// Design rationale: substring() の代わりに str[:].to_string() を使うべきだが、
// str[:] は raise 可能な関数であり、preprocessor コールバック型 (Array[String]) -> Array[String] は
// raise をサポートしない。has_prefix チェック済みで範囲外アクセスは起きないため substring() を使用する。

///| @file 展開プリプロセッサを登録する（gcc/javac 方式）。
///  `@path` 形式の引数をファイル内容の各トークンに展開する。
///  ファイル内容は空白・改行で分割し、クォート（`"`, `'`）とバックスラッシュエスケープを考慮する。
///  `@@` は `@` にエスケープされる。ネストした @file は展開しない（1段階のみ）。
///  ファイルが見つからない場合（`read_file` が None を返す場合）は引数をそのまま残す。
///  `read_file` コールバックはファイルパスを受け取り内容を返す。パス検証は呼び出し側の責任。
pub fn expand_at_files(
  parser : @core.Parser,
  read_file~ : (String) -> String?
) -> Unit {
  parser.add_preprocessor(fn(args) {
    let result : Array[String] = []
    for arg in args {
      if arg.has_prefix("@@") {
        // @@ エスケープ: 先頭の @ を1つ除去
        result.push(arg.substring(start=1))
      } else if arg.has_prefix("@") && arg.length() > 1 {
        // @file 展開
        let path = arg.substring(start=1)
        match read_file(path) {
          Some(content) => {
            let tokens = split_args(content)
            for token in tokens {
              result.push(token)
            }
          }
          None =>
            // ファイルが見つからない場合はそのまま残す
            result.push(arg)
        }
      } else {
        result.push(arg)
      }
    }
    result
  })
}
