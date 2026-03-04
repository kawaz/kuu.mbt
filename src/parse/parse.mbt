// Design rationale: Step 3 MVP では「名前解決→1候補確定→try_reduce」の直列モデルを採用。
// 設計書の「全候補投機実行→consumed最長一致選択」は、consumed > 1 の候補（serial等）が
// 登場する Step 4+ で実装する。現時点では consumed=1 固定のため、名前解決で1つに絞る方式で
// 正しく動作する。

///| マッチ候補の情報
priv struct MatchCandidate {
  node : @core.ErasedNode
  action : @core.ReduceAction
}

///| ロングオプションの処理
fn handle_long(
  name : String,
  eq_value : String?,
  args : Array[String],
  pos : Ref[Int],
  oc_candidates : Array[@core.ErasedNode]
) -> Unit raise {
  // 名前解決で候補を収集
  let exact_matches : Array[MatchCandidate] = []
  let prefix_matches : Array[MatchCandidate] = []
  for node in oc_candidates {
    match resolve_long(name, node.meta) {
      ExactMatch => {
        let action = @core.ReduceAction::Value(eq_value)
        exact_matches.push({ node, action })
      }
      NegateMatch =>
        exact_matches.push({ node, action: @core.ReduceAction::Negate })
      PrefixMatch => {
        let action = @core.ReduceAction::Value(eq_value)
        prefix_matches.push({ node, action })
      }
      NoMatch => ()
    }
  }
  // 候補選択: 完全一致を優先
  let matches = if exact_matches.length() > 0 {
    exact_matches
  } else {
    prefix_matches
  }
  if matches.length() == 0 {
    raise @core.ParseError::Usage(
      @core.ErrorKind::UnknownOption,
      "unknown option: --\{name}",
      @core.ErrorContext::{ option_name: name },
    )
  }
  if matches.length() > 1 {
    raise @core.ParseError::Usage(
      @core.ErrorKind::AmbiguousMatch,
      "ambiguous option: --\{name}",
      @core.ErrorContext::{ option_name: name },
    )
  }
  let candidate = matches[0]
  // Design rationale: 現時点では ResultMap は形式上の引数。Step 11 のグループ機能で実際に活用する。
  let rm = @core.ResultMap::{ id: 0, clone_fns: {} }
  // 値オプションの場合、値を取得する
  let mut action = candidate.action
  match action {
    @core.ReduceAction::Value(None) => {
      // フラグかもしれないし、値を必要とするオプションかもしれない
      // まず Value(None) で try_reduce を試す（フラグ向け）
      let result = (candidate.node.try_reduce)(action, rm)
      match result {
        @core.TryReduceResult::Accept(consumed~, result~) => {
          ignore(consumed)
          (candidate.node.commit_reduce)(result, rm)
          pos.val = pos.val + 1
          return
        }
        @core.TryReduceResult::Reject => {
          // フラグではない → 値オプション。次の引数を値として取得
          if pos.val + 1 >= args.length() {
            raise @core.ParseError::Usage(
              @core.ErrorKind::MissingValue,
              "option --\{name} requires a value",
              @core.ErrorContext::{ option_name: name },
            )
          }
          let next_val = args[pos.val + 1]
          action = @core.ReduceAction::Value(Some(next_val))
          let result2 = (candidate.node.try_reduce)(action, rm)
          match result2 {
            @core.TryReduceResult::Accept(consumed~, result~) => {
              ignore(consumed)
              (candidate.node.commit_reduce)(result, rm)
              pos.val = pos.val + 2 // オプション + 値
              return
            }
            @core.TryReduceResult::Reject =>
              raise @core.ParseError::Usage(
                @core.ErrorKind::InvalidValue,
                "invalid value for --\{name}: \{next_val}",
                @core.ErrorContext::{ option_name: name },
              )
            @core.TryReduceResult::Error(e) => raise e
          }
        }
        @core.TryReduceResult::Error(e) => raise e
      }
    }
    @core.ReduceAction::Value(Some(_)) => {
      // eq形式で値が提供されている
      let result = (candidate.node.try_reduce)(action, rm)
      match result {
        @core.TryReduceResult::Accept(consumed~, result~) => {
          ignore(consumed)
          (candidate.node.commit_reduce)(result, rm)
          pos.val = pos.val + 1
        }
        @core.TryReduceResult::Reject =>
          raise @core.ParseError::Usage(
            @core.ErrorKind::InvalidValue,
            "invalid value for --\{name}",
            @core.ErrorContext::{ option_name: name },
          )
        @core.TryReduceResult::Error(e) => raise e
      }
    }
    @core.ReduceAction::Negate => {
      let result = (candidate.node.try_reduce)(action, rm)
      match result {
        @core.TryReduceResult::Accept(consumed~, result~) => {
          ignore(consumed)
          (candidate.node.commit_reduce)(result, rm)
          pos.val = pos.val + 1
        }
        @core.TryReduceResult::Reject =>
          raise @core.ParseError::Usage(
            @core.ErrorKind::InvalidValue,
            "cannot negate --\{name}",
            @core.ErrorContext::{ option_name: name },
          )
        @core.TryReduceResult::Error(e) => raise e
      }
    }
  }
}

///| ショートオプションの処理
fn handle_short(
  chars : Array[Char],
  oc_candidates : Array[@core.ErasedNode],
  args : Array[String],
  pos : Ref[Int]
) -> Unit raise {
  // Design rationale: 現時点では ResultMap は形式上の引数。Step 11 のグループ機能で実際に活用する。
  let rm = @core.ResultMap::{ id: 0, clone_fns: {} }
  for i, ch in chars {
    // 各文字に対して候補を探す
    let mut found = false
    for node in oc_candidates {
      if resolve_short(ch, node.meta) {
        // 最後の文字は値を取れる可能性がある
        let is_last = i == chars.length() - 1
        // まず Value(None) で試す（フラグ向け）
        let action = @core.ReduceAction::Value(None)
        let result = (node.try_reduce)(action, rm)
        match result {
          @core.TryReduceResult::Accept(consumed~, result~) => {
            ignore(consumed)
            (node.commit_reduce)(result, rm)
            found = true
            break
          }
          @core.TryReduceResult::Reject => {
            // フラグではない → 値オプション
            // Design rationale: 連結ショートオプションで値オプションが途中に出現した場合、
            // 残りの文字列をその値として消費する（POSIX/GNU 準拠: -abfVALUE → a=flag, b=flag, f=VALUE）。
            if is_last {
              // 最後の文字 → 次の引数を値として取得
              if pos.val + 1 < args.length() {
                let next_val = args[pos.val + 1]
                let action2 = @core.ReduceAction::Value(Some(next_val))
                let result2 = (node.try_reduce)(action2, rm)
                match result2 {
                  @core.TryReduceResult::Accept(consumed~, result~) => {
                    ignore(consumed)
                    (node.commit_reduce)(result, rm)
                    pos.val = pos.val + 1 // 次の引数も消費
                    found = true
                    break
                  }
                  @core.TryReduceResult::Reject => ()
                  @core.TryReduceResult::Error(e) => raise e
                }
              } else {
                let ch_str = ch.to_string()
                raise @core.ParseError::Usage(
                  @core.ErrorKind::MissingValue,
                  "missing value for -\{ch_str}",
                  @core.ErrorContext::{ option_name: ch_str },
                )
              }
            } else {
              // 途中の文字 → 残りの文字列を値として消費
              let remaining = StringBuilder::new()
              for j = i + 1; j < chars.length(); j = j + 1 {
                remaining.write_char(chars[j])
              }
              let rest_val = remaining.to_string()
              let action2 = @core.ReduceAction::Value(Some(rest_val))
              let result2 = (node.try_reduce)(action2, rm)
              match result2 {
                @core.TryReduceResult::Accept(consumed~, result~) => {
                  ignore(consumed)
                  (node.commit_reduce)(result, rm)
                  found = true
                  // 残りの文字は全て消費済みなのでループを終了
                  pos.val = pos.val + 1
                  return
                }
                @core.TryReduceResult::Reject => ()
                @core.TryReduceResult::Error(e) => raise e
              }
            }
          }
          @core.TryReduceResult::Error(e) => raise e
        }
      }
    }
    if not(found) {
      let ch_str = ch.to_string()
      raise @core.ParseError::Usage(
        @core.ErrorKind::UnknownOption,
        "unknown option: -\{ch_str}",
        @core.ErrorContext::{ option_name: ch_str },
      )
    }
  }
  pos.val = pos.val + 1
}

///| Positional の処理
fn handle_positional(
  arg : String,
  p_candidates : Array[@core.ErasedNode],
  pos : Ref[Int],
  positional_idx : Ref[Int]
) -> Unit raise {
  // Design rationale: 現時点では ResultMap は形式上の引数。Step 11 のグループ機能で実際に活用する。
  let rm = @core.ResultMap::{ id: 0, clone_fns: {} }
  let action = @core.ReduceAction::Value(Some(arg))
  // positional_idx 番目以降の positional 候補を順に試す
  if positional_idx.val < p_candidates.length() {
    let node = p_candidates[positional_idx.val]
    let result = (node.try_reduce)(action, rm)
    match result {
      @core.TryReduceResult::Accept(consumed~, result~) => {
        ignore(consumed)
        (node.commit_reduce)(result, rm)
        positional_idx.val = positional_idx.val + 1
        pos.val = pos.val + 1
        return
      }
      @core.TryReduceResult::Reject => ()
      @core.TryReduceResult::Error(e) => raise e
    }
  }
  raise @core.ParseError::Usage(
    @core.ErrorKind::UnexpectedArgument,
    "unexpected argument: \{arg}",
    @core.ErrorContext::{ option_name: "" },
  )
}

///| Command の名前またはエイリアスが引数にマッチするか判定
fn command_name_matches(meta : @core.OptMeta, arg : String) -> Bool {
  if meta.name == arg {
    return true
  }
  for a in meta.aliases {
    if a.name == arg {
      return true
    }
  }
  false
}

///| パース実行
pub fn parse(
  parser : @core.Parser,
  args : Array[String],
  opts : @core.Opts
) -> Unit raise {
  // Phase 1: PreProcess — preprocessors を順に実行して args を変換
  let mut processed_args = args
  for hook in parser.preprocessors {
    processed_args = hook(processed_args)
  }
  // Phase 2: Reduce — 既存の消費ループ
  // Design rationale: resolve_hooks は Step 8 で名前解決に組み込む予定。Step 4 では呼び出さない。
  let mut nodes = @core.opts_to_erased_nodes(opts)
  let force_positional : Ref[Bool] = Ref::new(false)
  // Design rationale: p_mode は「Positional を1つ以上消費した後は Command マッチを無効化」するフラグ。
  // 例: `app file.txt cmd` では file.txt 消費後に cmd はサブコマンドではなく Positional として扱う。
  let p_mode : Ref[Bool] = Ref::new(false)
  let pos : Ref[Int] = Ref::new(0)
  let positional_idx : Ref[Int] = Ref::new(0)
  while pos.val < processed_args.length() {
    let arg = processed_args[pos.val]
    // Step 1: "--" セパレータ処理
    if arg == "--" && not(force_positional.val) {
      force_positional.val = true
      pos.val = pos.val + 1
      continue
    }
    // Step 2: 引数の種類判定
    let is_long = arg.has_prefix("--") && arg.length() > 2
    let is_short = arg.has_prefix("-") && arg.length() > 1 && not(is_long)
    // Step 3: OC/P リスト収集
    let oc_candidates : Array[@core.ErasedNode] = []
    let p_candidates : Array[@core.ErasedNode] = []
    for node in nodes {
      match node.meta.kind {
        @core.Kind::Positional => p_candidates.push(node)
        // Command は bare token でのみマッチ。handle_long/handle_short の候補には入れない
        @core.Kind::Command => continue
        @core.Kind::Option => {
          if force_positional.val {
            continue // force_positional 時は Option も除外
          }
          oc_candidates.push(node)
        }
      }
    }
    // Step 4: 投機実行
    if is_long && not(force_positional.val) {
      let (name, eq_value) = decompose_long(arg)
      handle_long(name, eq_value, processed_args, pos, oc_candidates)
    } else if is_short && not(force_positional.val) {
      let chars = decompose_short(arg)
      handle_short(chars, oc_candidates, processed_args, pos)
    } else {
      // bare token: まず Command 候補を名前完全一致でチェック
      let mut command_matched = false
      if not(force_positional.val) && not(p_mode.val) {
        for node in nodes {
          if node.meta.kind == @core.Kind::Command && command_name_matches(node.meta, arg) {
            // Design rationale: 現時点では ResultMap は形式上の引数。Step 11 のグループ機能で実際に活用する。
            let rm = @core.ResultMap::{ id: 0, clone_fns: {} }
            let action = @core.ReduceAction::Value(None)
            let result = (node.try_reduce)(action, rm)
            match result {
              @core.TryReduceResult::Accept(consumed~, result~) => {
                ignore(consumed)
                (node.commit_reduce)(result, rm)
                pos.val = pos.val + 1
                // スコープ遷移: children + global ノードに切り替え
                let child_nodes = (node.children)()
                let new_nodes : Array[@core.ErasedNode] = []
                for cn in child_nodes {
                  new_nodes.push(cn)
                }
                for n in nodes {
                  if n.meta.global {
                    new_nodes.push(n)
                  }
                }
                nodes = new_nodes
                positional_idx.val = 0
                command_matched = true
                break
              }
              @core.TryReduceResult::Reject => ()
              @core.TryReduceResult::Error(e) => raise e
            }
          }
        }
      }
      if not(command_matched) {
        // Positional 処理（非オプション引数 or force_positional）
        handle_positional(arg, p_candidates, pos, positional_idx)
        p_mode.val = true
      }
    }
  }
  // Design rationale: constraint.check が raise した場合、MoonBit の例外伝播により
  // parse() 関数全体が終了するため、後続の Validate/Finalize フックは実行されない。
  // これは「最初のエラーで即座に中断」という設計意図に合致する。

  // Phase 3: Validate — constraints を順に実行
  // Design rationale: 組み込みの制約チェック（exclusive/at_least_one/check_required）は
  // 環境変数適用後に実行する必要があるため Phase 4b（finalizers）に登録される。
  // Phase 3 の constraints はユーザーが add_constraint で登録する構文レベルの制約チェック
  //（env 適用前の状態で判定すべきケース）のために残している。
  // Design rationale: nodes はサブコマンド遷移後の「最終アクティブスコープ」のノード（子 + global）。
  // 親スコープの非 global ノードは含まれない。Validate/Finalize はアクティブスコープに対してのみ動作する。
  let validate_ctx = @core.ValidateCtx::{ nodes }
  for constraint in parser.constraints {
    (constraint.check)(validate_ctx)
  }
  // Phase 4a: EnvFinalize — 環境変数適用フックを実行
  let finalize_ctx = @core.FinalizeCtx::{ nodes }
  for hook in parser.env_finalizers {
    hook(finalize_ctx)
  }
  // Phase 4b: Finalize — 制約チェック等のフックを実行
  for finalizer in parser.finalizers {
    finalizer(finalize_ctx)
  }
}
