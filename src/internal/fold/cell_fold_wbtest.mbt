// cell_fold_wbtest.mbt — 座への部分更新 API (`CellSeats::value_at` / `set_at`) の単体 pin。
// DR-127 §2.2 の値空間降下が使う唯一の入口で、vivify (DR-127 §3) を足すときに挙動が変わる
// 境界そのもの。効果 fold の一本化 (effects と result の一致) は kuu 側の
// `src/kuu/cell_fold_wbtest.mbt` が公開 API 経由で固定する。

///|
fn fold_test_render_val(value : @abi.Value) -> String {
  match value {
    @abi.Null => "null"
    @abi.String(s) => s
    @abi.Bool(b) => if b { "true" } else { "false" }
    @abi.Number(d) => {
      let i = d.to_int()
      if i.to_double() == d {
        i.to_string()
      } else {
        d.to_string()
      }
    }
    @abi.Array(_) | @abi.Object(_) =>
      abort("this unit pin only reads scalar leaves back")
  }
}

///|
fn seat_read(
  seats : CellSeats,
  key : String,
  path : Array[@abi.ObservationSegment],
) -> String {
  match seats.value_at(key, path) {
    Ok(value) => fold_test_render_val(value)
    Err(fault) => seat_fault_message(fault)
  }
}

///|
fn seat_write(
  seats : CellSeats,
  key : String,
  path : Array[@abi.ObservationSegment],
  value : @abi.Value,
) -> String {
  match seats.set_at(key, path, value) {
    Ok(_) => "ok"
    Err(fault) => seat_fault_message(fault)
  }
}

///|
/// 保証 (DR-127 §2.2 / §6): 座への部分更新は segment 列 (`ObservationName` / `ObservationIndex`)
/// で複合値へ降りる。負 index は長さで正規化し (DR-127 §6 の「解決済み非負 index」の解決側)、
/// 範囲外・型不一致・不在フィールドはそれぞれ別の診断で失敗する。**器の自動生成は行わない** —
/// vivify は DR-127 §3 (W2-7) の責務なので、未 vivify の座は `absent` で失敗する。
test "CellSeats: 座への部分更新は record 座 / array index / 負 index を扱い、未 vivify は失敗する (DR-127 §2.2/§3/§6)" {
  let seats = CellSeats::new()

  // 未 vivify の座 = そもそも値が無い。読みも書きも absent (器を作らない)。
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationName("a")]), "absent")
  assert_eq(
    seat_write(seats, "#cell", [@abi.ObservationName("a")], @abi.Number(1.0)),
    "absent",
  )

  // 空 path は座そのもの。set_at は座を作れる (降下ではないので vivify ではない)。
  assert_eq(seat_write(seats, "#cell", [], @abi.String("scalar")), "ok")
  assert_eq(seat_read(seats, "#cell", []), "scalar")

  // スカラ座へ segment で降りようとしたら not-container。
  assert_eq(
    seat_read(seats, "#cell", [@abi.ObservationName("a")]),
    "not-container",
  )
  assert_eq(
    seat_read(seats, "#cell", [@abi.ObservationIndex(0)]),
    "not-container",
  )

  // record 座: 宣言済みフィールドは読み書きでき、未宣言フィールドは missing-field。
  assert_eq(
    seat_write(
      seats,
      "#cell",
      [],
      @abi.Object([("host", @abi.String("a")), ("port", @abi.Number(80.0))]),
    ),
    "ok",
  )
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationName("port")]), "80")
  assert_eq(
    seat_write(
      seats,
      "#cell",
      [@abi.ObservationName("port")],
      @abi.Number(443.0),
    ),
    "ok",
  )
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationName("port")]), "443")
  // 部分更新は兄弟フィールドを保つ。
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationName("host")]), "a")
  assert_eq(
    seat_read(seats, "#cell", [@abi.ObservationName("scheme")]),
    "missing-field:scheme",
  )
  assert_eq(
    seat_write(
      seats,
      "#cell",
      [@abi.ObservationName("scheme")],
      @abi.String("https"),
    ),
    "missing-field:scheme",
  )

  // array 座: 非負 index と負 index (末尾からの数え上げ) の両方が同じ座を指す。
  assert_eq(
    seat_write(
      seats,
      "#cell",
      [],
      @abi.Array([@abi.String("x"), @abi.String("y"), @abi.String("z")]),
    ),
    "ok",
  )
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationIndex(2)]), "z")
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationIndex(-1)]), "z")
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationIndex(-3)]), "x")
  assert_eq(
    seat_write(seats, "#cell", [@abi.ObservationIndex(-1)], @abi.String("Z")),
    "ok",
  )
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationIndex(2)]), "Z")
  assert_eq(seat_read(seats, "#cell", [@abi.ObservationIndex(0)]), "x")
  // 範囲外は正規化後も範囲外 (index は字面のまま診断に載る)。
  assert_eq(
    seat_read(seats, "#cell", [@abi.ObservationIndex(3)]),
    "index-out-of-range:3",
  )
  assert_eq(
    seat_read(seats, "#cell", [@abi.ObservationIndex(-4)]),
    "index-out-of-range:-4",
  )

  // 入れ子: record の中の array の中の record まで降りて書く。
  assert_eq(
    seat_write(
      seats,
      "#cell",
      [],
      @abi.Object([
        ("rows", @abi.Array([@abi.Object([("id", @abi.Number(1.0))])])),
      ]),
    ),
    "ok",
  )
  let nested : Array[@abi.ObservationSegment] = [
    @abi.ObservationName("rows"),
    @abi.ObservationIndex(-1),
    @abi.ObservationName("id"),
  ]
  assert_eq(seat_read(seats, "#cell", nested), "1")
  assert_eq(seat_write(seats, "#cell", nested, @abi.Number(2.0)), "ok")
  assert_eq(seat_read(seats, "#cell", nested), "2")
  // 途中の segment が外れれば、その段の診断が返る (先頭段の診断へ潰さない)。
  assert_eq(
    seat_read(seats, "#cell", [
      @abi.ObservationName("rows"),
      @abi.ObservationIndex(1),
    ]),
    "index-out-of-range:1",
  )
}
