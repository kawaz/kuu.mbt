// firing_record.mbt — DR-114 §6.1「fn は発火時に 1 回」の配達席。
//
// 勝ち枝確定後の 1 回の fold 実行 (値残余セル分は DR-127 §4.2 の枝ローカル fold の枝内実行結果を
// そのまま引き継ぐ) が、発火 1 件ごとの結果を FiringRecord として記録し、effects 射影
// (`front_door.mbt` の `projected_effect`) と resolve 相の CLI seat 解決 (`resolve.mbt` の
// `resolve_entity_raw`) は record の**消費者**になって cell fn を再実行しない。
//
// 識別上の設計制約 (W2-9 監査 M2): `Binding` の `derive(Eq)` は DR-038 の効果 identity
// (裁定前の `Array[Binding]` 構造等価 dedup) の実装そのものなので、値依存の record を
// Binding へ載せると非決定 fn の値差で同一効果列が別経路化する。record は Binding / Outcome の
// Eq に一切参加しない **side payload** (枝に併走する branch payload) としてここに置き、
// 効果列との対応は「セル (scope+key) ごとの出現順」で取る — binding の綴り (op / operand /
// value_residual) は不変のまま (DR-045 の綴り保持)。
//
// record が無い発火 (fold の保守的スキップ = 宣言を特定できない / 候補が食い違うセル、accum
// セル、CLI 以外の供給経路) は従来どおり resolve 相の残余分岐が最終防衛線として実行する —
// 一本化は「record がある発火を再実行しない」であり、防衛線の削除ではない。

///|
/// 発火 1 件の記録。`transition` は共有 fold (`fold_seat_effect`) の実行結果そのもの、
/// `old_used` は実行時に供給した `ctx.old` (DR-114 §7)。resolve 相の消費 gate は
/// 「自席で計算した old と `old_used` の一致」— parse 相と resolve 相で値源 (`ValueSources`)
/// が食い違う呼び出し (契約違反) や未供給経路では一致せず、現行どおり再実行に落ちる。
/// `resolved_residual` は発火時点の座の現在長で解決した観測アドレス片 (DR-127 §6、
/// `CellSeats::resolved_residual` の結果 — `None` = 着地座が確定できず字面フォールバック)。
pub(all) struct FiringRecord {
  transition : SeatTransition
  old_used : @abi.Value?
  old_consulted : Bool
  resolved_residual : Array[@abi.ObservationSegment]?
}

///|
/// この binding が record を持つ発火か (= ledger の出現順カウントに参加するか)。
/// cell fn の発火 (`Invoke`) と、値空間残余の座への着地 (解決済みアドレスの記録対象) が対象。
/// 生産者 (fold) と消費者 (effects 射影 / resolve) が同じ述語でカウントすることで、
/// binding 列の中の record 対応が位置ずれしない。
pub fn records_firing(binding : @abi.Binding) -> Bool {
  binding.op is @abi.Invoke(_) || binding.value_residual.length() > 0
}

///|
/// セル (scope + key) の ledger キー綴り。`\u{1f}` 区切りは scope segment の綴りと衝突しない
/// (branch fold の `seat_decl_key` と同じ選択)。
pub fn firing_cell_key(scope : Array[String], key : String) -> String {
  let out = StringBuilder::new()
  for segment in scope {
    out.write_string(segment)
    out.write_char('\u{1f}')
  }
  out.write_char('\u{1f}')
  out.write_string(key)
  out.to_string()
}

///|
/// 完全経路 1 本ぶんの record 台帳。セルごとに、そのセルの record 対象 binding
/// (`records_firing`) の効果列出現順と並走する配列を持つ。
pub struct FiringLedger {
  priv cells : Map[String, Array[FiringRecord]]
}

///|
pub fn FiringLedger::new() -> FiringLedger {
  { cells: Map([]) }
}

///|
pub fn FiringLedger::push(
  self : FiringLedger,
  scope : Array[String],
  key : String,
  record : FiringRecord,
) -> Unit {
  let cell = firing_cell_key(scope, key)
  match self.cells.get(cell) {
    Some(records) => records.push(record)
    None => self.cells.set(cell, [record])
  }
}

///|
/// セル内 `index` 番目 (record 対象 binding の出現順) の record。無ければ `None`
/// (= 消費者は現行どおり自分で実行する)。
pub fn FiringLedger::record_at(
  self : FiringLedger,
  scope : Array[String],
  key : String,
  index : Int,
) -> FiringRecord? {
  match self.cells.get(firing_cell_key(scope, key)) {
    Some(records) =>
      if index >= 0 && index < records.length() {
        Some(records[index])
      } else {
        None
      }
    None => None
  }
}

///|
/// 消費者側の出現順カウンタ。binding 列を効果列順に 1 度ずつ通し、record 対象 binding
/// (`records_firing`) だけカウントを進めて対応 record を引く。スキップされる binding
/// (effects 射影の内部セル除外等) もこのカーソルを**通してから**スキップすること —
/// 位置ずれ防止のため、カウントと消費を分離しない。
pub struct FiringCursor {
  priv counts : Map[String, Int]
}

///|
pub fn FiringCursor::new() -> FiringCursor {
  { counts: Map([]) }
}

///|
pub fn FiringCursor::next(
  self : FiringCursor,
  ledger : FiringLedger?,
  binding : @abi.Binding,
) -> FiringRecord? {
  if !records_firing(binding) {
    return None
  }
  let cell = firing_cell_key(binding.scope, binding.key)
  let index = self.counts.get(cell).unwrap_or(0)
  self.counts.set(cell, index + 1)
  match ledger {
    Some(ledger) => ledger.record_at(binding.scope, binding.key, index)
    None => None
  }
}

///|
/// `parse_tree` の配達口: 完全経路 (dedup 後の勝ち候補) ごとの (binds, ledger) 対。
/// binds は parse Success payload / ambiguous interpretation の `Array[Binding]` そのもので、
/// requires filter (DR-047 §5) の経路選別を挟んでも構造等価 (= DR-038 identity) で引き直せる。
pub struct FiringDeliveries {
  priv deliveries : Array[(Array[@abi.Binding], FiringLedger)]
}

///|
pub fn FiringDeliveries::new() -> FiringDeliveries {
  { deliveries: [] }
}

///|
pub fn FiringDeliveries::deliver(
  self : FiringDeliveries,
  binds : Array[@abi.Binding],
  ledger : FiringLedger,
) -> Unit {
  self.deliveries.push((binds, ledger))
}

///|
pub fn FiringDeliveries::ledger_for(
  self : FiringDeliveries,
  binds : Array[@abi.Binding],
) -> FiringLedger? {
  for delivery in self.deliveries {
    if delivery.0 == binds {
      return Some(delivery.1)
    }
  }
  None
}
