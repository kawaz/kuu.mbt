///|
fn levenshtein(a : String, b : String) -> Int {
  let m = a.length()
  let n = b.length()
  // dp[(i)] は行 i の各列の値を保持する
  let prev : Array[Int] = Array::make(n + 1, 0)
  let curr : Array[Int] = Array::make(n + 1, 0)
  for j = 0; j <= n; j = j + 1 {
    prev[j] = j
  }
  for i = 1; i <= m; i = i + 1 {
    curr[0] = i
    for j = 1; j <= n; j = j + 1 {
      let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 }
      let del = prev[j] + 1
      let ins = curr[j - 1] + 1
      let sub = prev[j - 1] + cost
      let mut min = del
      if ins < min {
        min = ins
      }
      if sub < min {
        min = sub
      }
      curr[j] = min
    }
    for j = 0; j <= n; j = j + 1 {
      prev[j] = curr[j]
    }
  }
  prev[n]
}

///|
fn suggest_typo(
  arg : String,
  registered_names : Map[String, Bool],
) -> String? {
  if not(arg.has_prefix("--")) {
    return None
  }
  let mut best_name : String? = None
  let mut best_dist = 3 // threshold: distance <= 2
  for name, _ in registered_names {
    if not(name.has_prefix("--")) {
      continue
    }
    let d = levenshtein(arg, name)
    if d < best_dist {
      best_dist = d
      best_name = Some(name)
    }
  }
  best_name
}

///|
fn format_unexpected_with_hint(
  arg : String,
  registered_names : Map[String, Bool],
) -> String {
  let msg = "unexpected argument: " + arg
  match suggest_typo(arg, registered_names) {
    Some(suggestion) => msg + " (did you mean " + suggestion + "?)"
    None => msg
  }
}

///|
fn Parser::validate_no_duplicate_names(self : Parser) -> Unit raise ParseError {
  if self.duplicate_errors.length() > 0 {
    raise parse_error(self.duplicate_errors[0])
  }
}

///|
/// self.nodes から --name=value 形式を処理する ExactNode を構築して追加
fn Parser::install_eq_split_node(self : Parser) -> Unit {
  // needs_value=true かつ name が "--" で始まるノードを収集
  let value_nodes : Array[ExactNode] = []
  for node in self.nodes {
    if node.needs_value && node.name.has_prefix("--") {
      value_nodes.push(node)
    }
  }
  // H-1 fix: implicit_value 付きコンビネータの eq_split 用フォールバックノード。
  // make_soft_custom_value_node の "--" ガードをバイパスする "--" ガードなしの value ノード。
  // value_nodes で consumed < 2 の場合のみフォールバックとして試行される。
  let eq_fallback = self.eq_fallback_nodes
  if value_nodes.is_empty() && eq_fallback.is_empty() {
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
            // eq-split は [name, value] (長さ2) で try_reduce を呼ぶ。
            // composite node が implicit (consumed=1) を返した場合、
            // 値が消費されていないので無視すべき。
            if consumed >= 2 && consumed > best_consumed {
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
      // H-1 fix: value_nodes で consumed < 2 の場合、eq_fallback ノードを試行。
      // implicit_value 付きの make_soft_custom_value_node が "--" ガードで
      // Reject した場合のフォールバック（"--" ガードなしの value ノード）。
      if best_consumed < 2 {
        for node in eq_fallback {
          match (node.try_reduce)([name, value], 0) {
            Accept(consumed~, commit~) =>
              if consumed >= 2 && consumed > best_consumed {
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
      }
      if ambiguous {
        return Error(parse_error("ambiguous argument: " + arg))
      }
      match best_commit {
        Some(commit) => Accept(consumed=1, commit~)
        None => Reject
      }
    },
    reset: fn() {  },
  }
  self.nodes.push(eq_node)
}

///|
/// self.nodes から short option ノードを収集し、結合ノードを構築して self.nodes に追加
fn Parser::install_short_combine_node(self : Parser) -> Unit {
  let short_nodes : Array[ExactNode] = []
  for node in self.nodes {
    if node.name.length() == 2 &&
      node.name.has_prefix("-") &&
      not(node.name.has_prefix("--")) {
      short_nodes.push(node)
    }
  }
  if short_nodes.is_empty() {
    return
  }

  let combine_node = ExactNode::{
    name: "",
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() {
        return Reject
      }
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

        // 同一 short 名の全ノードを収集
        let matching : Array[ExactNode] = []
        for sn in short_nodes {
          if sn.name == short_name {
            matching.push(sn)
          }
        }
        if matching.is_empty() {
          return Reject
        }

        let remaining = rest.unsafe_substring(start=ri + 1, end=rest.length())

        if remaining.length() > 0 {
          // remaining がある場合: まず value trial を needs_value=true のノードのみで試す
          let mut value_accepted = false
          let mut try_len = remaining.length()
          while try_len > 0 {
            let try_value = remaining.unsafe_substring(start=0, end=try_len)
            let mut found_accept = false
            let mut found_error : ParseError? = None
            for node in matching {
              // needs_value=false のノード（flag/implicit）は value trial で呼ばない
              // try_reduce の副作用（count の pending 増加等）を防ぐため
              if not(node.needs_value) {
                continue
              }
              match (node.try_reduce)([short_name, try_value], 0) {
                Accept(consumed~, commit~) =>
                  if consumed >= 2 {
                    commits.push(commit)
                    ri = ri + 1 + try_len
                    value_accepted = true
                    found_accept = true
                    break
                  }
                Error(e) => found_error = Some(e)
                _ => ()
              }
            }
            if found_accept {
              break
            }
            if try_len > 1 {
              try_len -= 1
            } else {
              match found_error {
                Some(e) => return Error(e)
                None => () // value trial 全 Reject → flag trial へ
              }
              break
            }
          }
          if not(value_accepted) {
            // value trial 全失敗 → flag trial を全ノードで試す
            let mut flag_accepted = false
            for node in matching {
              match (node.try_reduce)([short_name], 0) {
                Accept(commit~, ..) => {
                  commits.push(commit)
                  ri += 1
                  flag_accepted = true
                  break
                }
                Error(_) | Reject => ()
              }
            }
            if not(flag_accepted) {
              return Reject
            }
          }
        } else {
          // remaining なし: flag trial を全ノードで試す
          let mut flag_accepted = false
          for node in matching {
            match (node.try_reduce)([short_name], 0) {
              Accept(commit~, ..) => {
                commits.push(commit)
                ri += 1
                flag_accepted = true
                break
              }
              Error(_) | Reject => ()
            }
          }
          if not(flag_accepted) {
            // flag trial 全失敗 → 次の外引数で value trial
            if pos + 1 < args.length() {
              let mut ext_accepted = false
              for node in matching {
                match (node.try_reduce)([short_name, args[pos + 1]], 0) {
                  Accept(commit~, ..) => {
                    commits.push(commit)
                    total_consumed = 2
                    ri = rest.length()
                    ext_accepted = true
                    break
                  }
                  Error(e) => return Error(e)
                  Reject => ()
                }
              }
              if not(ext_accepted) {
                return Error(parse_error("missing value for " + short_name))
              }
            } else {
              return Error(parse_error("missing value for " + short_name))
            }
          }
        }
      }

      Accept(consumed=total_consumed, commit=fn() {
        for c in commits {
          c()
        }
      })
    },
    reset: fn() {  },
  }
  self.nodes.push(combine_node)
}

///|
/// `--` を検出したら残りの args を force_unclaimed に収集する。
/// P フェーズで positionals として消費される。
fn Parser::install_separator_node(self : Parser) -> Unit {
  let force_unclaimed = self.force_unclaimed
  let separator_node = ExactNode::{
    name: "--",
    needs_value: false,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      if pos >= args.length() || args[pos] != "--" {
        return Reject
      }
      // -- 以降の全 args を収集（OC フェーズでは消費済みとして扱う）
      let start = pos + 1
      let end = args.length()
      Accept(consumed=end - pos, commit=fn() {
        let mut p = start
        while p < end {
          force_unclaimed.push(args[p])
          p += 1
        }
      })
    },
    reset: fn() {  },
  }
  self.nodes.push(separator_node)
  // 重複検出のため registered_names に登録
  if self.registered_names.contains("--") {
    self.duplicate_errors.push("duplicate option name: --")
  }
  self.registered_names["--"] = true
}

///|
fn Parser::parse_raw(
  self : Parser,
  args : Array[String],
) -> ParseResult raise ParseError {
  if self.parsed.val {
    raise parse_error("Parser::parse can only be called once")
  }
  inject_help_node(self)
  self.validate_no_duplicate_names()
  self.install_eq_split_node()
  self.install_short_combine_node()

  // === OC Phase (Option/Command) ===
  let unclaimed : Array[String] = []
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
      None => {
        // greedy positional があれば OC で消費
        let mut consumed_by_greedy = false
        if self.current_positional.val < self.positionals.length() {
          let idx = self.current_positional.val
          let entry = self.positionals[idx]
          if entry.greedy {
            match (entry.handler)(args, pos) {
              Accept(consumed~, commit~) => {
                commit()
                if not(entry.is_rest) {
                  self.current_positional.val = idx + 1
                }
                pos = pos + consumed
                consumed_by_greedy = true
              }
              Reject => ()
              Error(e) => raise e
            }
          }
        }
        if not(consumed_by_greedy) {
          // unclaimed — P フェーズで処理
          unclaimed.push(args[pos])
          pos += 1
        }
      }
    }
  }

  // === P Phase (Positional) ===
  // force_unclaimed (-- 以降の args) を unclaimed の後ろに結合
  for arg in self.force_unclaimed {
    unclaimed.push(arg)
  }

  let mut upos = 0
  while upos < unclaimed.length() {
    // greedy positional をスキップ（OC で消費済み or 機会を逃した）
    while self.current_positional.val < self.positionals.length() &&
      self.positionals[self.current_positional.val].greedy {
      self.current_positional.val += 1
    }
    if self.current_positional.val >= self.positionals.length() {
      raise parse_error(
        format_unexpected_with_hint(unclaimed[upos], self.registered_names),
      )
    }
    let idx = self.current_positional.val
    let entry = self.positionals[idx]
    match (entry.handler)(unclaimed, upos) {
      Accept(consumed~, commit~) => {
        commit()
        if not(entry.is_rest) {
          self.current_positional.val = idx + 1
        }
        upos += consumed
      }
      Reject => {
        if entry.is_rest {
          // rest が Reject（stop_before トリガー等）→ 次の positional へ
          self.current_positional.val = idx + 1
        } else {
          raise parse_error(
            format_unexpected_with_hint(unclaimed[upos], self.registered_names),
          )
        }
      }
      Error(e) => raise e
    }
  }

  // post hooks: parse 完了後の値変換・遅延バリデーション
  for hook in self.post_hooks {
    hook()
  }
  self.parsed.val = true
  let kind = if self.children.length() > 0 { Map_(self.children) } else { One }
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
        raise ParseError(ParseErrorInfo::{
          ..info,
          help_text: self.generate_help(),
        })
      } else {
        raise ParseError(info)
      }
    Err(e) => raise e
  }
}
