// Design rationale: apply_env は env_finalizers に登録し、check_required 等の制約チェックは
// finalizers に登録する。parse.mbt は env_finalizers → finalizers の順で実行するため、
// ユーザーの登録順に関わらず env 適用が制約チェックより先に行われることが保証される。

// Design rationale: ValueSource トラッキング（Initial/Default/Environment/CommandLine の記録）は
// ErasedNode への追加フィールドが必要で影響範囲が広いため、Step 11（拡張コンビネータ + Group）で
// ResultMap 活用と合わせて実装する。Step 6 では is_set による「設定済み/未設定」の2値判定で
// コマンドライン優先を実現している。

///| 環境変数を適用する Finalize フックを登録する。
///  各ノードの meta.env / auto_env をチェックし、未設定ならば環境変数から値を適用する。
pub fn apply_env(
  parser : @core.Parser,
  opts : @core.Opts,
  env_prefix~ : String = ""
) -> Unit {
  // Design rationale: apply_env は FinalizeCtx.nodes（アクティブスコープ）ではなく、
  // 登録時に渡された opts を全走査する。環境変数はグローバルな設定メカニズムであり、
  // サブコマンドのスコープに限定せず全オプションに適用すべきだからである。
  // スコープを考慮した env 適用は Step 11 で ResultMap と合わせて検討する。
  let nodes = @core.opts_to_erased_nodes(opts)
  parser.add_env_finalizer(fn(_ctx) raise {
    let lookup = match parser.env_lookup {
      Some(f) => f
      None => return
    }
    let rm = @core.ResultMap::{ id: 0, clone_fns: {} }
    for node in nodes {
      // 環境変数適用は Option（フラグ含む）のみ。Positional/Command には適用しない。
      if node.meta.kind != @core.Kind::Option {
        continue
      }
      if (node.is_set)() {
        continue
      }
      // 環境変数名の決定: env > auto_env > env_prefix
      let env_name : String? = match node.meta.env {
        Some(name) => Some(name) // 個別 env は完全オーバーライド
        None => {
          let base_name : String? = match node.meta.auto_env {
            Some(true) => Some(node.meta.name.to_upper())
            Some(false) => None // 明示的に無効化
            None =>
              // auto_env 未設定で env_prefix があれば自動適用
              if env_prefix != "" {
                Some(node.meta.name.to_upper())
              } else {
                None
              }
          }
          match base_name {
            Some(name) =>
              if env_prefix != "" {
                Some(env_prefix + "_" + name)
              } else {
                Some(name)
              }
            None => None
          }
        }
      }
      match env_name {
        None => continue
        Some(name) => {
          let val = lookup(name)
          match val {
            None => continue
            Some(v) => {
              let action = @core.ReduceAction::Value(Some(v))
              let result = (node.try_reduce)(action, rm)
              match result {
                @core.TryReduceResult::Accept(result~, ..) =>
                  (node.commit_reduce)(result, rm)
                // Design rationale: 現在の全コンビネータ（int/string/flag）は Value(Some(v)) に対して
                // Accept または Error(raise) を返し、Reject は到達しない。将来のカスタム reducer で
                // Reject が返る場合は「このノードは当該値を処理対象外」の意味であり、スキップが正しい。
                @core.TryReduceResult::Reject => ()
                @core.TryReduceResult::Error(e) => raise e // エラーを伝播
              }
            }
          }
        }
      }
    }
  })
}
