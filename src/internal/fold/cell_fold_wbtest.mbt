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

///|
fn fold_test_binding(op : @abi.EffectOp) -> @abi.Binding {
  { ..@abi.Binding::new("cell", @abi.Bool(false), @abi.Cli), op, }
}

///|
fn fold_test_registry() -> @extension.Registry {
  let registry = @extension.Registry::new()
  for descriptor in @extension.cell_fn_descriptors() {
    guard registry.register_cell_fn(descriptor) else {
      abort("duplicate builtin cell fn: " + descriptor.name())
    }
  }
  registry
}

///|
/// 保証 (DR-045 / DR-131 §2b, §7): 共有 fold は直接操作を値状態の遷移へ全列挙で写す。
/// `unset` の旧 op carrier も通常値 null と同じ `ToValue(Null)` に正規化し、`default` / `empty`
/// はそれぞれ default 席 / committed な空へ遷移する。`splice` は accumulator piece のため
/// scalar 座の値状態を変えない。これは lowering の到達性ではなく fold 自体の遷移表を固定する単体 pin。
test "fold_seat_effect: 直接操作を SeatTransition へ全列挙する (DR-045 / DR-131)" {
  let registry = @extension.Registry::new()
  let (unset, unset_old) = fold_seat_effect(
    fold_test_binding(@abi.Unset),
    None,
    "cell",
    registry,
  )
  assert_true(unset is ToValue(@abi.Null))
  assert_false(unset_old)

  let (use_default, default_old) = fold_seat_effect(
    fold_test_binding(@abi.EffectOp::Default),
    None,
    "cell",
    registry,
  )
  assert_true(use_default is ToDefault)
  assert_false(default_old)

  let (empty, empty_old) = fold_seat_effect(
    fold_test_binding(@abi.Empty),
    None,
    "cell",
    registry,
  )
  assert_true(empty is ToEmpty)
  assert_false(empty_old)

  let (splice, splice_old) = fold_seat_effect(
    fold_test_binding(@abi.Splice),
    None,
    "cell",
    registry,
  )
  assert_true(splice is NoChange)
  assert_false(splice_old)
}

///|
/// 保証 (DR-114 §2 / §7、DR-131 §2b / §7): `Invoke` は registry resident を共有 fold の中で
/// 一度だけ発火し、Value(null) / UseDefault / Empty を直接操作と同じ遷移へ落とす。未知名と resident
/// failure は座を変えない失敗遷移として区別し、現行 lowering が先に弾く経路にも fold 単体の防衛網を持つ。
test "fold_seat_effect: Invoke の Value/Sentinel/未知名/失敗を全分類する (DR-114 / DR-131)" {
  let registry = fold_test_registry()
  let invoke = fn(name : String, args : Array[String]) {
    fold_test_binding(@abi.Invoke({ name, args }))
  }

  // unset resident は ordinary Value(null) を返すため、旧 Unset op と同じ席開放遷移になる。
  let (unset, _) = fold_seat_effect(invoke("unset", []), None, "cell", registry)
  assert_true(unset is ToValue(@abi.Null))

  // default / empty resident の Sentinel は fold 境界で対応する直接操作へ正規化される。
  let (use_default, _) = fold_seat_effect(
    invoke("default", []),
    None,
    "cell",
    registry,
  )
  assert_true(use_default is ToDefault)
  let (empty, _) = fold_seat_effect(invoke("empty", []), None, "cell", registry)
  assert_true(empty is ToEmpty)

  // registry に無い名前は FnMissing。座の値状態を変更する遷移へ化けない。
  let (missing, _) = fold_seat_effect(
    invoke("not-registered", []),
    None,
    "cell",
    registry,
  )
  assert_true(missing is FnMissing("not-registered"))

  // env resident は観測先が無いと reject する。失敗理由を保持した FnFailed で返す。
  let (failed, _) = fold_seat_effect(
    invoke("env", ["MISSING"]),
    None,
    "cell",
    registry,
  )
  match failed {
    FnFailed(reason) => {
      assert_eq(reason.disposition, @abi.RecognizedButInvalid)
      assert_eq(reason.reason, "absent-source")
    }
    _ => fail("missing env source must remain a classified FnFailed transition")
  }
}

///|
/// 保証 (DR-114 §7 / DR-081 §2 / DR-131 §7): 遷移から座状態への写像は、null による席開放、
/// default 席の有無、committed な空、状態不変の失敗を区別する。特に default 値が無い場合の
/// `ToDefault` は値を捏造せず `Emptied` へ落ち、FnMissing/FnFailed は既存座を書き換えない。
test "seat_after: 遷移後の Opened/Seated/Emptied/不変を全列挙する" {
  assert_true(seat_after(ToValue(@abi.Null), None) is Some(Opened))
  assert_true(
    seat_after(ToValue(@abi.Number(7.0)), None)
    is Some(Seated(@abi.Number(7.0))),
  )
  assert_true(
    seat_after(ToDefault, Some(@abi.String("declared")))
    is Some(Seated(@abi.String("declared"))),
  )
  assert_true(seat_after(ToDefault, None) is Some(Emptied))
  assert_true(seat_after(ToEmpty, None) is Some(Emptied))
  assert_true(seat_after(NoChange, None) is None)
  assert_true(seat_after(FnMissing("missing"), None) is None)
  assert_true(
    seat_after(
      FnFailed({
        disposition: @abi.RecognizedButInvalid,
        reason: "failed",
        message: "failed",
      }),
      None,
    )
    is None,
  )
}
