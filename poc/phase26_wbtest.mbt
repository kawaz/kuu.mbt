// phase26_wbtest.mbt — 第 16 弾: alias (DR-057) — 参照ファミリー 3 人目 (ref/link/alias)。独立要素で書く
// 別入口。意味論は link + 表示帰属: 効果は canonical 実体セルへ (entry-copy が canonical の name で bind)、
// 結果キーは canonical のみ。継承原理 (§3): name 導出入口 (long 配列の base + variant DSL、command の name
// 照合) は alias の name で再導出、明示綴り (short) は非継承。値源・結果キー・制約は実体側のまま。alias
// installer は宣言的コピー (global 同型); 入口展開は long/short/command installer が担う。hidden/deprecated
// は DR-058 (deprecated alias は入口限定で ParserContext.warnings に積む)。

fn p26_order() -> Array[Installer] {
  [
    LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst,
    RepeatInst, MultipleInst, ConfigInst, ConstraintInst, AliasInst,
  ]
}

/// The ShortCombine cluster entries of a built scope, as sorted `ch=name` (with `!` for a deprecated
/// entry). Used to show short 非継承 (no duplicate canonical short) and the deprecated flag placement.
fn short_str(sc : Scope) -> String {
  let items : Array[String] = []
  for g in sc.greedy {
    match g {
      NativeMatch(ShortCombine(prefix=_, entries~)) =>
        for e in entries {
          items.push("\{e.ch}=\{e.name}" + (if e.depr { "!" } else { "" }))
        }
      _ => ()
    }
  }
  sort_items(items)
  join_comma(items)
}

// ── 1. short alias: 別入口が canonical セルに束縛、結果キーは canonical のみ ──────

test "DR-057 §1/§2: a short alias binds the canonical cell; the result key stays canonical; あと勝ち" {
  // canonical `port` (short -p) + an alias `{alias:"port", short:"n"}` → -n is a SECOND entry into the
  // one `port` cell (link 同型). The entry-copy keys by the canonical name, so both the effect and the
  // result key are `port` — the alias makes no result scope of its own (§2). -p and -n on the same cell
  // are last-wins (DR-015).
  let def = def_(
    [opt("port", TNum, short=['p'])],
    [],
    aliases=[alias("port", short=['n'])],
  )
  let sc = build_or_fail(def, p26_order())
  inspect(result_str(sc, ["-n", "80"]), content="{port:80}") // -n → port セル、結果キー port
  inspect(result_str(sc, ["-p", "80"]), content="{port:80}") // canonical も同じセル
  inspect(result_str(sc, ["-p", "80", "-n", "90"]), content="{port:90}") // 同一セルあと勝ち (DR-015)
}

// ── 2. long alias + variant 再導出 (本命) ───────────────────────────────────────

test "DR-057 §3: a long alias re-derives the name-derived base AND its variant under the new name" {
  // canonical `ssl` (bool, default true) with a `--no-ssl` SET-false variant. Alias `{alias:"ssl",
  // name:"tls"}` → the name-derived base (--ssl) re-derives to --tls, and the variant (name-derived:
  // its trigger contains "ssl") re-derives to --no-tls. So --tls AND --no-tls both work, both hitting
  // the `ssl` cell; --no-tls sets ssl=false. The canonical spellings still work too.
  let def = def_(
    [
      opt(
        "ssl",
        TFlag,
        long=["ssl"],
        default=Some(VBool(true)),
        variants=[{ trigger: "no-ssl", op: Set, operand: Some(VBool(false)) }],
      ),
    ],
    [],
    aliases=[alias("ssl", name=Some("tls"))],
  )
  let sc = build_or_fail(def, p26_order())
  inspect(result_str(sc, ["--tls"]), content="{ssl:true}") // base 再導出: --tls → ssl (canonical key)
  inspect(result_str(sc, ["--no-tls"]), content="{ssl:false}") // variant 再導出: --no-tls → ssl=false
  inspect(result_str(sc, ["--ssl"]), content="{ssl:true}") // canonical base も不変
  inspect(result_str(sc, ["--no-ssl"]), content="{ssl:false}") // canonical variant も不変
}

// ── 3. long:[] 明示上書き → variant が切れる (差分上書き, DR-007) ─────────────────

test "DR-057 §3: an explicit long:[] override cuts the inherited variant (only the bare --tls remains)" {
  // Same canonical `ssl`. Alias `{alias:"ssl", name:"tls", long:[]}` → the explicit long override
  // (差分上書き) cuts the inherited variant, so --no-tls is NOT generated. The base --tls still comes
  // from the alias name (素の --tls のみ). --no-tls therefore does not resolve.
  let def = def_(
    [
      opt(
        "ssl",
        TFlag,
        long=["ssl"],
        default=Some(VBool(true)),
        variants=[{ trigger: "no-ssl", op: Set, operand: Some(VBool(false)) }],
      ),
    ],
    [],
    aliases=[alias("ssl", name=Some("tls"), long=Some([]))],
  )
  let sc = build_or_fail(def, p26_order())
  inspect(result_str(sc, ["--tls"]), content="{ssl:true}") // 素の --tls は残る (base は name 由来)
  // --no-tls は生成されない → 未定義トークンで完全経路なし (Failure、ssl=false にはならない)
  inspect(render_outcome(parse(ScopeNode(sc), ["--no-tls"])), content="fail:no complete parse")
  inspect(result_str(sc, ["--no-ssl"]), content="{ssl:false}") // canonical variant は不変
}

// ── 4. short 非継承: alias は canonical の short を継承しない ─────────────────────

test "DR-057 §3: short is NOT inherited — the alias does not re-generate the canonical short" {
  // canonical `ssl` declares its own short -s; the alias `tls` declares its own short -t. Because short
  // is an EXPLICIT spelling (§3 明示綴り非継承), the alias entry-copy does NOT inherit canonical's -s —
  // the cluster has exactly one `s` (canonical) + one `t` (alias), not a duplicated `s`. Both bind ssl.
  let def = def_(
    [opt("ssl", TFlag, long=["ssl"], short=['s'])],
    [],
    aliases=[alias("ssl", name=Some("tls"), short=['t'])],
  )
  let sc = build_or_fail(def, p26_order())
  inspect(short_str(sc), content="s=ssl,t=ssl") // 一つの s (継承なら s が二重に出る)
}

// ── 5. command alias: co → checkout 部分木、結果キーは checkout ───────────────────

test "DR-057 §2: a command alias enters the canonical subtree; the result key stays canonical" {
  // `checkout` is a command; alias `{alias:"checkout", type:command, name:"co"}` → `co` triggers the
  // checkout subtree (a clone body), and its export_key is EkKey("checkout") so the result nests under
  // `checkout`, not `co` (結果キーは canonical のみ, §2). `co --branch x` → {checkout:{branch:x}}.
  let def = def_cmd(
    [],
    [],
    [cmd("checkout", def_([opt("branch", TStr, long=["branch"])], []))],
    aliases=[alias("checkout", name=Some("co"))],
  )
  let sc = build_or_fail(def, p26_order())
  let ekm = build_export_map(def)
  inspect(
    export_result_str(sc, ekm, ["co", "--branch", "x"]),
    content="{checkout:{branch:x}}", // co で入るが結果キーは checkout
  )
  inspect(
    export_result_str(sc, ekm, ["checkout", "--branch", "y"]),
    content="{checkout:{branch:y}}", // canonical も同じ結果キー
  )
}

// ── 6. alias installer の順列一致 (不動点反復で入口 installer が展開) ─────────────

test "DR-057/DR-042: the alias-desugared lowering is identical regardless of installer order" {
  // The alias entry-copies are expanded by long/short in the fixpoint; the desugaring itself is
  // order-independent. Building with AliasInst early vs late (and the whole chain permuted) yields the
  // identical AtomicAST (canon_scope).
  let def = def_(
    [opt("ssl", TFlag, long=["ssl"], short=['s'], variants=[{ trigger: "no-ssl", op: Set, operand: Some(VBool(false)) }])],
    [],
    aliases=[alias("ssl", name=Some("tls"), short=['t'])],
  )
  let early = canon_scope(build_or_fail(def, [AliasInst, LongInst, ShortInst, EnvInst, DdInst, CommandInst, GlobalInst, InheritInst, RepeatInst, MultipleInst, ConfigInst, ConstraintInst]))
  let late = canon_scope(build_or_fail(def, p26_order()))
  inspect(early == late, content="true")
}

// ── 7. deprecated alias (DR-058): 受理 + ParserContext.warnings に構造化警告 ──────

test "DR-058: a deprecated alias is accepted and binds the canonical cell, adding a warning" {
  // canonical `port` (-p) + a normal alias -n + a DEPRECATED alias -o. All three bind `port`; only -o
  // adds a deprecation warning (DR-058: 受理不変 + warnings に {element, kind:deprecated}). -n / -p add
  // no warning. The warning's element is the canonical (`port`), the auto-derived "use port instead"素材.
  let def = def_(
    [opt("port", TNum, short=['p'])],
    [],
    aliases=[
      alias("port", short=['n']),
      alias("port", short=['o'], deprecated=true),
    ],
  )
  let sc = build_or_fail(def, p26_order())
  // -o: accepted, binds port, AND records a deprecation warning
  inspect(result_str(sc, ["-o", "80"]), content="{port:80}") // 受理 + 実体束縛
  inspect(warnings_str(parse(ScopeNode(sc), ["-o", "80"])), content="port") // warnings に積まれる
  // -n / -p: no warning
  inspect(warnings_str(parse(ScopeNode(sc), ["-n", "80"])), content="") // 非 deprecated alias
  inspect(warnings_str(parse(ScopeNode(sc), ["-p", "80"])), content="") // canonical
}

// ── 8. 実体側制約との噛み合い: alias 起動でも実体 committed が立ち制約が効く ────────

test "DR-057 §2/§3: a constraint on the canonical fires even when the alias entry triggers the commit" {
  // `decrypt requires key_file`. The alias -d is another entry into `decrypt` (§3: 制約は実体側のまま —
  // the alias does not carry the requires). Triggering -d commits the `decrypt` cell, so the canonical's
  // requires evaluates just as if --decrypt had fired: -d alone → violation; -d --key-file k → ok.
  let def = def_(
    [
      opt("decrypt", TFlag, long=["decrypt"], requires=["key_file"]),
      opt("key_file", TStr, long=["key-file"]),
    ],
    [],
    aliases=[alias("decrypt", short=['d'])],
  )
  let sc = build_or_fail(def, p26_order())
  inspect(errors_str(parse(ScopeNode(sc), ["-d"])), content="decrypt@1/constraint") // alias 起動でも制約が効く
  inspect(result_str(sc, ["-d", "--key-file", "k"]), content="{decrypt:true,key_file:k}") // 充足
}
