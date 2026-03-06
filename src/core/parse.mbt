///| self.nodes から short option ノードを収集し、結合ノードを構築して self.nodes に追加
fn Parser::install_short_combine_node(self : Parser) -> Unit {
  let short_nodes : Array[ExactNode] = []
  for node in self.nodes {
    if node.name.length() == 2 && node.name.has_prefix("-") && not(node.name.has_prefix("--")) {
      short_nodes.push(node)
    }
  }
  if short_nodes.is_empty() { return }

  let combine_node = ExactNode::{
    name: "",
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() { return Reject }
      let arg = args[pos]
      if arg.length() <= 2 || not(arg.has_prefix("-")) || arg.has_prefix("--") {
        return Reject
      }
      let rest = arg.unsafe_substring(start=1, end=arg.length())
      let commits : Array[() -> Unit] = []
      let mut total_consumed = 1
      let mut ri = 0

      while ri < rest.length() {
        let ch = rest[ri].to_int().unsafe_to_char()
        let short_name = "-" + ch.to_string()

        let mut found : ExactNode? = None
        for sn in short_nodes {
          if sn.name == short_name { found = Some(sn); break }
        }
        match found {
          None => return Reject
          Some(node) => {
            // Step 1: フラグとして試行
            match (node.try_reduce)([short_name], 0) {
              Accept(commit~, ..) => { commits.push(commit); ri += 1; continue }
              Error(_) | Reject => ()
            }

            // Step 2: 値を取るオプションとして試行
            let remaining = rest.unsafe_substring(start=ri + 1, end=rest.length())

            if remaining.length() > 0 {
              let mut value_accepted = false
              let mut try_len = remaining.length()
              while try_len > 0 {
                let try_value = remaining.unsafe_substring(start=0, end=try_len)
                match (node.try_reduce)([short_name, try_value], 0) {
                  Accept(commit~, ..) => {
                    commits.push(commit)
                    ri = ri + 1 + try_len
                    value_accepted = true
                    break
                  }
                  Error(_) =>
                    if try_len > 1 { try_len -= 1 }
                    else {
                      match (node.try_reduce)([short_name, remaining], 0) {
                        Error(e) => return Error(e)
                        _ => return Reject
                      }
                    }
                  _ => return Reject
                }
              }
              if not(value_accepted) { return Reject }
            } else {
              if pos + 1 < args.length() {
                match (node.try_reduce)([short_name, args[pos + 1]], 0) {
                  Accept(commit~, ..) => {
                    commits.push(commit)
                    total_consumed = 2
                    ri = rest.length()
                  }
                  Error(e) => return Error(e)
                  _ => return Reject
                }
              } else {
                return Error(parse_error("missing value for " + short_name))
              }
            }
          }
        }
      }

      Accept(consumed=total_consumed, commit=fn() { for c in commits { c() } })
    },
    reset: fn() {},
  }
  self.nodes.push(combine_node)
}

///|
fn Parser::parse_raw(
  self : Parser,
  args : Array[String],
) -> ParseResult raise ParseError {
  self.install_short_combine_node()
  let mut pos = 0
  while pos < args.length() {
    // Handle `--` separator: enable force_positional and consume `--`
    if args[pos] == "--" && not(self.force_positional.val) {
      self.force_positional.val = true
      pos = pos + 1
      continue
    }
    let mut best_consumed = 0
    let mut best_commit : (() -> Unit)? = None
    let mut ambiguous = false
    // When force_positional is active, skip ExactNode matching
    if not(self.force_positional.val) {
      // Check if current arg contains '=' for --name=value syntax
      // Only apply eq_split to args starting with "--" (not commands or positionals)
      let eq_split : (Array[String], Int)? = if args[pos].has_prefix("--") {
        args[pos]
        .find("=")
        .map(fn(eq_pos) {
          let name = args[pos].unsafe_substring(start=0, end=eq_pos)
          let value = args[pos].unsafe_substring(
            start=eq_pos + 1,
            end=args[pos].length(),
          )
          ([name, value], 1)
        })
      } else {
        None
      }
      for node in self.nodes {
        // Try with equals-split args first, then original args
        let result = match eq_split {
          Some((split_args, actual_consumed)) =>
            match (node.try_reduce)(split_args, 0) {
              Accept(consumed~, commit~) =>
                if consumed > 0 {
                  Accept(consumed=actual_consumed, commit~)
                } else {
                  Reject
                }
              other => other
            }
          None => (node.try_reduce)(args, pos)
        }
        match result {
          Accept(consumed~, commit~) =>
            if consumed > best_consumed {
              best_consumed = consumed
              best_commit = Some(commit)
              ambiguous = false
            } else if consumed == best_consumed && consumed > 0 {
              ambiguous = true
            }
          Reject => ()
          Error(e) => raise e
        }
      }
      if ambiguous {
        raise parse_error("ambiguous argument: " + args[pos])
      }
    }
    match best_commit {
      Some(commit) => {
        commit()
        pos = pos + best_consumed
      }
      None =>
        if self.current_positional.val < self.positionals.length() {
          let idx = self.current_positional.val
          let (handler, is_rest) = self.positionals[idx]
          match handler(args, pos) {
            Accept(consumed~, commit~) => {
              commit()
              if not(is_rest) {
                self.current_positional.val = idx + 1
              }
              pos = pos + consumed
            }
            Reject => raise parse_error("unexpected argument: " + args[pos])
            Error(e) => raise e
          }
        } else {
          raise parse_error("unexpected argument: " + args[pos])
        }
    }
  }
  self.parsed.val = true
  let kind = if self.children.length() > 0 {
    Map_(self.children)
  } else {
    One
  }
  { kind, parser: self }
}

///|
pub fn Parser::parse(
  self : Parser,
  args : Array[String],
) -> ParseResult raise ParseError {
  let result : Result[ParseResult, ParseError] = try? self.parse_raw(args)
  match result {
    Ok(r) => r
    Err(ParseError(info)) =>
      if info.help_text == "" {
        raise ParseError(ParseErrorInfo::{ ..info, help_text: self.generate_help() })
      } else {
        raise ParseError(info)
      }
    Err(e) => raise e
  }
}
