///| PreProcess フックを登録する
pub fn Parser::add_preprocessor(
  self : Parser,
  hook : (Array[String]) -> Array[String]
) -> Unit {
  self.preprocessors.push(hook)
}

// Design rationale: Step 4 では Resolve フックの登録 API のみ提供し、実際の呼び出しは Step 8（did-you-mean サジェスト）で実装する。
// 理由: Resolve フックの型シグネチャは名前解決の介入タイミング（解決前/解決失敗後）によって変わる可能性があり、
// Step 8 の具体的なユースケース（did-you-mean、あいまいマッチ）実装時に確定させる。

///| Resolve フックを登録する
pub fn Parser::add_resolve_hook(
  self : Parser,
  hook : (String, Array[ErasedNode]) -> Array[ErasedNode]?
) -> Unit {
  self.resolve_hooks.push(hook)
}

///| Validate フック（制約）を登録する
pub fn Parser::add_constraint(
  self : Parser,
  check~ : (ValidateCtx) -> Unit raise,
  help_hint~ : String = "",
) -> Unit {
  self.constraints.push(Constraint::{ check, help_hint })
}

///| 環境変数適用用 Finalize フックを登録する（通常の finalizer より先に実行される）
pub fn Parser::add_env_finalizer(
  self : Parser,
  hook : (FinalizeCtx) -> Unit raise
) -> Unit {
  self.env_finalizers.push(hook)
}

///| Finalize フックを登録する
pub fn Parser::add_finalizer(
  self : Parser,
  hook : (FinalizeCtx) -> Unit raise
) -> Unit {
  self.finalizers.push(hook)
}

///| 環境変数ルックアップ関数を設定する
pub fn Parser::set_env_lookup(
  self : Parser,
  lookup : (String) -> String?
) -> Unit {
  self.env_lookup = Some(lookup)
}
