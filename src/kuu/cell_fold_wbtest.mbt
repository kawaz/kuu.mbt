// cell_fold_wbtest.mbt — 共有 fold (`cell_fold.mbt`) の 2 面を固定する。
//
// 1. 座への部分更新 API (`CellSeats::value_at` / `set_at`) の単体。DR-127 §2.2 の値空間降下が
//    使う唯一の入口で、vivify (DR-127 §3、W2-7) を足すときに挙動が変わる境界そのもの
// 2. 効果適用 fold の一本化が守る不変条件 — **同じ効果列に対し effects の operand と result の
//    値が一致する**。従来 effects 射影と CLI seat 解決が独立に畳んでいて、`ctx.old` (DR-114 §7)
//    の供給が 4 通りずれていた (`docs/findings/2026-08-02-w2-4-fold-unification.md` の差異表)。
//    conformance は両方を pin するが、両方が同時に間違うと検出できないので、ここで
//    「両者が一致すること」自体を固定する

///|
fn seat_read(
  seats : CellSeats,
  key : String,
  path : Array[@abi.ObservationSegment],
) -> String {
  match seats.value_at(key, path) {
    Ok(value) => test_render_val(value)
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
/// 保証 (DR-114 §7 / DR-081 §2 / DR-131 §2b/§7): effects 射影と CLI seat 解決が同じ fold を
/// 使うので、`ctx.old` に依存する cell fn (`incr`) の結果は effects の operand と result の値で
/// 一致する。3 行はいずれも一本化前に食い違っていた形 (差異表 F-1 / F-2 / F-4)。
test "効果 fold の一本化: ctx.old 依存の効果は effects と result で一致する (DR-114 §7)" {
  fn probe(src : String, args : Array[String]) -> String raise {
    let ast = match parse_definition(@json.parse(src)) {
      Ok(a) => a
      Err(_) => {
        fail("parse_definition failed")
        panic()
      }
    }
    let outcome = parse_legacy(ast, args)
    let parsed = match outcome {
      @engine.Success(binds) => binds
      other => {
        fail("parse should succeed, got " + render_outcome(other))
        panic()
      }
    }
    let resolved = match resolve_legacy(ast, outcome, args) {
      @engine.Success(binds) => binds
      other => {
        fail("resolve should succeed, got " + render_outcome(other))
        panic()
      }
    }
    let view = output_legacy(ast, effects=parsed, resolved~)
    let out = StringBuilder::new()
    for effect in view.effects {
      out.write_string(effect.entity)
      out.write_char(':')
      out.write_string(
        match effect.op {
          @abi.Set => "set"
          @abi.Empty => "empty"
          @abi.EffectOp::Default => "default"
          @abi.Unset => "unset"
          @abi.Invoke(_) => "invoke"
          @abi.Remove => "remove"
          @abi.Splice => "splice"
        },
      )
      out.write_char('(')
      out.write_string(
        match effect.operand {
          Some(value) => test_render_val(value)
          None => "-"
        },
      )
      out.write_string(") ")
    }
    out.write_string("| " + render_rval_sorted(view.result))
    out.to_string()
  }

  // F-1: subcommand scope 配下のセルでも、宣言 default が `old` になる。effects 射影が root の
  // entity しか引けなかった頃はここが `set(1)` (old absent → 0+1) で result の 6 とずれていた。
  assert_eq(
    probe(
      (
        #|{"commands": [{"name": "go", "options": [
        #|  {"name": "n", "type": "number", "default": 5, "long": [":incr"]}]}]}
      ),
      ["go", "--n"],
    ),
    "n:set(6) | {go={n=6}}",
  )

  // F-2: `unset` (null Value fn、DR-131 §2b) は席を開けるので、次の `old` は宣言 default へ戻る
  // — 座に null が居座って `incr` を型不一致で落とすのではない。
  assert_eq(
    probe(
      (
        #|{"options": [{"name": "n", "type": "number", "default": 5,
        #|  "long": [":incr", "clear:unset"]}]}
      ),
      ["--n", "--clear-n", "--n"],
    ),
    "n:set(6) n:set(null) n:set(6) | {n=6}",
  )

  // F-4: `default` (DR-081 §2) は書き換え済み default をセルへ書くので、次の `old` は
  // 直前の 6 ではなく default の 5 (→ 6)。
  assert_eq(
    probe(
      (
        #|{"options": [{"name": "n", "type": "number", "default": 5,
        #|  "long": [":incr", "reset:default"]}]}
      ),
      ["--n", "--reset-n", "--n"],
    ),
    "n:set(6) n:default(-) n:set(6) | {n=6}",
  )

  // 対照: 一本化前から一致していた形も動かない (セル別に座が分かれ、set は両者を同じに動かす)。
  assert_eq(
    probe(
      (
        #|{"options": [{"name": "n", "type": "number", "default": 5, "long": [":incr"]},
        #|             {"name": "m", "type": "number", "default": 7, "long": [":incr"]}]}
      ),
      ["--n", "--m", "--n"],
    ),
    "n:set(6) m:set(8) n:set(7) | {m=8,n=7}",
  )
}
