///| self.nodes から --name=value 形式を処理する ExactNode を構築して追加
fn Parser::install_eq_split_node(self : Parser) -> Unit {
  // needs_value=true かつ name が "--" で始まるノードを収集
  let value_nodes : Array[ExactNode] = []
  for node in self.nodes {
    if node.needs_value && node.name.has_prefix("--") {
      value_nodes.push(node)
    }
  }
  if value_nodes.is_empty() {
    return
  }
  let eq_node = ExactNode::{
    name: "",
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() {
        return Reject
      }
      let arg = args[pos]
      if not(arg.has_prefix("--")) {
        return Reject
      }
      // "=" を探す
      let eq_pos = match arg.find("=") {
        None => return Reject
        Some(p) => p
      }
      let name = arg.unsafe_substring(start=0, end=eq_pos)
      let value = arg.unsafe_substring(start=eq_pos + 1, end=arg.length())
      // value_nodes から name にマッチするものを探す（最長一致）
      let mut best_consumed = 0
      let mut best_commit : (() -> Unit)? = None
      let mut ambiguous = false
      for node in value_nodes {
        match (node.try_reduce)([name, value], 0) {
          Accept(consumed~, commit~) =>
            if consumed > best_consumed {
              best_consumed = consumed
              best_commit = Some(commit)
              ambiguous = false
            } else if consumed == best_consumed && consumed > 0 {
              ambiguous = true
            }
          Error(e) => return Error(e)
          Reject => ()
        }
      }
      if ambiguous {
        return Error(parse_error("ambiguous argument: " + arg))
      }
      match best_commit {
        Some(commit) => Accept(consumed=1, commit~)
        None => Reject
      }
    },
    reset: fn() {},
  }
  self.nodes.push(eq_node)
}

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

///| `--` セパレータを greedy な ExactNode として構築し self.nodes に追加。
///| `--` を検出したら残りの args を positionals で serial に消費する。
fn Parser::install_separator_node(self : Parser) -> Unit {
  let positionals = self.positionals
  let current_positional = self.current_positional
  let separator_node = ExactNode::{
    name: "--",
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != "--" {
        return Reject
      }
      let mut p = pos + 1
      let commits : Array[() -> Unit] = []
      let mut next_pos_idx = current_positional.val
      while p < args.length() {
        if next_pos_idx >= positionals.length() {
          break
        }
        let (handler, is_rest) = positionals[next_pos_idx]
        match handler(args, p) {
          Accept(consumed~, commit~) => {
            commits.push(commit)
            if not(is_rest) {
              next_pos_idx += 1
            }
            p += consumed
          }
          Reject => break
          Error(e) => return Error(e)
        }
      }
      if p < args.length() {
        return Error(parse_error("unexpected argument: " + args[p]))
      }
      let final_pos_idx = next_pos_idx
      Accept(
        consumed=p - pos,
        commit=fn() {
          for c in commits {
            c()
          }
          current_positional.val = final_pos_idx
        },
      )
    },
    reset: fn() {},
  }
  self.nodes.push(separator_node)
}

///|
fn Parser::parse_raw(
  self : Parser,
  args : Array[String],
) -> ParseResult raise ParseError {
  self.install_eq_split_node()
  self.install_short_combine_node()
  let mut pos = 0
  while pos < args.length() {
    let mut best_consumed = 0
    let mut best_commit : (() -> Unit)? = None
    let mut ambiguous = false
    for node in self.nodes {
      let result = (node.try_reduce)(args, pos)
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
