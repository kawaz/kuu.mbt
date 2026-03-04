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

///| Finalize フックを登録する
pub fn Parser::add_finalizer(
  self : Parser,
  hook : (FinalizeCtx) -> Unit raise
) -> Unit {
  self.finalizers.push(hook)
}
