// cell_fold.mbt — 座 (cell) の値状態と、効果 1 件を座へ畳む共有 fold。
//
// 効果列から「今この座に何が座っているか」を求める計算は、DR-045 の効果語彙・DR-114 §7 の
// `ctx.old` 規範・DR-131 §7 の Sentinel 語彙が一体で決める 1 つの意味論である。従来それを
// `front_door.mbt` の effects 射影 (`projected_effect` の `current` map) と `resolve.mbt` の
// CLI seat 解決 (`resolve_entity_raw` の scalar fold) が独立に実装しており、複合値と vivify
// (DR-127 §3) が入ると両者の答えがずれる。conformance は effects と result の両方を pin して
// いるので、ずれは「両方が同時に間違っている」場合に検出できない — だから 3 つ目の fold
// (DR-127 §4.2 の枝ローカル効果列) を足す前に、ここへ 1 本化する。
//
// 本モジュールが持つのは **値状態** だけである。効果の出力表現 (`OutputEffect` の op/operand) と
// 解決済み binding の carrier 構築は、観測面と値源ラダーという別々の責務なので各呼び手に残る。

///|
/// 座の値状態。DR-114 §7 の `ctx.old()`「発火直前の cell 値を返し、値が無ければ absent」を
/// この 3 値から導く。値が座っていない状態が 2 つあるのは old の落ち先が違うため:
///
/// - `Opened` — 席が開いた状態 (`unset` = null Value fn、DR-131 §2b)。値源ラダーが下段まで
///   開くので、old は宣言 default へ落ちる (fixture `multiple-parse/unset-opens-ladder-to-declared-default.json`)
/// - `Emptied` — committed な空 (`empty` Sentinel、DR-131 §7)。`empty` の target は array / map /
///   record に限られる (REFERENCE の `cell_fns` 表、scalar 等は definition-error `invalid-range`)
///   ので、本来この座の old は**型別の空値** (`[]` / `{}`) である。ここが absent を返すのは
///   **その空値を供給する consumer がまだ居ない**ため — collection セルの値解決は accumulator
///   resident (`resolve_cli`) が持ち本 fold を通らず、accumulator セルへ `ctx.old` を読む fn を
///   置く定義 (`multiple` × `update`) は `parse_definition` 時点の definition-error である。
///   consumer が入る段で型別の空値へ差し替えること
priv enum SeatState {
  Opened
  Emptied
  Seated(@abi.Value)
}

///|
/// 効果 1 件が座の値状態へ与える遷移。DR-045 の op 語彙を「値状態の言葉」へ写したもので、
/// `Invoke` は cell fn を呼んだ **後** の分類になる (呼び出し自体が本 fold の責務)。
priv enum SeatTransition {
  /// 値が座る。`ToValue(Null)` は「席を開ける」= uncommitted (DR-045 の `is_committed` が
  /// `Set` かつ値 null を committed としないのと同じ規則)。
  ToValue(@abi.Value)
  /// default 席の現在値へ戻す (committed)。実際にどの値かは呼び手が持つラダー
  /// (`resolve_ladder_below_cli` / 宣言 default) が決める — DR-081 §2。
  ToDefault
  /// committed な空へ (DR-131 §7)。
  ToEmpty
  /// 値状態を変えない (merge accumulator の `splice` piece 等)。
  NoChange
  /// cell fn 名が registry に無い。
  FnMissing(String)
  /// cell fn の `observes` 解決または本体が失敗した。
  FnFailed(@extension.FnReason)
}

///|
/// 効果 1 件を座の値状態遷移へ畳む。`old` は DR-114 §7 の `ctx.old`、`target` は effect mode の
/// 対象セル名。cell fn 呼び出しはここが唯一の実施点で、`Value` 出力は通常の set、`Sentinel` 出力は
/// 対応する直接操作へ落ちる (DR-114 §2)。
///
/// `Remove` を `ToValue` に写すのは、merge accumulator の add piece と同じ「operand が要素 type で
/// parse された値」だからである (DR-080 §2)。scalar seat には `Remove`/`Splice` は届かない
/// (呼び手側の防御 arm が受け持つ)。
fn fold_seat_effect(
  binding : @abi.Binding,
  old : @abi.Value?,
  target : String,
  extensions : @node.Registry,
) -> (SeatTransition, Bool) {
  match binding.op {
    @abi.Set | @abi.Remove => (ToValue(binding.value), false)
    @abi.EffectOp::Default => (ToDefault, false)
    @abi.Empty => (ToEmpty, false)
    @abi.Unset => (ToValue(@abi.Null), false)
    @abi.Splice => (NoChange, false)
    @abi.Invoke(invocation) => {
      let descriptor = match extensions.lookup_cell_fn(invocation.name) {
        Some(descriptor) => descriptor
        None => return (FnMissing(invocation.name), false)
      }
      let observes = match descriptor.concrete_observes(invocation) {
        Ok(observes) => observes
        Err(reason) => return (FnFailed(reason), false)
      }
      let ctx = @extension.FnCtx::for_effect(target, target, old~, observes~)
      let transition = match descriptor.invoke(invocation.to_call(), ctx) {
        Err(reason) => FnFailed(reason)
        Ok(@extension.FnOutput::Value(value)) => ToValue(value)
        Ok(@extension.FnOutput::Sentinel(@extension.UseDefault)) => ToDefault
        Ok(@extension.FnOutput::Sentinel(@extension.CellSentinel::Empty)) =>
          ToEmpty
      }
      // DR-127 §3: 値残余の空座では「ctx.old を要する」Value fn の適用が解決失敗になる。
      // descriptor に old 依存の宣言席が無いので、実行時に old() が参照されたかで判定する。
      (transition, ctx.old_consulted())
    }
  }
}

///|
/// 遷移後の座の値状態。`ToDefault` の落ち先は呼び手のラダーが決めるので引数で受ける
/// (供給が無ければ座は空 — 書き戻す値が無い)。状態を変えない遷移は `None` を返す。
fn seat_after(
  transition : SeatTransition,
  default_seat : @abi.Value?,
) -> SeatState? {
  match transition {
    ToValue(@abi.Null) => Some(Opened)
    ToValue(value) => Some(Seated(value))
    ToDefault =>
      Some(
        match default_seat {
          Some(value) => Seated(value)
          None => Emptied
        },
      )
    ToEmpty => Some(Emptied)
    NoChange | FnMissing(_) | FnFailed(_) => None
  }
}

///|
/// 効果列が畳んだ座の集合。key の綴りは呼び手が決める (`project_effects` は
/// `effect_cell_key` = scope path + `#` + 宣言名、`resolve_entity_raw` の CLI seat は
/// 1 セルしか畳まないので宣言名そのもの)。
///
/// 読み書きの口は `value_at` / `set_at` の 2 つだけである。**座そのものは空 segment 列という
/// 特例**で、値空間 (DR-127 §2.2) へ降りる部分更新は同じ口に segment 列を渡した形になる —
/// 降下の計算を 1 箇所へ集めておくと、vivify (DR-127 §3) を足すときに触る場所が 1 つで済む。
priv struct CellSeats {
  states : Map[String, SeatState]
}

///|
fn CellSeats::new() -> CellSeats {
  { states: Map([]) }
}

///|
/// 座の `ctx.old` (DR-114 §7)。`declared_default` は当該セルの宣言 default で、席が開いている
/// (= 効果がまだ無い / `unset` 済み) ときの落ち先。
fn CellSeats::old(
  self : CellSeats,
  key : String,
  declared_default : @abi.Value?,
) -> @abi.Value? {
  match self.value_at(key, []) {
    Ok(value) => Some(value)
    // 値の無い座は 2 種類ある (`SeatState` の doc comment): committed な空は absent、
    // 席が開いているだけなら宣言 default へ落ちる。
    Err(_) =>
      if self.states.get(key) is Some(Emptied) {
        None
      } else {
        declared_default
      }
  }
}

///|
/// 座の値状態を書く。値を持つ状態は「空 segment 列への部分更新」= 座そのものへの set なので、
/// 書き込み口を 1 つに保つため `set_at` を通す。
fn CellSeats::put(self : CellSeats, key : String, state : SeatState) -> Unit {
  match state {
    Seated(value) =>
      match self.set_at(key, [], value) {
        Ok(_) => ()
        Err(fault) =>
          abort(
            "空 segment 列の set_at は降下を伴わないので失敗しない (座そのものへの set): " +
            seat_fault_message(fault),
          )
      }
    Opened | Emptied => self.states.set(key, state)
  }
}

///|
/// 座への部分更新が成立しない理由。DR-127 §2.2 の値空間降下が実行時に返す診断の素材で、
/// 器の自動生成 (vivify、DR-127 §3) は本段では行わない — 未 vivify の座は `SeatAbsent` になる。
priv enum SeatFault {
  /// 座そのもの、または途中の器に値が無い。
  SeatAbsent
  /// スカラを segment で降りようとした。
  SeatNotContainer
  /// record 座に当該フィールドが無い。
  SeatMissingField(String)
  /// array の index が (負 index を長さで正規化した後も) 範囲外。
  SeatIndexOutOfRange(Int)
}

///|
/// 座の失敗理由の綴り。W2-6 の値空間降下が診断メッセージへ載せる素材で、防御 abort の
/// メッセージもここを通す (失敗の種類を握りつぶさない)。
fn seat_fault_message(fault : SeatFault) -> String {
  match fault {
    SeatAbsent => "absent"
    SeatNotContainer => "not-container"
    SeatMissingField(field) => "missing-field:" + field
    SeatIndexOutOfRange(index) => "index-out-of-range:" + index.to_string()
  }
}

///|
/// 負 index を長さで正規化する (DR-127 §6「index segment は解決済みの非負 index を載せる」の
/// 解決側)。範囲外は `None`。
fn normalized_index(index : Int, length : Int) -> Int? {
  let resolved = if index < 0 { length + index } else { index }
  if resolved < 0 || resolved >= length {
    None
  } else {
    Some(resolved)
  }
}

///|
/// 複合値へ segment 列で降りて値を取る。空 path は値そのもの。
fn value_at(
  value : @abi.Value,
  path : ArrayView[@abi.ObservationSegment],
) -> Result[@abi.Value, SeatFault] {
  match path {
    [] => Ok(value)
    [segment, .. rest] =>
      match (segment, value) {
        (@abi.ObservationName(field), @abi.Object(fields)) => {
          for entry in fields {
            if entry.0 == field {
              return value_at(entry.1, rest)
            }
          }
          Err(SeatMissingField(field))
        }
        (@abi.ObservationIndex(index), @abi.Array(items)) =>
          match normalized_index(index, items.length()) {
            Some(resolved) => value_at(items[resolved], rest)
            None => Err(SeatIndexOutOfRange(index))
          }
        _ => Err(SeatNotContainer)
      }
  }
}

///|
/// 複合値の segment 列が指す座を差し替えた新しい値を返す (元の値は変えない)。空 path は
/// 差し替え値そのもの。器が無い座は作らない — vivify (DR-127 §3) は W2-7 の責務で、ここでは
/// `SeatAbsent` / `SeatMissingField` / `SeatIndexOutOfRange` を返す。
fn value_with_at(
  value : @abi.Value,
  path : ArrayView[@abi.ObservationSegment],
  replacement : @abi.Value,
) -> Result[@abi.Value, SeatFault] {
  match path {
    [] => Ok(replacement)
    [segment, .. rest] =>
      match (segment, value) {
        (@abi.ObservationName(field), @abi.Object(fields)) => {
          let out : Array[(String, @abi.Value)] = []
          let mut hit = false
          for entry in fields {
            if entry.0 == field && !hit {
              match value_with_at(entry.1, rest, replacement) {
                Ok(updated) => out.push((entry.0, updated))
                Err(fault) => return Err(fault)
              }
              hit = true
            } else {
              out.push(entry)
            }
          }
          if hit {
            Ok(@abi.Object(out))
          } else {
            Err(SeatMissingField(field))
          }
        }
        (@abi.ObservationIndex(index), @abi.Array(items)) =>
          match normalized_index(index, items.length()) {
            Some(resolved) => {
              let out : Array[@abi.Value] = []
              for offset in 0..<items.length() {
                if offset == resolved {
                  match value_with_at(items[offset], rest, replacement) {
                    Ok(updated) => out.push(updated)
                    Err(fault) => return Err(fault)
                  }
                } else {
                  out.push(items[offset])
                }
              }
              Ok(@abi.Array(out))
            }
            None => Err(SeatIndexOutOfRange(index))
          }
        _ => Err(SeatNotContainer)
      }
  }
}

///|
/// 宣言 ValueType の record 段からフィールドの型参照を引く。union は「当該フィールドを持つ
/// record variant」の最初の 1 つ (DR-127 §2.2 union 行 — FieldType 終端の静的一致検査 (W2-6) を
/// 通過済みのパスでは、どの含有 variant を選んでも operand のパース実体は同一)。
fn declared_field_reference(
  declared : @abi.ValueType,
  field : String,
) -> String? {
  match declared {
    @abi.ValueType::Record(fields) => {
      for entry in fields {
        if entry.0 == field {
          return Some(entry.1)
        }
      }
      None
    }
    @abi.ValueType::Union(members) => {
      for variant_member in members {
        match declared_field_reference(variant_member, field) {
          Some(reference) => return Some(reference)
          None => ()
        }
      }
      None
    }
    _ => None
  }
}

///|
/// 宣言 ValueType を値空間残余 segment 列で降りたときの「その段の宣言型」。record フィールドは
/// type 参照ホップ (DR-126 §1) を挟むので registry を引く。辿れない段があれば `None`
/// (= 静的検査 (W2-6) を通過した routed パスでは起きない構造だが、防御として握りつぶさず None)。
fn declared_type_at(
  declared : @abi.ValueType?,
  path : ArrayView[@abi.ObservationSegment],
  registry : @extension.Registry,
) -> @abi.ValueType? {
  match path {
    [] => declared
    [segment, .. rest] =>
      match (segment, declared) {
        (@abi.ObservationName(field), Some(current)) =>
          match declared_field_reference(current, field) {
            Some(reference) =>
              match registry.resolve_type_reference(reference) {
                Some(resident) =>
                  declared_type_at(resident.output_type(), rest, registry)
                None => None
              }
            None => None
          }
        (@abi.ObservationIndex(_), Some(@abi.ValueType::Array(item))) =>
          declared_type_at(Some(item), rest, registry)
        (@abi.ObservationIndex(_), Some(@abi.ValueType::Union(members))) => {
          for variant_member in members {
            if variant_member is @abi.ValueType::Array(item) {
              return declared_type_at(Some(item), rest, registry)
            }
          }
          None
        }
        _ => None
      }
  }
}

///|
/// 値残余終端のフィールド type が名乗る `out` (DR-127 §3.2 — 座に座る値の適合検査の规準)。
fn residual_terminal_out(
  declared : @abi.ValueType?,
  path : Array[@abi.ObservationSegment],
  registry : @extension.Registry,
) -> @abi.ValueType? {
  declared_type_at(declared, path[:], registry)
}

///|
/// 宣言型で record 段と言える (= 器 `{}` を vivify してよい) か。union は含有 variant に record が
/// あれば器を作れる (DR-127 §2.2 vivify 列 — 構造的なので variant 選択は不要)。
fn declared_vivifies_record(declared : @abi.ValueType?) -> Bool {
  match declared {
    Some(@abi.ValueType::Record(_)) => true
    Some(@abi.ValueType::Union(members)) => {
      for variant_member in members {
        if declared_vivifies_record(Some(variant_member)) {
          return true
        }
      }
      false
    }
    _ => false
  }
}

///|
/// 宣言型併走の値空間読み (DR-130 §4.1): record の宣言済み座で物理的に欠落しているものは
/// 論理的に `null` と読む。器そのものが無い座は従来どおり `SeatAbsent` (空座 — DR-127 §3 の
/// Reject 判定素材として区別が要る)。
fn typed_value_at(
  value : @abi.Value,
  declared : @abi.ValueType?,
  path : ArrayView[@abi.ObservationSegment],
  registry : @extension.Registry,
) -> Result[@abi.Value, SeatFault] {
  match path {
    [] => Ok(value)
    [segment, .. rest] =>
      match (segment, value) {
        (@abi.ObservationName(field), @abi.Object(fields)) => {
          for entry in fields {
            if entry.0 == field {
              return typed_value_at(
                entry.1,
                declared_type_at(declared, path[0:1], registry),
                rest,
                registry,
              )
            }
          }
          // 宣言済みフィールドの欠落は論理 null (DR-130 §4.1)。パスがさらに続くなら
          // null の中は辿れないので、その先の座は器なし (= SeatAbsent) である。
          match declared {
            Some(current) =>
              if declared_field_reference(current, field) is Some(_) {
                if rest is [] {
                  Ok(@abi.Null)
                } else {
                  Err(SeatAbsent)
                }
              } else {
                Err(SeatMissingField(field))
              }
            None => Err(SeatMissingField(field))
          }
        }
        (@abi.ObservationIndex(index), @abi.Array(items)) =>
          match normalized_index(index, items.length()) {
            Some(resolved) =>
              typed_value_at(
                items[resolved],
                declared_type_at(declared, path[0:1], registry),
                rest,
                registry,
              )
            None => Err(SeatIndexOutOfRange(index))
          }
        _ => Err(SeatNotContainer)
      }
  }
}

///|
/// 宣言型併走の値空間書き (DR-127 §3)。`value` None = 器なし。vivify (器 `{}` の生成) が働くのは
/// (a) `vivify` = true (op gate: `set` 専用) かつ (b) その段の宣言型が record (union は含有
/// variant の器) の場合のみ。既存 record 器への宣言済みフィールドの追記は器生成ではないので
/// vivify gate に依らない。array / map / value の器は作らない (DR-127 §2.2 vivify 列)。
fn typed_value_with_at(
  value : @abi.Value?,
  declared : @abi.ValueType?,
  path : ArrayView[@abi.ObservationSegment],
  replacement : @abi.Value,
  registry : @extension.Registry,
  vivify : Bool,
) -> Result[@abi.Value, SeatFault] {
  match path {
    [] => Ok(replacement)
    [segment, .. rest] =>
      match segment {
        @abi.ObservationName(field) => {
          let field_declared = declared_type_at(declared, path[0:1], registry)
          match value {
            None =>
              // 器なし → record 段なら vivify (器 `{}` を作って降下を続ける)。
              if vivify && declared_vivifies_record(declared) {
                match
                  typed_value_with_at(
                    None,
                    field_declared,
                    rest,
                    replacement,
                    registry,
                    vivify,
                  ) {
                  Ok(inner) => Ok(@abi.Object([(field, inner)]))
                  Err(fault) => Err(fault)
                }
              } else {
                Err(SeatAbsent)
              }
            Some(@abi.Object(fields)) => {
              let out : Array[(String, @abi.Value)] = []
              let mut hit = false
              for entry in fields {
                if entry.0 == field && !hit {
                  match
                    typed_value_with_at(
                      Some(entry.1),
                      field_declared,
                      rest,
                      replacement,
                      registry,
                      vivify,
                    ) {
                    Ok(updated) => out.push((entry.0, updated))
                    Err(fault) => return Err(fault)
                  }
                  hit = true
                } else {
                  out.push(entry)
                }
              }
              if hit {
                return Ok(@abi.Object(out))
              }
              // 宣言済みフィールドの欠落座への書き = キーの追記 (器は既にあるので vivify gate 外)。
              // ただしパスがさらに続く場合、中間器の生成は vivify の領分に戻る。
              match declared {
                Some(current) if declared_field_reference(current, field)
                  is Some(_) =>
                  match
                    typed_value_with_at(
                      None,
                      field_declared,
                      rest,
                      replacement,
                      registry,
                      vivify,
                    ) {
                    Ok(inner) => {
                      out.push((field, inner))
                      Ok(@abi.Object(out))
                    }
                    Err(fault) => Err(fault)
                  }
                _ => Err(SeatMissingField(field))
              }
            }
            Some(_) => Err(SeatNotContainer)
          }
        }
        @abi.ObservationIndex(index) =>
          match value {
            // array の要素は実行時にしか存在しない — 器を vivify しない (DR-127 §2.2)。
            None => Err(SeatAbsent)
            Some(@abi.Array(items)) =>
              match normalized_index(index, items.length()) {
                Some(resolved) => {
                  let element_declared = declared_type_at(
                    declared,
                    path[0:1],
                    registry,
                  )
                  let out : Array[@abi.Value] = []
                  for offset in 0..<items.length() {
                    if offset == resolved {
                      match
                        typed_value_with_at(
                          Some(items[offset]),
                          element_declared,
                          rest,
                          replacement,
                          registry,
                          vivify,
                        ) {
                        Ok(updated) => out.push(updated)
                        Err(fault) => return Err(fault)
                      }
                    } else {
                      out.push(items[offset])
                    }
                  }
                  Ok(@abi.Array(out))
                }
                None => Err(SeatIndexOutOfRange(index))
              }
            Some(_) => Err(SeatNotContainer)
          }
      }
  }
}

///|
/// 座の値空間残余への読み (宣言型併走、DR-130 §4.1 の論理 null 込み)。
fn CellSeats::value_at_declared(
  self : CellSeats,
  key : String,
  path : Array[@abi.ObservationSegment],
  declared : @abi.ValueType?,
  registry : @extension.Registry,
) -> Result[@abi.Value, SeatFault] {
  match self.states.get(key) {
    Some(Seated(value)) => typed_value_at(value, declared, path[:], registry)
    _ => Err(SeatAbsent)
  }
}

///|
/// 座の値空間残余への書き (宣言型併走、vivify は `set` 専用の op gate を呼び手が `vivify~` で渡す)。
fn CellSeats::set_at_declared(
  self : CellSeats,
  key : String,
  path : Array[@abi.ObservationSegment],
  value : @abi.Value,
  declared : @abi.ValueType?,
  registry : @extension.Registry,
  vivify~ : Bool,
) -> Result[Unit, SeatFault] {
  let current : @abi.Value? = match self.states.get(key) {
    Some(Seated(seated)) => Some(seated)
    _ => None
  }
  match
    typed_value_with_at(current, declared, path[:], value, registry, vivify) {
    Ok(updated) => {
      self.states.set(key, Seated(updated))
      Ok(())
    }
    Err(fault) => Err(fault)
  }
}

///|
/// 座の中の segment 列が指す値を読む。空 path は座の値そのもの。値の無い座は `SeatAbsent`。
fn CellSeats::value_at(
  self : CellSeats,
  key : String,
  path : Array[@abi.ObservationSegment],
) -> Result[@abi.Value, SeatFault] {
  match self.states.get(key) {
    Some(Seated(value)) => value_at(value, path[:])
    _ => Err(SeatAbsent)
  }
}

///|
/// 座の中の segment 列が指す値を書く。空 path は座そのものへの set。
fn CellSeats::set_at(
  self : CellSeats,
  key : String,
  path : Array[@abi.ObservationSegment],
  value : @abi.Value,
) -> Result[Unit, SeatFault] {
  if path.length() == 0 {
    self.states.set(key, Seated(value))
    return Ok(())
  }
  match self.states.get(key) {
    Some(Seated(current)) =>
      match value_with_at(current, path[:], value) {
        Ok(updated) => {
          self.states.set(key, Seated(updated))
          Ok(())
        }
        Err(fault) => Err(fault)
      }
    _ => Err(SeatAbsent)
  }
}
