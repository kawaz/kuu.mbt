// cell_fold_wbtest.mbt — 効果適用 fold の一本化が守る不変条件を公開 API 経由で固定する:
// **同じ効果列に対し effects の operand と result の値が一致する**。従来 effects 射影と
// CLI seat 解決が独立に畳んでいて、`ctx.old` (DR-114 §7) の供給が 4 通りずれていた
// (`docs/findings/2026-08-02-w2-4-fold-unification.md` の差異表)。conformance は両方を pin
// するが、両方が同時に間違うと検出できないので、ここで「両者が一致すること」自体を固定する。
// 座への部分更新 API の単体 pin は共有 fold の住処 `src/internal/fold/cell_fold_wbtest.mbt`。

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
