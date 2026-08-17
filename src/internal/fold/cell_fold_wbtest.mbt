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
    guard registry.register_cell_fn(descriptor) is Ok(_) else {
      abort("duplicate builtin cell fn: " + descriptor.name())
    }
  }
  guard registry.register_cell_fn(
      @extension.cell_fn_descriptor(
        "test/fail-observes",
        [@extension.cell_fn_parameter("source")],
        @extension.CellFnOutput::Value,
        @extension.Total,
        observes=["option:<source>"],
        run=fn(_, _) { Ok(@extension.FnOutput::Value(@abi.Bool(true))) },
      ),
    )
    is Ok(_) else {
    abort("duplicate test/fail-observes cell fn")
  }
  guard registry.register_cell_fn(
      @extension.cell_fn_descriptor(
        "test/fail-run",
        [],
        @extension.CellFnOutput::Value,
        @extension.Reject,
        reasons=["test-failure"],
        run=fn(_, _) {
          Err({
            disposition: @abi.RecognizedButInvalid,
            reason: "test-failure",
            message: "test resident rejects",
          })
        },
      ),
    )
    is Ok(_) else {
    abort("duplicate test/fail-run cell fn")
  }
  registry
}

///|
/// 保証 (DR-045 / DR-080 §2 / DR-131 §7): 共有 fold は現行の直接操作語彙を値状態の遷移へ
/// 全列挙で写す。`set` / `remove` は operand を座らせ、`default` / `empty` は default 席 / committed
/// な空へ遷移し、`splice` は accumulator piece のため scalar 座の値状態を変えない。DR-131 §6 で
/// 廃止された直接 `Unset` carrier はここで規範化せず、正規経路の `Invoke(unset) → Value(null)` を別 test が固定する。
test "fold_seat_effect: 現行の直接操作を SeatTransition へ全列挙する (DR-045 / DR-080 / DR-131)" {
  let registry = @extension.Registry::new()
  let (set, set_old) = fold_seat_effect(
    fold_test_binding(@abi.Set),
    None,
    "cell",
    registry,
  )
  assert_true(set is ToValue(@abi.Bool(false)))
  assert_false(set_old)

  let (remove, remove_old) = fold_seat_effect(
    fold_test_binding(@abi.Remove),
    None,
    "cell",
    registry,
  )
  assert_true(remove is ToValue(@abi.Bool(false)))
  assert_false(remove_old)

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
/// 保証 (DR-114 §2 / §7、DR-127 §3、DR-131 §2b / §7): `Invoke` は registry resident を共有
/// fold の中で一度だけ発火し、非 null Value / Value(null) / UseDefault / Empty を分類する。失敗は
/// registry 不在、observes 具体化失敗、resident 本体失敗を区別し、`ctx.old()` の参照事実も返す。
test "fold_seat_effect: Invoke の出力・失敗段・old 参照を全分類する (DR-114 / DR-127 / DR-131)" {
  let registry = fold_test_registry()
  let invoke = fn(name : String, args : Array[String]) {
    fold_test_binding(@abi.Invoke({ name, args }))
  }

  // incr は発火直前の old=4 を読み、非 null Value(5) を返す。old_consulted=true が空座 Reject の根拠。
  let (incremented, increment_old) = fold_seat_effect(
    invoke("incr", []),
    Some(@abi.Number(4.0)),
    "cell",
    registry,
  )
  assert_true(incremented is ToValue(@abi.Number(5.0)))
  assert_true(increment_old)

  // unset resident は ordinary Value(null) を返して席を開くが、old は参照しない。
  let (unset, unset_old) = fold_seat_effect(
    invoke("unset", []),
    None,
    "cell",
    registry,
  )
  assert_true(unset is ToValue(@abi.Null))
  assert_false(unset_old)

  // default / empty resident の Sentinel は対応する直接操作へ正規化され、old は参照しない。
  let (use_default, default_old) = fold_seat_effect(
    invoke("default", []),
    None,
    "cell",
    registry,
  )
  assert_true(use_default is ToDefault)
  assert_false(default_old)
  let (empty, empty_old) = fold_seat_effect(
    invoke("empty", []),
    None,
    "cell",
    registry,
  )
  assert_true(empty is ToEmpty)
  assert_false(empty_old)

  // registry に無い名前は FnMissing。座の値状態を変更する遷移へ化けない。
  let (missing, missing_old) = fold_seat_effect(
    invoke("not-registered", []),
    None,
    "cell",
    registry,
  )
  assert_true(missing is FnMissing("not-registered"))
  assert_false(missing_old)

  // 不正 arity は定義検査が先に弾くが、fold の防御 arm は observes 具体化失敗を FnFailed で保持する。
  let (observes_failed, observes_old) = fold_seat_effect(
    invoke("test/fail-observes", []),
    None,
    "cell",
    registry,
  )
  match observes_failed {
    FnFailed(reason) => assert_eq(reason.reason, "invalid-argument")
    _ => fail("malformed invocation must fail while concretizing observes")
  }
  assert_false(observes_old)

  // 規範上 failure を宣言する test resident で、本体 reject が FnFailed として理由を保持することを固定する。
  let (invoke_failed, invoke_old) = fold_seat_effect(
    invoke("test/fail-run", []),
    None,
    "cell",
    registry,
  )
  match invoke_failed {
    FnFailed(reason) => {
      assert_eq(reason.disposition, @abi.RecognizedButInvalid)
      assert_eq(reason.reason, "test-failure")
    }
    _ => fail("resident rejection must remain a classified FnFailed transition")
  }
  assert_false(invoke_old)
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

///|
fn cull_test_write(
  value : @abi.Value,
  residual : Array[@abi.ObservationSegment],
  at_pos : Int,
) -> @abi.Binding {
  {
    ..@abi.Binding::new("cell", value, @abi.Cli, at_pos=Some(at_pos)),
    op: @abi.Set,
    value_residual: residual,
  }
}

///|
/// 保証 (DR-138 §1/§2/§4/§5/§6): union 宣言セルの確定相。書き込みは型適合する全枝へ並行着地し
/// (含まない枝には Reject も Error も出ない)、未完成枝は淘汰され、生存枝の最終着地が後勝ちで
/// セル値になる。生存ゼロは Incomplete、複数枝の同時最終着地は同値なら Winner・異値なら Tie。
/// 書き込み自体の失敗 (未登録 cell fn) は淘汰に吸わせず WriteFailed で書き込み時に裁く。
test "cull_union_cell: 並行着地・未完成淘汰・後勝ち・tie・書き込み失敗を分類する (DR-138 §1/§2/§4/§5/§6)" {
  let registry = fold_test_registry()
  let color : Array[@abi.ValueType] = [
    @abi.ValueType::Tuple(["int", "int", "int"]),
    @abi.ValueType::String,
  ]

  // 書き込みゼロ = 淘汰対象外。ラダーは通常どおり開く (DR-138 §3 の committed 基準)。
  assert_true(cull_union_cell("cell", color, [], registry) is NoWrites)

  // 位置書きだけでは tuple 枝が [0,255,null] で未完成、string 枝へは着地しない
  // → 生存ゼロ。args_pos は当該セルに着地した書き込みのうち argv 位置最深 (DR-138 §4)。
  let partial = cull_union_cell(
    "cell",
    color,
    [
      cull_test_write(@abi.Number(0.0), [@abi.ObservationIndex(0)], 1),
      cull_test_write(@abi.Number(255.0), [@abi.ObservationIndex(1)], 3),
    ],
    registry,
  )
  assert_true(partial is Incomplete(3))

  // 全座が埋まれば tuple 枝が完成し、生存枝は 1 本 → その値で確定。
  let complete = cull_union_cell(
    "cell",
    color,
    [
      cull_test_write(@abi.Number(0.0), [@abi.ObservationIndex(0)], 1),
      cull_test_write(@abi.Number(255.0), [@abi.ObservationIndex(1)], 3),
      cull_test_write(@abi.Number(7.0), [@abi.ObservationIndex(2)], 5),
    ],
    registry,
  )
  match complete {
    Winner(candidate) => {
      assert_eq(candidate.variant_index, 0)
      assert_true(candidate.value is @abi.Array(_))
    }
    _ => abort("expected the tuple branch to survive alone")
  }

  // 丸ごと set は型適合する枝にだけ着地する — string は tuple 枝の構造に適合しないので、
  // 未完成の tuple 枝は淘汰され string 枝が残る (位置書きは黙って消える、DR-138 §2)。
  let whole_set_wins = cull_union_cell(
    "cell",
    color,
    [
      cull_test_write(@abi.Number(0.0), [@abi.ObservationIndex(0)], 1),
      cull_test_write(@abi.String("blue"), [], 3),
    ],
    registry,
  )
  match whole_set_wins {
    Winner(candidate) => assert_eq(candidate.variant_index, 1)
    _ => abort("expected the string branch to survive alone")
  }

  // 入れ子 union は葉集合へ平坦化して読む (DR-138 §1) — 葉の tuple へ位置書きが届く。
  let nested = union_leaf_variants([
    @abi.ValueType::Union([
      @abi.ValueType::Tuple(["int", "int"]),
      @abi.ValueType::Bool,
    ]),
    @abi.ValueType::String,
  ])
  assert_eq(nested.length(), 3)
  match
    cull_union_cell(
      "cell",
      nested,
      [
        cull_test_write(@abi.Number(1.0), [@abi.ObservationIndex(0)], 0),
        cull_test_write(@abi.Number(2.0), [@abi.ObservationIndex(1)], 1),
      ],
      registry,
    ) {
    Winner(candidate) => assert_eq(candidate.variant_index, 0)
    _ => abort("expected the flattened tuple leaf to survive")
  }

  // フィールド集合の違う record 2 variant の共有フィールドへの 1 書き込みは両枝を完成させ、
  // 射影後の観測値が違う ({a:1} vs {a:1,b:null}) ので tie = ambiguous (DR-138 §5)。
  let shape : Array[@abi.ValueType] = [
    @abi.ValueType::Record([("a", "int")]),
    @abi.ValueType::Record([("a", "int"), ("b", "int")]),
  ]
  match
    cull_union_cell(
      "cell",
      shape,
      [cull_test_write(@abi.Number(1.0), [@abi.ObservationName("a")], 1)],
      registry,
    ) {
    Tie(candidates) => assert_eq(candidates.length(), 2)
    _ => abort("expected both record branches to tie")
  }

  // 明示 `default` 効果は宣言 default を完全値 1 発として運ぶ (DR-138 §3)。
  match
    cull_union_cell(
      "cell",
      color,
      [{ ..fold_test_binding(@abi.Invoke({ name: "default", args: [] })) }],
      registry,
      default_fall=Some(
        @abi.Array([@abi.Number(1.0), @abi.Number(2.0), @abi.Number(3.0)]),
      ),
    ) {
    Winner(candidate) => assert_eq(candidate.variant_index, 0)
    _ => abort("expected the declared default to seat the tuple branch")
  }

  // 書き込み自体の失敗は淘汰と別位相 — 未登録 cell fn は沈黙せず書き込み時に裁く (§6)。
  match
    cull_union_cell(
      "cell",
      color,
      [
        {
          ..fold_test_binding(@abi.Invoke({ name: "not-registered", args: [] }))
        },
      ],
      registry,
    ) {
    WriteFailed(reason, _, _) => assert_eq(reason, "unknown-vocab")
    _ => abort("expected an unregistered cell fn to surface as a write failure")
  }
}

///|
/// 保証 (DR-138 §6b、UC-Q4): union 宣言セルへの cell fn は特別扱いしない。
///
/// 1. **発火ごとに 1 回だけ実行**する — 枝ごとの再実行をしない (DR-114 の一回実行不変条件)。
///    純粋な fn だと観測値が同じになるため conformance では検出できない性質なので、
///    実行回数そのものを数える resident でここに固定する。
/// 2. **`ctx.old` はその時点のセルの観測値** — 逐次 淘汰 + 後勝ちの勝ち値で常に一意、
///    成立値が無ければ null。枝別の old は fn に見せない。
/// 3. 産出 Value は通常の書き込みとして**適合枝へ並行着地**する。
test "cull_union_cell: cell fn は発火ごとに 1 回実行し old は時点観測値 (DR-138 §6b)" {
  let calls : Array[@abi.Value?] = []
  let registry = fold_test_registry()
  // 呼ばれるたびに ctx.old を記録し、old+1 (old が無ければ 0) を返す観測用 resident。
  guard registry.register_cell_fn(
      @extension.cell_fn_descriptor(
        "test/count-old",
        [],
        @extension.CellFnOutput::Value,
        @extension.Total,
        observes=["old"],
        run=fn(_args, ctx) {
          let old = ctx.old()
          calls.push(old)
          let next = match old {
            Some(@abi.Number(n)) => n + 1.0
            _ => 0.0
          }
          Ok(@extension.FnOutput::Value(@abi.Number(next)))
        },
      ),
    )
    is Ok(_) else {
    abort("duplicate test/count-old cell fn")
  }
  // [number, string] の union — 枝が 2 つあるので、枝ごと再実行なら 1 発火で 2 回走る。
  let members : Array[@abi.ValueType] = [
    @abi.ValueType::Number,
    @abi.ValueType::String,
  ]
  let invoke = {
    ..fold_test_binding(@abi.Invoke({ name: "test/count-old", args: [] })),
    at_pos: Some(1),
  }
  match cull_union_cell("cell", members, [invoke], registry) {
    Winner(candidate) => assert_eq(candidate.value, @abi.Number(0.0))
    _ => abort("expected the fn output to seat the number branch")
  }
  // 1 発火 = 1 回実行 (枝数 2 でも 2 回にならない)。
  assert_eq(calls.length(), 1)
  // 着地前の時点観測値は null (成立値なし)。
  assert_eq(calls[0], None)

  // 逐次: set(5) の後に発火すると old は 5 (number 枝が後勝ちの勝ち値)、産出は 6。
  calls.clear()
  let set5 = {
    ..@abi.Binding::new("cell", @abi.Number(5.0), @abi.Cli, at_pos=Some(1)),
    op: @abi.Set,
  }
  let bump = {
    ..fold_test_binding(@abi.Invoke({ name: "test/count-old", args: [] })),
    at_pos: Some(2),
  }
  match cull_union_cell("cell", members, [set5, bump], registry) {
    Winner(candidate) => assert_eq(candidate.value, @abi.Number(6.0))
    _ => abort("expected the incremented value to win")
  }
  assert_eq(calls.length(), 1)
  assert_eq(calls[0], Some(@abi.Number(5.0)))

  // DR-138 §6: 書き込み自体の失敗は淘汰に吸わせず書き込み時に裁く。fn 本体の失敗は
  // 単相セルと同じ Error 観測になる (union に入れた途端に黙って消える非対称を作らない)。
  match
    cull_union_cell(
      "cell",
      members,
      [
        {
          ..fold_test_binding(@abi.Invoke({ name: "test/fail-run", args: [] })),
          at_pos: Some(1),
        },
      ],
      registry,
    ) {
    WriteFailed(reason, _, pos) => {
      assert_eq(reason, "test-failure")
      assert_eq(pos, 1)
    }
    _ => abort("a failing cell fn must surface as a write-time failure")
  }
}

///|
/// argv 位置を持たない書き込み (値源ラダー / 宣言 default 由来など、`at_pos` が `None`) 用。
fn cull_test_write_unpositioned(
  value : @abi.Value,
  residual : Array[@abi.ObservationSegment],
) -> @abi.Binding {
  {
    ..@abi.Binding::new("cell", value, @abi.Cli),
    op: @abi.Set,
    value_residual: residual,
  }
}

///|
/// 保証 (DR-138 §4 の args_pos 帰属): 「当該セルに着地した書き込みのうち **argv 位置最深**の
/// ものの operand 位置。argv 位置を持たない書き込みしか無い場合は消費位置 (DR-127 §4.2)」。
/// 後者を呼び出し側が実現できるよう、`at_pos` を持たない書き込みは最深位置の計算に参加せず、
/// 全部が位置なしなら `Incomplete(-1)` (= argv 位置なし) を返す。旧実装は `None` を `0` に
/// 読み替えていたため、(a) 位置なしの書き込みが argv 先頭を指し、(b) 呼び出し側の
/// 「消費位置へ落とす」フォールバックが構造的に到達不能な死枝になっていた。
test "cull_union_cell: 位置なし書き込みは最深位置に参加しない (DR-138 §4 / DR-127 §4.2)" {
  let registry = fold_test_registry()
  let color : Array[@abi.ValueType] = [
    @abi.ValueType::Tuple(["int", "int", "int"]),
    @abi.ValueType::String,
  ]

  // 位置なしの書き込みだけ → 生存ゼロ、かつ argv 位置は無い (-1)。
  let unpositioned = cull_union_cell(
    "cell",
    color,
    [
      cull_test_write_unpositioned(@abi.Number(0.0), [@abi.ObservationIndex(0)]),
      cull_test_write_unpositioned(
        @abi.Number(255.0),
        [@abi.ObservationIndex(1)],
      ),
    ],
    registry,
  )
  assert_true(unpositioned is Incomplete(-1))

  // 位置つきが 1 つでもあれば、その最深位置が勝つ (位置なしは 0 として混ざらない)。
  let mixed = cull_union_cell(
    "cell",
    color,
    [
      cull_test_write(@abi.Number(0.0), [@abi.ObservationIndex(0)], 3),
      cull_test_write_unpositioned(
        @abi.Number(255.0),
        [@abi.ObservationIndex(1)],
      ),
    ],
    registry,
  )
  assert_true(mixed is Incomplete(3))
}

///|
/// 保証 (DR-138 §6 / §2 の別位相): union 宣言セルの **値残余座**への書き込みでも、
///
/// - **fn が実行されて失敗した**のは書き込み自体の失敗 → `WriteFailed` で書き込み時に裁く。
///   丸ごと書き経路が同じ綴りを WriteFailed にするのと同一観測でなければならず、union に
///   入れた途端に黙って消える非対称を作らない (旧実装はここだけ黙殺していた)
/// - **SeatFault** (座がその枝の宣言形に無い) は型非適合と同じ「当該枝へ着地しないだけ」
///   (§2 — 非適合は Reject も Error も出さない) なので、黙って落とすのが正しい。
///   両者を混同すると枝選別そのものが失敗に化ける
test "cull_union_cell: 値残余座でも fn の失敗は WriteFailed、SeatFault は非着地 (DR-138 §6/§2)" {
  let registry = fold_test_registry()
  let color : Array[@abi.ValueType] = [
    @abi.ValueType::Tuple(["int", "int", "int"]),
    @abi.ValueType::String,
  ]

  // 値残余座への Invoke で fn が Reject → 淘汰に吸わせず WriteFailed。
  match
    cull_union_cell(
      "cell",
      color,
      [
        {
          ..fold_test_binding(@abi.Invoke({ name: "test/fail-run", args: [] })),
          value_residual: [@abi.ObservationIndex(0)],
        },
      ],
      registry,
    ) {
    WriteFailed(reason, _, _) => assert_eq(reason, "test-failure")
    _ =>
      abort("expected a failing cell fn on a value-space seat to surface as a write failure")
  }

  // string 枝には index 座が無い (SeatFault) が、それは非着地であって失敗ではない —
  // tuple 枝だけが着地し、未完成なので Incomplete に落ちる (WriteFailed にはならない)。
  assert_true(
    cull_union_cell(
      "cell",
      color,
      [cull_test_write(@abi.Number(0.0), [@abi.ObservationIndex(0)], 2)],
      registry,
    )
    is Incomplete(2),
  )
}
