///|
pub fn Parser::parse(
  self : Parser,
  args : Array[String],
) -> Unit raise ParseError {
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
}
