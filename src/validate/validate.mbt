// Design rationale: Step 5 の制約（exclusive, at_least_one, check_required）は
// 登録時にキャプチャした ErasedNode の is_set を参照する。
// これは Opt[T].to_opts() で生成された ErasedNode と同一インスタンスであるため、
// parse() による commit_reduce の結果が正しく反映される。
// サブコマンドスコープ下の制約分離は Step 11（Group）で対応する。

///| 排他オプション制約を登録する。
/// required=false (デフォルト): 最大1つ設定可能。2つ以上で ArgumentConflict エラー。
/// required=true: ちょうど1つ必須。0個で MissingRequired、2つ以上で ArgumentConflict。
pub fn exclusive(
  parser : @core.Parser,
  opts : Array[@core.Opts],
  required~ : Bool = false,
) -> Unit {
  let nodes : Array[@core.ErasedNode] = []
  for o in opts {
    for n in @core.opts_to_erased_nodes(o) {
      nodes.push(n)
    }
  }
  if nodes.length() == 0 {
    return
  } // 空配列は制約登録不要
  parser.add_constraint(
    check=fn(_ctx) raise {
      let set_names : Array[String] = []
      for node in nodes {
        if (node.is_set)() {
          set_names.push(node.meta.name)
        }
      }
      if set_names.length() > 1 {
        let names = set_names.iter().map(fn(n) { "--" + n }).collect()
        let names_str = names.join(", ")
        raise @core.ParseError::Usage(
          @core.ErrorKind::ArgumentConflict,
          "options are mutually exclusive: " + names_str,
          @core.ErrorContext::{ option_name: set_names[0] },
        )
      }
      if required && set_names.length() == 0 {
        let all_names : Array[String] = nodes.iter().map(fn(n) { "--" + n.meta.name }).collect()
        let all_names_str = all_names.join(", ")
        raise @core.ParseError::Usage(
          @core.ErrorKind::MissingRequired,
          "one of the following options is required: " + all_names_str,
          @core.ErrorContext::{ option_name: nodes[0].meta.name },
        )
      }
    },
  )
}

///| 最低1つ必須の制約を登録する。
/// opts のうち1つも設定されていなければ MissingRequired エラー。
pub fn at_least_one(
  parser : @core.Parser,
  opts : Array[@core.Opts],
) -> Unit {
  let nodes : Array[@core.ErasedNode] = []
  for o in opts {
    for n in @core.opts_to_erased_nodes(o) {
      nodes.push(n)
    }
  }
  if nodes.length() == 0 {
    return
  } // 空配列は制約登録不要
  parser.add_constraint(
    check=fn(_ctx) raise {
      let mut count = 0
      for node in nodes {
        if (node.is_set)() {
          count = count + 1
        }
      }
      if count == 0 {
        let all_names : Array[String] = nodes.iter().map(fn(n) { "--" + n.meta.name }).collect()
        let all_names_str = all_names.join(", ")
        raise @core.ParseError::Usage(
          @core.ErrorKind::MissingRequired,
          "at least one of the following options is required: " + all_names_str,
          @core.ErrorContext::{ option_name: nodes[0].meta.name },
        )
      }
    },
  )
}

///| required オプションの未指定チェックを登録する。
/// opts 内の全ノードを走査し、meta.required == true かつ is_set() == false のものがあればエラー。
pub fn check_required(
  parser : @core.Parser,
  opts : @core.Opts,
) -> Unit {
  let nodes = @core.opts_to_erased_nodes(opts)
  if nodes.length() == 0 {
    return
  } // 空配列は制約登録不要（一貫性のため追加）
  parser.add_constraint(
    check=fn(_ctx) raise {
      for node in nodes {
        if node.meta.required && not((node.is_set)()) {
          raise @core.ParseError::Usage(
            @core.ErrorKind::MissingRequired,
            "required option not provided: --" + node.meta.name,
            @core.ErrorContext::{ option_name: node.meta.name },
          )
        }
      }
    },
  )
}
