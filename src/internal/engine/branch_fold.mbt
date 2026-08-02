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
// 明示 `default` 効果の落ち先 (DR-081 §2 の書き換え済み default) は `ladder` closure が供給する
// (front_door が parse の値源 provider で実装、DR-114 §6.1 の一本化)。ladder 未供給の呼び出し
// (engine 直呼び) は宣言 default 止まり — その形では record の old が resolve 相と一致せず
// 消費されないため、fold は枝選別のためだけに走る従来経路になる。

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
  out : Map[String, Array[SeatDecl]],
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
    let key = seat_decl_key(address, entity.name)
    let decl : SeatDecl = { entity, scope_path: path.copy() }
    // 同一 key は複数候補として全部保持する (後勝ち上書き禁止) — duplicate raw command path
    // (DR-120 合法) で同名 scope が 2 本立つと、同じ address に別宣言の entity が並びうる。
    // 候補が一意に定まるかは lookup 側 (`seat_decl_lookup`) が判定する。
    match out.get(key) {
      Some(candidates) => candidates.push(decl)
      None => out.set(key, [decl])
    }
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
  out : Map[String, Array[SeatDecl]],
  seen_refs : Array[String],
) -> Unit {
  match n {
    ScopeNode(child) =>
      collect_seat_decls_into(child, path, defs, out, seen_refs)
    CommandSatisfied(name, _, child) => {
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
) -> Map[String, Array[SeatDecl]] {
  let out : Map[String, Array[SeatDecl]] = Map([])
  match root {
    ScopeNode(sc) => collect_seat_decls_into(sc, [], defs, out, [])
    _ => ()
  }
  out
}

///|
/// key に対する宣言候補を 1 つに絞る。fold が判定に使う面 (宣言 ValueType / 宣言 default /
/// accumulator か) で全候補が一致するときだけ Some — 食い違う候補が並ぶ key (同名 scope 2 本が
/// 別宣言を持つ形) は None を返し、呼び手は保守的スキップ (fold 対象外 = resolve 相へ委譲) に
/// 倒す。枝の同一性 (どの scope 本体の読みか) まで運べば絞れるが、binding にその素材が無い。
fn seat_decl_lookup(
  decls : Map[String, Array[SeatDecl]],
  key : String,
) -> SeatDecl? {
  match decls.get(key) {
    None => None
    Some(candidates) => {
      guard candidates.length() > 0 else { return None }
      let head = candidates[0]
      for offset in 1..<candidates.length() {
        let other = candidates[offset]
        if other.entity.ty.output_type() != head.entity.ty.output_type() ||
          other.entity.default_values != head.entity.default_values ||
          (other.entity.accum is Some(_)) != (head.entity.accum is Some(_)) {
          return None
        }
      }
      Some(head)
    }
  }
}

///|
fn branch_fold_declared_default(entity : Entity) -> Value? {
  match entity.default_values {
    Some(vs) => if vs.length() > 0 { Some(vs[0]) } else { None }
    None => None
  }
}

///|
/// fold が枝を落とすときの合成 ParseError。`args_pos` = 当該 binding の `at_pos`、無ければ
/// 消費位置 (DR-127 §4.2 / DR-037)。`reason` / `message` は失敗位相ごとに呼び手が渡す —
/// Reject 位相は `unresolvable_link_path`、Error 位相 (fn 失敗 / out 乖離) は resolve 相が
/// 出すのと同じ語彙 (単枝と多枝で診断の出所を変えない)。
fn branch_fold_failure(
  binding : Binding,
  consumed_pos : Int,
  scope_path : Array[String],
  reason : String,
  message : String,
) -> ParseError {
  {
    element: binding.key,
    args_pos: match binding.at_pos {
      Some(pos) => pos
      None => consumed_pos
    },
    kind: Parse,
    reason,
    message,
    path: scope_path.copy(),
  }
}

///|
fn branch_fold_error(
  binding : Binding,
  consumed_pos : Int,
  scope_path : Array[String],
  detail : String,
) -> ParseError {
  branch_fold_failure(
    binding,
    consumed_pos,
    scope_path,
    "unresolvable_link_path",
    "the link path into '" +
    binding.key +
    "' did not resolve on this reading: " +
    detail,
  )
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
/// 完全枝 1 本の効果列 (`strip_levels_to_declaring_scope` 済み) を畳み、fold の実行で**判明した
/// 失敗**を持つ枝を裁定前に除外する素材 (合成 ParseError) を返す (DR-127 §4.2 / DR-037 —
/// 判明済みの失敗を持つ読みは完全経路に数えない)。失敗は 2 位相で、どちらも枝は落ちるが
/// 合成 ParseError の語彙が違う:
///
/// | 位相 | 素材 | reason |
/// |---|---|---|
/// | Reject (経路解決の失敗、DR-127 §3/§4.1/§4.2) | Sentinel の残余座適用 / 空座への ctx.old 依存 fn / 座の解決失敗 (SeatFault) / 構造終端 (array 要素・map 値型) の宣言不適合 | `unresolvable_link_path` |
/// | Error (実行して判明した失敗、resolve 相と同語彙) | cell fn 未登録 (`unknown-vocab`) / fn 実行失敗 (fn の reason) / record フィールド終端の out 乖離 (DR-126 §4 の breach 語彙) | resolve 相と同一 |
///
/// 判定対象の効果は Set の operand と Value fn の戻り値の両方 (`b.op` に依らず、座へ座る
/// 非 null 値すべて — DR-127 §3.2「保証は値を運んだ経路で変わらない」)。fold が実行しない
/// もの (畳んでいないセルの fn 等) はここでは判明しないので落とさず、resolve 相が持ち主。
///
/// `ledger` (DR-114 §6.1 の一本化): 枝内で実行した発火の結果を FiringRecord として記録する。
/// 枝が落ちれば ledger は枝ごと捨てられ、勝ち枝の ledger は裁定後にそのまま配達される —
/// 値残余セルの fn を勝ち枝で**再実行しない**ための引き継ぎ席。`ladder` は明示 `default`
/// 効果の落ち先 (DR-081 §2 の書き換え済み default)。未供給 (None) は従来どおり宣言 default
/// 止まり (W2-4 findings §3.2 の既知残差) で、供給時は resolve 相と同じ full ladder に揃う。
fn branch_fold_reject(
  eff : Array[Binding],
  consumed_pos : Int,
  decls : Map[String, Array[SeatDecl]],
  extensions : Registry,
  ladder : ((Entity, Array[String], Array[Binding]) -> Value?)?,
  ledger : @fold.FiringLedger?,
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
    let decl = match seat_decl_lookup(decls, seat_decl_key(scope, key)) {
      Some(decl) => decl
      // 宣言を特定できない / 候補が食い違う形は落とさない (保守的スキップ = resolve 相へ委譲)。
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
        let (transition, old_consulted) = @fold.fold_seat_effect(
          b, old, key, extensions,
        )
        // record 対象は `records_firing` (= Invoke) のみ — 消費者の出現順カウントと揃える。
        match ledger {
          Some(records) if b.op is Invoke(_) =>
            records.push(b.scope, b.key, {
              transition,
              old_used: old,
              old_consulted,
              resolved_residual: None,
            })
          _ => ()
        }
        // fold が実行して判明した fn の失敗は Error 位相の除外素材 (resolve 相と同じ語彙)。
        match transition {
          @fold.FnMissing(name) =>
            return Some(
              branch_fold_failure(
                b,
                consumed_pos,
                decl.scope_path,
                "unknown-vocab",
                "cell fn '" + name + "' is not registered",
              ),
            )
          @fold.FnFailed({ reason, message, .. }) =>
            return Some(
              branch_fold_failure(
                b,
                consumed_pos,
                decl.scope_path,
                reason,
                message,
              ),
            )
          _ => ()
        }
        // 明示 `default` 効果の落ち先: `ladder` 供給時は resolve 相と同じ full ladder
        // (DR-081 §2 の書き換え済み default)、未供給は従来どおり宣言 default 止まり
        // (ヘッダの既知の残差)。
        let default_fall : Value? = if transition is @fold.ToDefault {
          match ladder {
            Some(query) => query(decl.entity, decl.scope_path, eff)
            None => declared_default
          }
        } else {
          declared_default
        }
        match @fold.seat_after(transition, default_fall) {
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
      match ledger {
        Some(records) =>
          records.push(b.scope, b.key, {
            transition,
            old_used: old,
            old_consulted,
            // 発火時点 (書き込み前) の座の現在長で解決した観測アドレス片 (DR-127 §6)。
            resolved_residual: seats.resolved_residual(key, b.value_residual),
          })
        None => ()
      }
      match transition {
        @fold.NoChange => ()
        // fold が実行して判明した fn の失敗は Error 位相の除外素材 (resolve 相と同じ語彙)。
        @fold.FnMissing(name) =>
          return Some(
            branch_fold_failure(
              b,
              consumed_pos,
              decl.scope_path,
              "unknown-vocab",
              "cell fn '" + name + "' is not registered",
            ),
          )
        @fold.FnFailed({ reason, message, .. }) =>
          return Some(
            branch_fold_failure(
              b,
              consumed_pos,
              decl.scope_path,
              reason,
              message,
            ),
          )
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
            let producer = match b.op {
              Invoke(invocation) => invocation.name
              _ => "set"
            }
            match
              @fold.residual_terminal_structural(
                declared,
                b.value_residual[:],
                extensions,
              ) {
              Some(structural) =>
                // 構造終端 (array 要素 / map 値型) の宣言不適合 = Reject 位相。
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
              None =>
                // record フィールド終端の out 乖離 = Error 位相 (DR-126 §4 の breach 語彙を
                // そのまま運ぶ — resolve 相の同検査と同一観測)。
                match
                  @fold.residual_terminal_out(
                    declared,
                    b.value_residual,
                    extensions,
                  ) {
                  Some(out) =>
                    match
                      @extension.seat_fn_output_breach(
                        value, out, producer, extensions,
                      ) {
                      Some((reason, message)) =>
                        return Some(
                          branch_fold_failure(
                            b,
                            consumed_pos,
                            decl.scope_path,
                            reason,
                            message,
                          ),
                        )
                      None => ()
                    }
                  None => ()
                }
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

///|
fn binding_has_plain_invoke(bs : Array[Binding]) -> Bool {
  for b in bs {
    if b.op is Invoke(_) && b.value_residual.length() == 0 {
      return true
    }
  }
  false
}

///|
/// 裁定後の 1 回の fold (DR-114 §6.1 の一本化): 値残余 binding を持たないセルの Invoke 発火を
/// 勝ち経路上で 1 回実行し、FiringRecord として記録する。値残余セル分は枝ローカル fold
/// (`branch_fold_reject`) の枝内実行結果が ledger ごと引き継がれるので対象外。枝選別に参加しない
/// 発火を全枝で実行するのは DR-114 が禁じる方向の悪化なので、per-branch には広げず勝ち経路
/// 確定後に置く (W2-9 findings「実行一本化の設計」2)。
///
/// 裁定は済んでいるので失敗 (fn 未登録 / 実行失敗) でも経路は落とさず record に残す —
/// resolve 相の消費者が従来と同じ Err を合成し、effects 射影は従来と同じ生 `invoke` を観測する。
/// 保守的スキップ (宣言を特定できない / 候補が食い違う / accum セル) は record を作らない =
/// resolve 相の残余分岐が従来どおり実行する (最終防衛線)。
fn branch_fold_plain_records(
  eff : Array[Binding],
  decls : Map[String, Array[SeatDecl]],
  extensions : Registry,
  ladder : ((Entity, Array[String], Array[Binding]) -> Value?)?,
  ledger : @fold.FiringLedger,
) -> Unit {
  // 値残余 binding を 1 件でも持つセルは枝ローカル fold の領分 (record は引き継ぎ済み)。
  let residual_cells : Array[(Array[String], String)] = []
  for b in eff {
    if b.value_residual.length() > 0 {
      let mut seen = false
      for cell in residual_cells {
        if cell.1 == b.key && scope_matches(b, cell.0) {
          seen = true
          break
        }
      }
      if !seen {
        residual_cells.push((b.scope, b.key))
      }
    }
  }
  let plain_cells : Array[(Array[String], String)] = []
  for b in eff {
    if b.op is Invoke(_) && b.value_residual.length() == 0 {
      let mut excluded = false
      for cell in residual_cells {
        if cell.1 == b.key && scope_matches(b, cell.0) {
          excluded = true
          break
        }
      }
      if excluded {
        continue
      }
      let mut seen = false
      for cell in plain_cells {
        if cell.1 == b.key && scope_matches(b, cell.0) {
          seen = true
          break
        }
      }
      if !seen {
        plain_cells.push((b.scope, b.key))
      }
    }
  }
  for cell in plain_cells {
    let (scope, key) = cell
    let decl = match seat_decl_lookup(decls, seat_decl_key(scope, key)) {
      Some(decl) => decl
      None => continue
    }
    if decl.entity.accum is Some(_) {
      continue
    }
    let declared_default = branch_fold_declared_default(decl.entity)
    let seats = @fold.CellSeats::new()
    for b in eff {
      if b.key != key || !scope_matches(b, scope) {
        continue
      }
      if b.op is (Remove | Splice) {
        continue
      }
      let old = seats.old(key, declared_default)
      let (transition, old_consulted) = @fold.fold_seat_effect(
        b, old, key, extensions,
      )
      if b.op is Invoke(_) {
        ledger.push(b.scope, b.key, {
          transition,
          old_used: old,
          old_consulted,
          resolved_residual: None,
        })
      }
      // 明示 `default` 効果の落ち先は `branch_fold_reject` と同じ ladder 規則。
      let default_fall : Value? = if transition is @fold.ToDefault {
        match ladder {
          Some(query) => query(decl.entity, decl.scope_path, eff)
          None => declared_default
        }
      } else {
        declared_default
      }
      match @fold.seat_after(transition, default_fall) {
        Some(state) => seats.put(key, state)
        None => ()
      }
    }
  }
}
