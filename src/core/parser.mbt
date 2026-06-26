///|
fn parse_error(
  message : String,
  kind? : ErrorKind = InvalidValue,
  opt_name? : String = "",
  tip? : String = "",
) -> ParseError {
  ParseError(ParseErrorInfo::{ kind, message, error_context: "", opt_name, tip })
}

///|
/// ExactNode の commit (consumed > 0) を committed フラグでラップする。
/// consumed=0 (デフォルトフォールバック) では committed を true にしない。
fn wrap_node_with_set(node : ExactNode, committed : Ref[Bool]) -> ExactNode {
  let orig_try_reduce = node.try_reduce
  let orig_reset = node.reset
  ExactNode::{
    name: node.name,
    needs_value: node.needs_value,
    try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
      match orig_try_reduce(args, pos) {
        Accept(consumed~, commit~) =>
          if consumed > 0 {
            Accept(consumed~, commit=fn() {
              commit()
              committed.val = true
            })
          } else {
            Accept(consumed~, commit~)
          }
        other => other
      }
    },
    reset: fn() {
      orig_reset()
      committed.val = false
    },
  }
}

///|
/// Sets the top-level description shown in `--help` output.
pub fn Parser::set_description(self : Parser, desc : String) -> Unit {
  self.description.val = desc
}

///|
/// 環境変数プレフィックスを設定する。env パラメータ付き opt は
/// `prefix + "_" + env_name` の環境変数を参照するようになる。
/// サブコマンドは親の prefix を自動的に継承し、
/// `PARENT_PREFIX_SUBCMD_NAME` のようにネストする。
pub fn Parser::env_prefix(self : Parser, prefix : String) -> Unit {
  self.env_prefix.val = prefix
}

///|
/// auto_env を有効/無効にする。有効時、env パラメータ未設定かつ Visible の全オプションに
/// name.to_upper() (ハイフン→アンダースコア変換) の環境変数を自動バインドする。
pub fn Parser::auto_env(self : Parser, enabled : Bool) -> Unit {
  self.auto_env_enabled.val = enabled
}

///|
/// env パラメータと auto_env 設定から実効的な env 名を算出する。
/// - env が非空: そのまま返す（明示的指定が優先）
/// - auto_env_enabled かつ Visible: name のハイフンをアンダースコアに変換し大文字化
/// - それ以外: "" を返す
fn Parser::effective_env_name(
  self : Parser,
  env : String,
  name : String,
  visibility : Visibility,
) -> String {
  if env != "" {
    env
  } else if self.auto_env_enabled.val && visibility == Visible {
    name.replace_all(old="-", new="_").to_upper()
  } else {
    ""
  }
}

///|
/// Creates a new CLI argument parser.
///
/// The parser uses a two-phase architecture: OC (Option/Command) phase for
/// named options and subcommands, followed by P (Positional) phase for
/// remaining arguments.
///
/// Parameters:
/// - `dashdash` - If true (default), enables `--` separator support.
///   Arguments after `--` are treated as positional regardless of prefix.
///
/// Returns a `Parser` on which options, subcommands, and constraints can be
/// registered before calling `parse`.
///
/// Example:
/// ```
/// let parser = Parser::new()
/// let name = parser.string(name="name", default="world")
/// parser.parse!(["--name", "MoonBit"])
/// ```
pub fn Parser::new(dashdash? : Bool = true) -> Parser {
  let seq : Ref[Int] = { val: 0 }
  let p : Parser = {
    next_id: fn() -> Int {
      let id = seq.val
      seq.val = id + 1
      id
    },
    nodes: [],
    global_nodes: [],
    positionals: [],
    current_positional: { val: 0 },
    parsed: { val: false },
    children: Map([], capacity=0),
    metas: [],
    description: { val: "" },
    before_post_hooks: [],
    post_hooks: [],
    before_pre_refs: {},
    registered_names: {},
    duplicate_errors: [],
    force_unclaimed: [],
    node_templates: Map([], capacity=0),
    eq_fallback_nodes: [],
    deprecated_usages: [],
    env_applicators: [],
    env_map: { val: {} },
    help_header_text: { val: "" },
    help_footer_text: { val: "" },
    env_prefix: { val: "" },
    auto_env_enabled: { val: false },
  }
  if dashdash {
    p.install_separator_node()
  }
  p
}

///|
/// コンビネータの共通パイプライン: メインノード生成 → committed ラップ → variation展開 → 登録 → OptMeta → Opt[T]
fn[T] Parser::register_option(
  self : Parser,
  name~ : String,
  aliases~ : Array[String],
  shorts~ : String,
  global~ : Bool,
  help~ : String,
  value_name~ : String,
  default_display~ : String,
  env_name~ : String,
  visibility~ : Visibility,
  kind~ : OptKind,
  variations~ : Array[Variation],
  valcell~ : ValCell[T],
  accessor~ : Accessor[T],
  make_main_node~ : (String) -> ExactNode,
  make_node_for_variation~ : (String, Variation) -> ExactNode,
) -> Opt[T] {
  if name == "" {
    self.duplicate_errors.push("option name must not be empty")
  }
  let id = (self.next_id)()
  self.expand_and_register(
    name,
    aliases,
    shorts,
    global,
    make_long_nodes=fn(opt_name) {
      let nodes : Array[ExactNode] = []
      nodes.push(
        wrap_node_with_set(make_main_node(opt_name), valcell.committed),
      )
      expand_variation_nodes(
        opt_name, variations, nodes, make_node_for_variation,
      )
      nodes
    },
    make_short_nodes=fn(short_name) {
      [wrap_node_with_set(make_main_node(short_name), valcell.committed)]
    },
  )
  let shorts_arr : Array[String] = @grapheme.graphemes(shorts)
    .iter()
    .map(fn(sv) { sv.to_owned() })
    .collect()
  let var_names = variations.map(fn(v) {
    let prefix = match v {
      Toggle(p) | True(p) | False(p) | Reset(p) | Unset(p) => p
    }
    "--" + prefix + "-" + name
  })
  self.metas.push(OptMeta::{
    kind,
    name,
    help,
    value_name,
    default_display,
    env_name,
    global,
    shorts: shorts_arr,
    aliases,
    variation_names: var_names,
    visibility,
  })
  self.node_templates[id] = NodeTemplate::{
    make_node: make_main_node,
    is_global: global,
    make_eq_fallback: None,
  }
  {
    id,
    name: "--" + name,
    accessor,
    parsed: self.parsed,
    used: fn() { valcell.committed.val },
  }
}

///|
/// 汎用別名コンビネータ: target の値を共有する新しい ExactNode を name で登録する。
/// name は生文字列（"--" の自動付加なし）。opt / cmd / append 問わず使える。
///
/// node_templates[target.id] に保存されたファクトリ（register_option / cmd で登録）から
/// 新しい ExactNode を生成し、target と Accessor を共有（used のみ独立）。
/// alias 使用時は alias.is_set()=true に加え target.is_set()=true もセットされる。
/// チェーン alias（alias の alias）では Accessor.set_commit 経由で root まで伝搬する。
/// target が global の場合、alias も global_nodes に登録し子パーサに伝搬する。
pub fn[T] Parser::make_alias(
  self : Parser,
  name : String,
  target : Opt[T],
) -> Opt[T] {
  let source = self.node_templates.get(target.id)
  match source {
    None => {
      // target がこの Parser に登録されていない（別 Parser の Opt 等）
      self.duplicate_errors.push(
        "alias target not found: " +
        target.name +
        " (id=" +
        target.id.to_string() +
        ")",
      )
      let id = (self.next_id)()
      {
        id,
        name,
        accessor: target.accessor,
        parsed: target.parsed,
        used: fn() { false },
      }
    }
    Some(src) => {
      if self.registered_names.contains(name) {
        self.duplicate_errors.push("duplicate option name: " + name)
      }
      self.registered_names[name] = true
      let node = (src.make_node)(name)
      let opt_used : Ref[Bool] = { val: false }
      let target_acc = target.accessor
      let orig_try_reduce = node.try_reduce
      let orig_reset = node.reset
      let wrapped = ExactNode::{
        name: node.name,
        needs_value: node.needs_value,
        try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
          match orig_try_reduce(args, pos) {
            Accept(consumed~, commit~) =>
              if consumed > 0 {
                Accept(consumed~, commit=fn() {
                  commit()
                  opt_used.val = true
                  // target の committed を更新。チェーン alias でも
                  // Accessor.set_commit 経由で root まで伝搬する。
                  (target_acc.set_commit)()
                })
              } else {
                Accept(consumed~, commit~)
              }
            other => other
          }
        },
        reset: fn() {
          orig_reset()
          opt_used.val = false
        },
      }
      self.nodes.push(wrapped)
      // target が global なら alias も global — 子パーサに伝搬させる
      if src.is_global {
        self.global_nodes.push(wrapped)
      }
      // implicit_value 付きコンビネータの場合、alias 名でも eq_fallback_nodes に登録
      match src.make_eq_fallback {
        Some(factory) => self.eq_fallback_nodes.push(factory(name))
        None => ()
      }
      let id = (self.next_id)()
      self.node_templates[id] = NodeTemplate::{
        make_node: src.make_node,
        is_global: src.is_global,
        make_eq_fallback: src.make_eq_fallback,
      }
      {
        id,
        name,
        accessor: target.accessor,
        parsed: target.parsed,
        used: fn() { opt_used.val },
      }
    }
  }
}

///|
/// 非推奨の別名を登録するコンビネータ。
/// alias + post_hook で実装。使用されると deprecated_usages に (name, msg) を記録する。
/// 値は target と共有（alias 動作）、is_set は独立。
pub fn[T] Parser::deprecated(
  self : Parser,
  name : String,
  target : Opt[T],
  msg? : String = "",
) -> Opt[T] {
  if name == "" {
    self.duplicate_errors.push("deprecated name must not be empty")
  }
  let alias_opt = self.make_alias(name, target)
  let dep_name = name
  let dep_msg = msg
  self.post_hooks.push(fn() {
    if alias_opt.is_set() {
      self.deprecated_usages.push((dep_name, dep_msg))
    }
  })
  alias_opt
}

///|
/// 値変換コンビネータ: パースパイプラインの各フェーズにフィルタを挿入する。
/// target が set されている場合のみ適用（未設定の default には変換を掛けない）。
///
/// - before_pre: pre 変換前の文字列加工（ノード走査時、各出現ごとに実行）
///   - custom() で作成された opt のみ対応。flag/count/append 等では無視される。
///   - implicit_value パス、eq_split（--opt=val）パス、env パスには適用されない（既知制限）。
/// - after_pre: pre 変換後の値変換（post_hooks フェーズで実行）
/// - before_post: post バリデーション前の値変換（post_hooks フェーズ、after_pre の後に実行）
///   - 現アーキテクチャでは after_pre と同一フェーズで実行される（DR-0061 ペンディング）
/// - after_post: post バリデーション後の値変換（post_hooks フェーズ、最後に実行）
pub fn[T] Parser::adjust(
  self : Parser,
  target : Opt[T],
  before_pre? : FilterChain[String, String],
  after_pre? : FilterChain[T, T],
  before_post? : FilterChain[T, T],
  after_post? : FilterChain[T, T],
) -> Unit {
  // before_pre: ノード走査時の raw string 変換（Ref 経由で pre チェーンに前挿入）
  match before_pre {
    Some(chain) => self.append_before_pre(target.id, chain)
    _ => ()
  }
  // after_pre / before_post → before_post_hooks（post_hooks より先に実行）
  // after_pre と before_post は現アーキテクチャでは同じフェーズで実行される。
  // 将来 per-occurrence 実行が必要になった場合に after_pre を分離する。
  match after_pre {
    Some(chain) => self.add_value_hook(target, chain, early=true)
    _ => ()
  }
  match before_post {
    Some(chain) => self.add_value_hook(target, chain, early=true)
    _ => ()
  }
  // after_post → post_hooks（最後に実行）
  match after_post {
    Some(chain) => self.add_value_hook(target, chain, early=false)
    _ => ()
  }
}

///|
/// adjust 内部: target が set なら chain で値変換する hook を登録。
/// early=true → before_post_hooks、early=false → post_hooks。
fn[T] Parser::add_value_hook(
  self : Parser,
  target : Opt[T],
  chain : FilterChain[T, T],
  early~ : Bool,
) -> Unit {
  let hook = fn() raise ParseError {
    if target.is_set() {
      (target.accessor.set_value)((chain.run)((target.accessor.get)()))
    }
  }
  if early {
    self.before_post_hooks.push(hook)
  } else {
    self.post_hooks.push(hook)
  }
}

///|
/// adjust(before_pre=...) 内部: before_pre_ref に chain を追加。
/// 複数回呼び出し時は FIFO（登録順）で実行される（after_post と同じセマンティクス）。
/// before_pre_ref が未登録（custom 以外の opt）の場合は無視。
fn Parser::append_before_pre(
  self : Parser,
  opt_id : Int,
  chain : FilterChain[String, String],
) -> Unit {
  match self.before_pre_refs.get(opt_id) {
    Some(r) =>
      r.val = match r.val {
        Some(existing) =>
          Some({
            run: fn(s) raise ParseError { (chain.run)((existing.run)(s)) },
          })
        None => Some(chain)
      }
    None => ()
  }
}

///|
/// 値転送コンビネータ: パース後に source の値を target にコピーする。
/// source が set されている場合のみ転送。
/// propagate_set=false（デフォルト）: target の is_set は変更しない。
/// propagate_set=true: target の is_set も true にする（set 経由）。
pub fn[T] Parser::link(
  self : Parser,
  target : Opt[T],
  source~ : Opt[T],
  propagate_set? : Bool = false,
) -> Unit {
  self.post_hooks.push(fn() {
    if source.is_set() {
      if propagate_set {
        (target.accessor.set)((source.accessor.get)())
      } else {
        (target.accessor.set_value)((source.accessor.get)())
      }
    }
  })
}

///|
/// 構造コピーコンビネータ: target と同じパース振る舞いだが独立した値セルを持つ。
/// DR-0037 の「clone = 新 name、新 Ref、フィルタ参照共有」を実現する。
/// alias との違い: alias は値共有（Accessor 共有）、clone は値独立（独自 cell）。
///
/// 制限: clone の alias（`alias(name2, clone_opt)`）は clone の cell ではなく
/// target の cell に書き込む。clone の alias が必要な場合は target に alias してから
/// clone するか、clone のさらなる clone を使うこと。
pub fn[T] Parser::clone(
  self : Parser,
  name : String,
  target : Opt[T],
) -> Opt[T] {
  let source = self.node_templates.get(target.id)
  match source {
    None => {
      self.duplicate_errors.push(
        "clone target not found: " +
        target.name +
        " (id=" +
        target.id.to_string() +
        ")",
      )
      let id = (self.next_id)()
      {
        id,
        name,
        accessor: target.accessor,
        parsed: target.parsed,
        used: fn() { false },
      }
    }
    Some(src) => {
      if self.registered_names.contains(name) {
        self.duplicate_errors.push("duplicate option name: " + name)
      }
      self.registered_names[name] = true
      // 独立した cell と committed。初期値は clone 宣言時点の target 値（= parse 前なので default）。
      let initial_val = (target.accessor.get)()
      let clone_cell : Ref[T] = { val: initial_val }
      let opt_used : Ref[Bool] = { val: false }
      let target_acc = target.accessor
      // clone の cell/committed をリセットする共通関数（ExactNode.reset と Accessor.reset で共用）
      // initial_val を直接使い、target_acc.get() への依存を避ける
      let reset_clone = fn() {
        clone_cell.val = initial_val
        opt_used.val = false
      }
      let node = (src.make_node)(name)
      let orig_try_reduce = node.try_reduce
      let orig_reset = node.reset
      // save/restore パターン: 元のノードの commit は target の cell に書き込むため、
      // commit 前に target を保存し、commit 後に clone の cell にコピーしてから target を復元する。
      // clone_commit_wrap: 任意の try_reduce 結果を save/restore でラップする共通関数
      let clone_commit_wrap = fn(result : TryResult) -> TryResult {
        match result {
          Accept(consumed~, commit~) =>
            if consumed > 0 {
              Accept(consumed~, commit=fn() {
                let saved = (target_acc.get)()
                commit()
                clone_cell.val = (target_acc.get)()
                opt_used.val = true
                (target_acc.set_value)(saved)
              })
            } else {
              Accept(consumed~, commit~)
            }
          other => other
        }
      }
      let wrapped = ExactNode::{
        name: node.name,
        needs_value: node.needs_value,
        try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
          clone_commit_wrap(orig_try_reduce(args, pos))
        },
        reset: fn() {
          orig_reset()
          reset_clone()
        },
      }
      self.nodes.push(wrapped)
      if src.is_global {
        self.global_nodes.push(wrapped)
      }
      // implicit_value 付きコンビネータの場合、eq_fallback も同じ save/restore でラップ
      match src.make_eq_fallback {
        Some(factory) => {
          let eq_node = factory(name)
          let wrapped_eq = ExactNode::{
            name: eq_node.name,
            needs_value: eq_node.needs_value,
            try_reduce: fn(args : Array[String], pos : Int) -> TryResult {
              clone_commit_wrap((eq_node.try_reduce)(args, pos))
            },
            reset: eq_node.reset,
          }
          self.eq_fallback_nodes.push(wrapped_eq)
        }
        None => ()
      }
      let id = (self.next_id)()
      self.node_templates[id] = NodeTemplate::{
        make_node: src.make_node,
        is_global: src.is_global,
        make_eq_fallback: src.make_eq_fallback,
      }
      // clone は ValCell の Accessor を使わずカスタム Accessor を手動構築するため、
      // opt_used が committed 兼 used の役割を担う。set/set_commit は opt_used を直接操作する。
      let clone_acc : Accessor[T] = {
        get: fn() { clone_cell.val },
        set: fn(v) {
          clone_cell.val = v
          opt_used.val = true
        },
        set_value: fn(v) { clone_cell.val = v },
        set_commit: fn() { opt_used.val = true },
        reset: reset_clone,
      }
      {
        id,
        name,
        accessor: clone_acc,
        parsed: target.parsed,
        used: fn() { opt_used.val },
      }
    }
  }
}

///|
/// long オプションのノード展開: --{name} のメインノード + aliases の --{alias} ノードを生成し、
/// 各バッチを check_and_register_names で重複検査・名前登録する。
fn expand_long(
  name : String,
  aliases : Array[String],
  make_long_nodes~ : (String) -> Array[ExactNode],
  check_and_register_names~ : (Array[ExactNode]) -> Unit,
) -> Array[ExactNode] {
  let result : Array[ExactNode] = []
  let main_nodes = make_long_nodes("--" + name)
  check_and_register_names(main_nodes)
  for node in main_nodes {
    result.push(node)
  }
  for alt in aliases {
    let alt_nodes = make_long_nodes("--" + alt)
    check_and_register_names(alt_nodes)
    for node in alt_nodes {
      result.push(node)
    }
  }
  result
}

///|
/// short オプションのノード展開: shorts 文字列を grapheme 分解し、バリデーション後に
/// 各 grapheme を -{c} ノードに変換する。
/// report_error で不正文字（"-", whitespace, NUL）を報告し、name はエラーメッセージ用。
fn expand_short(
  name : String,
  shorts : String,
  make_short_nodes~ : (String) -> Array[ExactNode],
  check_and_register_names~ : (Array[ExactNode]) -> Unit,
  report_error~ : (String) -> Unit,
) -> Array[ExactNode] {
  let result : Array[ExactNode] = []
  let shorts_g = @grapheme.graphemes(shorts)
  for i = 0; i < shorts_g.length(); i = i + 1 {
    let g = shorts_g[i].to_owned()
    if g == "-" {
      report_error("invalid short option character '-' in option --" + name)
    } else if g == " " || g == "\t" || g == "\n" || g == "\r" {
      report_error(
        "invalid short option character (whitespace) in option --" + name,
      )
    } else if g == "\u0000" {
      report_error("invalid short option character (NUL) in option --" + name)
    }
  }
  for i = 0; i < shorts_g.length(); i = i + 1 {
    let short_nodes = make_short_nodes("-" + shorts_g[i].to_owned())
    check_and_register_names(short_nodes)
    for node in short_nodes {
      result.push(node)
    }
  }
  result
}

///|
/// コンビネータの共通パターン: メイン名 → aliases → short の展開 + ノード登録
fn Parser::expand_and_register(
  self : Parser,
  name : String,
  aliases : Array[String],
  shorts : String,
  global : Bool,
  // long option 名（"--verbose" 等）に対して全ノード（メイン + variation）を返す
  make_long_nodes~ : (String) -> Array[ExactNode],
  // short option 名（"-v" 等）に対してメインノードのみ返す（variation なし）
  make_short_nodes~ : (String) -> Array[ExactNode],
) -> Unit {
  fn register(nodes : Array[ExactNode]) {
    for node in nodes {
      self.nodes.push(node)
      if global {
        self.global_nodes.push(node)
      }
    }
  }

  fn check_and_register_names(nodes : Array[ExactNode]) {
    // Check against previously registered names (cross-combinator duplicates)
    for node in nodes {
      if node.name != "" && self.registered_names.contains(node.name) {
        self.duplicate_errors.push("duplicate option name: " + node.name)
        break // report once per batch
      }
    }
    // Register all names from this batch
    for node in nodes {
      if node.name != "" {
        self.registered_names[node.name] = true
      }
    }
  }

  let long_nodes = expand_long(
    name,
    aliases,
    make_long_nodes~,
    check_and_register_names~,
  )
  register(long_nodes)
  let short_nodes = expand_short(
    name,
    shorts,
    make_short_nodes~,
    check_and_register_names~,
    report_error=fn(msg) { self.duplicate_errors.push(msg) },
  )
  register(short_nodes)
}
