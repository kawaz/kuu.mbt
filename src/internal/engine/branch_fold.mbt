// branch_fold.mbt — DR-127 §4.2 の枝ローカル効果列 fold。
//
// 裁定 (完全経路カウント、`parse_tree`) の前に、完全枝ごとの効果列を畳んで値空間残余
// (`Binding.value_residual`) の解決可否を判定する。解決不能な枝は落ち、他の解釈が選ばれる
// (DR-127 §4 / DR-029)。落とした枝は Held 等価 — 合成 ParseError (`args_pos` = 当該 binding の
// `at_pos`、無ければ消費位置、DR-127 §4.2 / DR-037) を持って既存の Held 経路 (max_reach /
// push_error / faildef) に乗るため、全枝落ちでも失敗レポートに原因が必ず載る。
//
// 値状態の遷移計算そのものは共有 fold (`src/internal/fold/cell_fold.mbt`) が持つ — 本ファイルに
// あるのは「枝の binding 列を対象セルごとに共有 fold へ流し、Reject 判定素材 (器の有無 /
// old_consulted / Sentinel 種別 / 座の解決失敗) を DR-127 §3 / §4.1 の裁定に写す」ことだけ。
// 同じ判定は resolve 相 (`src/kuu/resolve.mbt` の残余分岐) にも居るが、あちらは単枝の最終防衛線
// (env 供給や後段の乖離検査を持つ) で、こちらは裁定前の枝間選別 — 位相が違う 2 つの消費者が
// 同じ共有 fold を呼ぶ形であり、fold の実装は 1 つである。
//
// 判定の保守姿勢: 対象セルの宣言 (Entity) を特定できない形は落とさない (= resolve 相へ委ねる)。
// 枝を誤って落とすと正しい解釈が消えるのに対し、落とし漏れは単枝観測 (resolve 相 Err) に
// 一致するだけで、意味論は DR-127 §4 の範囲に留まるため。
//
// 既知の残差 (W2-4 findings §3.2 と同根): parse 相は env / config を引けないため、明示の
// `default` 効果が座へ戻す値は宣言 default 止まり。resolve 相のラダー値と容器の中身が違う場合、
// その後の実行時解決 (array 長など) がずれうる。W2-9 (観測面 / 公開 API) の判断と同着。

///|
/// 宣言セル 1 つ分の fold 素材: 対象 Entity と、それを宣言する scope の path (合成 ParseError の
/// `path` に載せる ancestor scope names)。
priv struct SeatDecl {
  entity : Entity
  scope_path : Array[String]
}

///|
fn seat_decl_key(scope : Array[String], name : String) -> String {
  let out = StringBuilder::new()
  for segment in scope {
    out.write_string(segment)
    out.write_char('\u{1f}')
  }
  out.write_char('\u{1f}')
  out.write_string(name)
  out.to_string()
}

///|
fn collect_seat_decls_into(
  sc : Scope,
  path : Array[String],
  defs : Map[String, Node],
  out : Map[String, SeatDecl],
  seen_refs : Array[String],
) -> Unit {
  for entity in sc.entities {
    let address : Array[String] = []
    for segment in path {
      address.push(segment)
    }
    for segment in entity.declaring_path {
      address.push(segment)
    }
    out.set(seat_decl_key(address, entity.name), {
      entity,
      scope_path: path.copy(),
    })
  }
  for g in sc.greedy {
    collect_seat_decl_nodes(g, path, defs, out, seen_refs)
  }
  for p in sc.positional {
    collect_seat_decl_nodes(p, path, defs, out, seen_refs)
  }
}

///|
fn collect_seat_decl_nodes(
  n : Node,
  path : Array[String],
  defs : Map[String, Node],
  out : Map[String, SeatDecl],
  seen_refs : Array[String],
) -> Unit {
  match n {
    ScopeNode(child) =>
      collect_seat_decls_into(child, path, defs, out, seen_refs)
    CommandSatisfied(name, child) => {
      let p2 : Array[String] = []
      for s in path {
        p2.push(s)
      }
      p2.push(name)
      collect_seat_decls_into(child, p2, defs, out, seen_refs)
    }
    Or(alts) =>
      for a in alts {
        collect_seat_decl_nodes(a, path, defs, out, seen_refs)
      }
    LinkTarget(_, _, _, _, _, _, _, _, _, inner) =>
      collect_seat_decl_nodes(inner, path, defs, out, seen_refs)
    Rooted(inner, _) =>
      collect_seat_decl_nodes(inner, path, defs, out, seen_refs)
    Many(inner, _) => collect_seat_decl_nodes(inner, path, defs, out, seen_refs)
    BoundedTail(head, _, _) =>
      collect_seat_decl_nodes(head, path, defs, out, seen_refs)
    Ref(name) =>
      if !str_mem(seen_refs, name) {
        let seen2 : Array[String] = []
        for s in seen_refs {
          seen2.push(s)
        }
        seen2.push(name)
        match ref_head(defs, name) {
          ScopeNode(child) =>
            collect_seat_decls_into(child, path, defs, out, seen2)
          _ => ()
        }
      }
    _ => ()
  }
}

///|
/// 全 scope の宣言セルを (scope path + declaring_path, name) で引ける index にする。
/// 枝ローカル fold が値残余 binding の対象セル宣言 (ValueType / 宣言 default) を引くために使う。
fn collect_seat_decls(
  root : Node,
  defs : Map[String, Node],
) -> Map[String, SeatDecl] {
  let out : Map[String, SeatDecl] = Map([])
  match root {
    ScopeNode(sc) => collect_seat_decls_into(sc, [], defs, out, [])
    _ => ()
  }
  out
}

///|
fn branch_fold_declared_default(entity : Entity) -> Value? {
  match entity.default_values {
    Some(vs) => if vs.length() > 0 { Some(vs[0]) } else { None }
    None => None
  }
}

///|
fn branch_fold_error(
  binding : Binding,
  consumed_pos : Int,
  scope_path : Array[String],
  detail : String,
) -> ParseError {
  {
    element: binding.key,
    args_pos: match binding.at_pos {
      Some(pos) => pos
      None => consumed_pos
    },
    kind: Parse,
    reason: "unresolvable_link_path",
    message: "the link path into '" +
    binding.key +
    "' did not resolve on this reading: " +
    detail,
    path: scope_path.copy(),
  }
}

///|
fn scope_matches(binding : Binding, address : Array[String]) -> Bool {
  if binding.scope.length() != address.length() {
    return false
  }
  for offset in 0..<address.length() {
    if binding.scope[offset] != address[offset] {
      return false
    }
  }
  true
}

///|
/// 完全枝 1 本の効果列 (`strip_levels_to_declaring_scope` 済み) を畳み、値空間残余の解決可否を
/// 判定する (DR-127 §4.2)。解決不能なら合成 ParseError (= この枝を Held 等価で落とす素材) を返す。
///
/// Reject になるのは DR-127 §3 / §4.1 の裁定素材のみ: Sentinel (default / empty) の残余座への
/// 適用、空座 (未 vivify) への `ctx.old` 依存 Value fn、座の解決失敗 (record 宣言外フィールド /
/// map キー不在 / array index の実行時範囲外 / 器の不在)。cell fn の未登録・実行失敗と
/// フィールド type への out 不適合は経路解決の失敗ではないため枝を落とさず、resolve 相の
/// Err / 乖離 Error に委ねる (単枝と多枝で診断の出所を変えない)。
fn branch_fold_reject(
  eff : Array[Binding],
  consumed_pos : Int,
  decls : Map[String, SeatDecl],
  extensions : Registry,
) -> ParseError? {
  // 値残余を持つセルだけ畳む (このセル集合以外の効果は値状態に関与させる必要がない —
  // 値残余の解決素材はそのセル自身の容器の中身だけである)。出現順を保つ。
  let affected : Array[(Array[String], String)] = []
  for b in eff {
    if b.value_residual.length() > 0 {
      let mut seen = false
      for cell in affected {
        if cell.1 == b.key && scope_matches(b, cell.0) {
          seen = true
          break
        }
      }
      if !seen {
        affected.push((b.scope, b.key))
      }
    }
  }
  for cell in affected {
    let (scope, key) = cell
    let decl = match decls.get(seat_decl_key(scope, key)) {
      Some(decl) => decl
      // 宣言を特定できない形は落とさない (ヘッダの保守姿勢)。
      None => continue
    }
    if decl.entity.accum is Some(_) {
      // accumulator セルへの値空間パスは定義時 Unsupported (DR-127 実装計画 §6.1) なので
      // ここへは届かない構造だが、届いても枝選別はしない (resolve 相の管轄へ)。
      continue
    }
    let declared = decl.entity.ty.output_type()
    let declared_default = branch_fold_declared_default(decl.entity)
    let seats = @fold.CellSeats::new()
    for b in eff {
      if b.key != key || !scope_matches(b, scope) {
        continue
      }
      if b.value_residual.length() == 0 {
        // セルそのものへの効果 (parser 産出の丸ごと置換 / unset / 明示 default 等)。
        // `Remove` / `Splice` は merge accumulator 専用 (DR-080 §1) でこの scalar fold には
        // 届かないが、宣言特定に漏れがあっても枝を誤って落とさないよう黙って素通す
        // (resolve 相の防御 abort が最終防衛線)。
        if b.op is (Remove | Splice) {
          continue
        }
        let old = seats.old(key, declared_default)
        let (transition, _) = @fold.fold_seat_effect(b, old, key, extensions)
        // 明示 `default` 効果の落ち先は resolve 相ではラダー (DR-081 §2) だが、parse 相は
        // env / config を引けないので宣言 default 止まり (ヘッダの既知の残差)。
        match @fold.seat_after(transition, declared_default) {
          Some(state) => seats.put(key, state)
          None => ()
        }
        continue
      }
      // 値空間残余の座への効果 — resolve 相の残余分岐と同じ判定素材を枝選別に写す。
      let container_present = seats.value_at(key, []) is Ok(_)
      let old : Value? = if container_present {
        match
          seats.value_at_declared(key, b.value_residual, declared, extensions) {
          Ok(value) => Some(value)
          Err(_) => None
        }
      } else {
        None
      }
      let (transition, old_consulted) = @fold.fold_seat_effect(
        b, old, key, extensions,
      )
      match transition {
        // fn の未登録 / 実行失敗は経路解決の失敗ではない — resolve 相の Err に委ねる。
        @fold.NoChange | @fold.FnMissing(_) | @fold.FnFailed(_) => ()
        // DR-127 §4.1 / DR-131 §7: Sentinel (default / empty) は値残余座で解決失敗。
        @fold.ToDefault | @fold.ToEmpty =>
          return Some(
            branch_fold_error(
              b,
              consumed_pos,
              decl.scope_path,
              "a sentinel operation cannot apply to a value-space seat (DR-127 §4.1)",
            ),
          )
        @fold.ToValue(value) => {
          // DR-127 §3: 空の座 (未 vivify) で ctx.old を読んだ Value fn は戻り値に依らず解決失敗。
          if !container_present && old_consulted {
            return Some(
              branch_fold_error(
                b,
                consumed_pos,
                decl.scope_path,
                "a Value fn that reads ctx.old cannot apply to an empty value-space seat (DR-127 §3)",
              ),
            )
          }
          // 構造終端 (array 要素 / map 値型) の座に座る値は、その構造宣言への適合検査を
          // 通ってから座る (統括裁定 2026-08-02 — DR-126 §4 系の「宣言に適合する値しか座に
          // 座れない」は要素型宣言にも及ぶ)。これらの座は operand を entry 自身の型で読む
          // (registry パース実体が無い) ため、well-formed な読みでも宣言不適合が起こりうる —
          // record フィールド終端の乖離検査 (resolve 相の Error) と違い、ここは枝 Reject。
          if !(value is Null) {
            match
              @fold.residual_terminal_structural(
                declared,
                b.value_residual[:],
                extensions,
              ) {
              Some(structural) => {
                let producer = match b.op {
                  Invoke(invocation) => invocation.name
                  _ => "set"
                }
                match
                  @extension.seat_fn_output_breach(
                    value, structural, producer, extensions,
                  ) {
                  Some((_, detail)) =>
                    return Some(
                      branch_fold_error(
                        b,
                        consumed_pos,
                        decl.scope_path,
                        detail,
                      ),
                    )
                  None => ()
                }
              }
              None => ()
            }
          }
          if value is Null && !container_present {
            // DR-131 §7: `unset` (null 返し) は空座でも成立する — 器は作らず座は論理 null。
            ()
          } else {
            match
              seats.set_at_declared(
                key,
                b.value_residual,
                value,
                declared,
                extensions,
                // DR-127 §3: vivify (器 `{}` の生成) は set (部分書き) 専用の op gate。
                vivify=b.op is Set,
              ) {
              Ok(_) => ()
              Err(fault) =>
                return Some(
                  branch_fold_error(
                    b,
                    consumed_pos,
                    decl.scope_path,
                    @fold.seat_fault_message(fault),
                  ),
                )
            }
          }
        }
      }
    }
  }
  None
}

///|
fn binding_has_value_residual(bs : Array[Binding]) -> Bool {
  for b in bs {
    if b.value_residual.length() > 0 {
      return true
    }
  }
  false
}
