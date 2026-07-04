// phase24_wbtest.mbt — 第 14 弾: parse_definition の失敗挙動 (DR-054)。返値は 2 値 union
// (Ok(atomic) | Err([{element, kind, message, hint}])), エラーは全列挙 (first-error 打ち切りしない)。
// 境界: lowering が構成できない / 全入力で壊れる = Error (parse_definition 失敗)。一部入力で驚きうる
// だけ = warn (lint の関心、PoC 射程外、実装しない)。hint は「次の手」型 (DR-042 完全性検査の様式)。

// ── 全列挙: 複数の独立エラーが 1 回で返る (DR-054 §4) ────────────────────────────

test "DR-054: multiple independent errors are ALL returned in one parse_definition (全列挙)" {
  // An absent ref (`missing`) AND a zero-progress repeat (`loop` → a 0-token Bind template). Both
  // surface in a single call — no first-error 打ち切り (コンパイラの定石).
  let def = def_(
    [],
    [
      pos("x", TStr, ref_=Some("missing")), // absent ref
      pos("loop", TStr, ref_=Some("noprog"), repeat=rep(1)), // zero-progress head
    ],
  )
  let reg : Map[String, Node] = Map::new()
  reg.set("noprog", Bind("b", VBool(true))) // a 0-token head (no consumption)
  match parse_definition(def, [RepeatInst], registry=reg) {
    Err(errs) => inspect(deferrs_str(errs), content="loop/zero-progress,x/absent-ref")
    Ok(_) => abort("expected multiple errors")
  }
}

// ── 未知の特殊語彙 + hint (DR-042①) ────────────────────────────────────────────

test "DR-054: an unknown special vocab is an Error with a 「次の手」hint" {
  // env:PORT used but EnvInst absent → unknown-vocab, and the hint names the fix (register the owner).
  let def = def_([opt("port", TNum, long=["port"], env=["PORT"])], [])
  match parse_definition(def, [LongInst]) {
    Err(errs) => {
      inspect(deferrs_str(errs), content="port/unknown-vocab")
      inspect(
        hint_of(errs, "port"),
        content="register an installer owning 'env:PORT' in the chain (§13.5)",
      )
    }
    Ok(_) => abort("expected unknown-vocab error")
  }
}

// ── 不正な値域: repeat min > max (DR-052) ──────────────────────────────────────

test "DR-054: repeat min > max is an invalid-range Error (with hint)" {
  // A range that cannot describe any cardinality — the lowering is malformed → Error.
  let def = def_([], [pos("f", TStr, repeat=rep(3, max=Some(1)))]) // min 3 > max 1
  match parse_definition(def, [RepeatInst]) {
    Err(errs) => {
      inspect(deferrs_str(errs), content="f/invalid-range")
      inspect(hint_of(errs, "f"), content="set the repeat max >= min")
    }
    Ok(_) => abort("expected invalid-range error")
  }
}

// ── 不在の ref / link (DR-032) ─────────────────────────────────────────────────

test "DR-054: a ref target defined nowhere is an absent-ref Error (with hint)" {
  // `x` refs `nope`, which exists in neither the scope nor definitions → the ref cannot resolve.
  let def = def_([], [pos("x", TStr, ref_=Some("nope"))])
  let reg : Map[String, Node] = Map::new()
  match parse_definition(def, [RepeatInst], registry=reg) {
    Err(errs) => {
      inspect(deferrs_str(errs), content="x/absent-ref")
      inspect(
        hint_of(errs, "x"),
        content="define 'nope' as a template (definitions) or in the scope",
      )
    }
    Ok(_) => abort("expected absent-ref error")
  }
}

// ── 循環 ref vs repeat の正当な自己 ref (DR-007/032 vs DR-043) ───────────────────

test "DR-054: a circular ref is an Error; a repeat's legitimate self-ref is NOT (ゼロ進捗ガードとの区別)" {
  // A circular ref: `bad` refs itself in HEAD position (nothing consumed before recursing) → infinite
  // structural expansion → circular-ref Error.
  let def_bad = def_([], [pos("x", TStr, ref_=Some("bad"))])
  let reg_bad : Map[String, Node] = Map::new()
  reg_bad.set("bad", Seq([Ref("bad")])) // head-position self-ref
  match parse_definition(def_bad, [RepeatInst], registry=reg_bad) {
    Err(errs) => inspect(deferrs_str(errs), content="bad/circular-ref")
    Ok(_) => abort("expected circular-ref error")
  }
  // CONTRAST: a plain repeat's self-ref lowers to `Seq([head, Opt(Ref(self))])` — the head is a
  // CONSUMING node, so the self-ref is NOT in head position → NOT circular. It builds and runs fine.
  // This is the distinction the zero-progress guard already draws (head must consume before recursing).
  let def_ok = def_([], [pos("f", TStr, repeat=rep(1))])
  let reg_ok : Map[String, Node] = Map::new()
  let sc = build_reg(def_ok, [RepeatInst], reg_ok) // no error → builds
  inspect(result_str(sc, ["a", "b"], defs=reg_ok), content="{f:[a,b]}") // and works
}
