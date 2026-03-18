///|
fn parse_error(
  message : String,
  kind~ : ErrorKind = InvalidValue,
  opt_name~ : String = "",
) -> ParseError {
  ParseError(ParseErrorInfo::{ kind, message, help_text: "", opt_name })
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
pub fn Parser::set_description(self : Parser, desc : String) -> Unit {
  self.description.val = desc
}

///|
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
    children: Map::new(),
    metas: [],
    description: { val: "" },
    post_hooks: [],
    registered_names: {},
    duplicate_errors: [],
    force_unclaimed: [],
    node_templates: Map::new(),
    eq_fallback_nodes: [],
    deprecated_usages: [],
    env_applicators: [],
    env_map: { val: {} },
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
  hidden~ : Bool,
  kind~ : OptKind,
  variations~ : Array[Variation],
  valcell~ : ValCell[T],
  make_main_node~ : (String) -> ExactNode,
  make_node_for_variation~ : (String, Variation) -> ExactNode,
) -> Opt[T] {
  let id = (self.next_id)()
  self.expand_and_register(
    name, aliases, shorts, global,
    make_long_nodes=fn(opt_name) {
      let nodes : Array[ExactNode] = []
      nodes.push(wrap_node_with_set(make_main_node(opt_name), valcell.committed))
      expand_variation_nodes(opt_name, variations, nodes, make_node_for_variation)
      nodes
    },
    make_short_nodes=fn(short_name) {
      [wrap_node_with_set(make_main_node(short_name), valcell.committed)]
    },
  )
  let shorts_arr : Array[String] = @unicodegrapheme.graphemes(shorts).iter().map(fn(sv) { sv.to_string() }).collect()
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
    hidden,
  })
  self.node_templates[id] = NodeTemplate::{
    make_node: make_main_node,
    is_global: global,
    make_eq_fallback: None,
  }
  { id, name: "--" + name, accessor: valcell.accessor(), parsed: self.parsed, used: fn() { valcell.committed.val } }
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
        "alias target not found: " + target.name +
        " (id=" +
        target.id.to_string() +
        ")",
      )
      let id = (self.next_id)()
      { id, name, accessor: target.accessor, parsed: target.parsed, used: fn() { false } }
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
      { id, name, accessor: target.accessor, parsed: target.parsed, used: fn() { opt_used.val } }
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
  msg~ : String = "",
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
/// 値変換コンビネータ: パース後に target の値を FilterChain で変換する。
/// target が set されている場合のみ適用（未設定の default には変換を掛けない）。
pub fn[T] Parser::adjust(
  self : Parser,
  target : Opt[T],
  after_post~ : FilterChain[T, T],
) -> Unit {
  self.post_hooks.push(fn() raise ParseError {
    if target.is_set() {
      (target.accessor.set_value)((after_post.run)((target.accessor.get)()))
    }
  })
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
  propagate_set~ : Bool = false,
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
/// DR-037 の「clone = 新 name、新 Ref、フィルタ参照共有」を実現する。
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
        "clone target not found: " + target.name +
        " (id=" +
        target.id.to_string() +
        ")",
      )
      let id = (self.next_id)()
      { id, name, accessor: target.accessor, parsed: target.parsed, used: fn() { false } }
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
      let clone_commit_wrap = fn(
        result : TryResult,
      ) -> TryResult {
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
      { id, name, accessor: clone_acc, parsed: target.parsed, used: fn() { opt_used.val } }
    }
  }
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
        self.duplicate_errors.push(
          "duplicate option name: " + node.name,
        )
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

  // Validate shorts characters (grapheme cluster units)
  let shorts_g = @unicodegrapheme.graphemes(shorts)
  for i = 0; i < shorts_g.length(); i = i + 1 {
    let g = shorts_g[i].to_string()
    if g == "-" {
      self.duplicate_errors.push(
        "invalid short option character '-' in option --" + name,
      )
    } else if g == " " || g == "\t" || g == "\n" || g == "\r" {
      self.duplicate_errors.push(
        "invalid short option character (whitespace) in option --" + name,
      )
    } else if g == "\u0000" {
      self.duplicate_errors.push(
        "invalid short option character (NUL) in option --" + name,
      )
    }
  }
  let long_nodes = make_long_nodes("--" + name)
  check_and_register_names(long_nodes)
  register(long_nodes)
  for alt in aliases {
    let alt_nodes = make_long_nodes("--" + alt)
    check_and_register_names(alt_nodes)
    register(alt_nodes)
  }
  for i = 0; i < shorts_g.length(); i = i + 1 {
    let short_nodes = make_short_nodes("-" + shorts_g[i].to_string())
    check_and_register_names(short_nodes)
    register(short_nodes)
  }
}
