///|
fn Parser::try_short_combine(
  self : Parser,
  args : Array[String],
  pos : Int,
) -> TryResult {
  let arg = args[pos]
  // chars = arg without leading '-'
  let chars = arg.unsafe_substring(start=1, end=arg.length())
  let commits : Array[() -> Unit] = []
  let mut total_consumed = 1 // at least the original arg
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i].to_int().unsafe_to_char()
    let short_name = "-" + ch.to_string()
    // Find the node with this short name
    let mut found : ExactNode? = None
    for node in self.nodes {
      if node.name == short_name {
        found = Some(node)
        break
      }
    }
    match found {
      None => return Reject // unknown short option, abandon combining
      Some(node) =>
        if node.needs_value {
          // Value option: consume remaining chars or next arg as value
          let remaining = chars.unsafe_substring(start=i + 1, end=chars.length())
          if remaining.length() > 0 {
            // Use remaining string as value: e.g. -oArg -> [-o, Arg]
            let synth_args = [short_name, remaining]
            match (node.try_reduce)(synth_args, 0) {
              Accept(commit~, ..) => {
                commits.push(commit)
                i = chars.length() // consumed all remaining chars
              }
              Error(e) => return Error(e)
              _ => return Reject
            }
          } else {
            // No remaining chars, consume next arg as value
            if pos + 1 < args.length() {
              let synth_args = [short_name, args[pos + 1]]
              match (node.try_reduce)(synth_args, 0) {
                Accept(commit~, ..) => {
                  commits.push(commit)
                  total_consumed = 2
                  i = chars.length() // done
                }
                Error(e) => return Error(e)
                _ => return Reject
              }
            } else {
              return Error(ParseError("missing value for " + short_name))
            }
          }
        } else {
          // Flag option
          let synth_args = [short_name]
          match (node.try_reduce)(synth_args, 0) {
            Accept(commit~, ..) => commits.push(commit)
            Error(e) => return Error(e)
            _ => return Reject
          }
          i = i + 1
        }
    }
  }
  // All chars consumed successfully
  Accept(
    consumed=total_consumed,
    commit=fn() {
      for c in commits {
        c()
      }
    },
  )
}

///|
pub fn Parser::parse(
  self : Parser,
  args : Array[String],
) -> ParseResult raise ParseError {
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
        raise ParseError("ambiguous argument: " + args[pos])
      }
    }
    // Try short option combining if no ExactNode matched
    if best_commit.is_empty() && not(self.force_positional.val) {
      let arg = args[pos]
      if arg.has_prefix("-") && not(arg.has_prefix("--")) && arg.length() > 2 {
        match self.try_short_combine(args, pos) {
          Accept(consumed~, commit~) => {
            best_consumed = consumed
            best_commit = Some(commit)
          }
          Error(e) => raise e
          Reject => ()
        }
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
            Reject => raise ParseError("unexpected argument: " + args[pos])
            Error(e) => raise e
          }
        } else {
          raise ParseError("unexpected argument: " + args[pos])
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
