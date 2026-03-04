///|
pub(all) struct CompletionCandidate {
  value : String
  description : String
} derive(Eq, Show, Debug)

///|
pub(all) enum Shell {
  Bash
  Zsh
  Fish
} derive(Eq, Show, Debug)

///| 文字列中の target を replacement に置換する
fn string_replace(s : String, target : Char, replacement : String) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if ch == target {
      buf.write_string(replacement)
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

///| 文字列から指定文字を除去する
fn string_remove(s : String, target : Char) -> String {
  let buf = StringBuilder::new()
  for ch in s {
    if ch != target {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}

// Design rationale: collect_completions はオプション名/サブコマンド名の補完候補を収集する。
// 値の補完（choices ベース）は文脈依存であるため、collect_value_completions で個別に扱う。

///| ErasedNode のリストから補完候補を収集する
pub fn collect_completions(
  nodes : Array[@core.ErasedNode],
) -> Array[CompletionCandidate] {
  let candidates : Array[CompletionCandidate] = []
  for node in nodes {
    let meta = node.meta
    if meta.visibility == @core.Visibility::Hidden {
      continue
    }
    let desc = meta.help
    match meta.kind {
      Option => {
        candidates.push({ value: "--" + meta.name, description: desc })
        // shorts
        for short in meta.shorts {
          candidates.push({
            value: "-" + short.char.to_string(),
            description: desc,
          })
        }
        // aliases (deprecated は除外)
        for al in meta.aliases {
          if not(al.deprecated) {
            candidates.push({ value: "--" + al.name, description: desc })
          }
        }
        // inversion
        match meta.inversion {
          Some(No) =>
            candidates.push({ value: "--no-" + meta.name, description: desc })
          Some(EnableDisable) => {
            candidates.push({
              value: "--enable-" + meta.name,
              description: desc,
            })
            candidates.push({
              value: "--disable-" + meta.name,
              description: desc,
            })
          }
          Some(Custom(pos, neg)) => {
            candidates.push({
              value: "--" + pos + "-" + meta.name,
              description: desc,
            })
            candidates.push({
              value: "--" + neg + "-" + meta.name,
              description: desc,
            })
          }
          None => ()
        }
      }
      Command => {
        candidates.push({ value: meta.name, description: desc })
        for al in meta.aliases {
          if not(al.deprecated) {
            candidates.push({ value: al.name, description: desc })
          }
        }
      }
      Positional => ()
    }
  }
  candidates
}

///| choices ベースの値補完候補を収集する
pub fn collect_value_completions(
  node : @core.ErasedNode,
) -> Array[CompletionCandidate] {
  let candidates : Array[CompletionCandidate] = []
  for choice in node.meta.choices {
    candidates.push({ value: choice, description: "" })
  }
  candidates
}

///| Zsh 向けに description 内の `:` をエスケープする
fn escape_zsh_description(desc : String) -> String {
  string_replace(desc, ':', "\\:")
}

///| Fish 向けに description 内のタブをスペースに、改行を除去する
fn escape_fish_description(desc : String) -> String {
  let s = string_replace(desc, '\t', " ")
  string_remove(s, '\n')
}

///| 補完候補をシェルスクリプト形式で出力する
pub fn format_completions(
  candidates : Array[CompletionCandidate],
  shell : Shell,
) -> String {
  let lines : Array[String] = []
  for candidate in candidates {
    match shell {
      Bash => lines.push(candidate.value)
      Zsh =>
        lines.push(
          candidate.value + ":" + escape_zsh_description(candidate.description),
        )
      Fish =>
        lines.push(
          candidate.value + "\t" + escape_fish_description(
            candidate.description,
          ),
        )
    }
  }
  lines.join("\n")
}
