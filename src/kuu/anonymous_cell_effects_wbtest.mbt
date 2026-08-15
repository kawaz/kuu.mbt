// anonymous_cell_effects_wbtest.mbt — 匿名 leaf (= 結果キー軸へ自分の綴りを供給しない子) の
// value binding が立てる `key = ""` の鍵空間を、effects 射影の側から固定する層。
//
// この空キーは `is_sentinel` が構造 sentinel (`[]` / `{}`) と共有する鍵空間で、gate を素通し
// させると seq の配列要素まで effects へ漏れ、落とすと匿名 scalar template への `ref` の効果が
// 消える (issue `kawaz/kuu` docs/issue/2026-08-16-ref-anonymous-template-effects-binding.md)。
// 分かれ目は **値がセルそのものに着地したか、セルの値の内部の要素座に着地したか** で、
// binding の scope 末尾が index segment (`#0`) かどうかがその判別子になる。
//
// fixtures 側の対応面: `name-surface/ref-id-axis-lookup.json` (ref)、
// `or-parse/option-anonymous-branches-value.json` (or 枝)、
// `seq-parse/option-anonymous-children-array.json` /
// `multiple-parse/nameless-seq-sources.json` (seq の配列要素 = effects 不在)。

///|
/// 保証: `ref` で匿名 scalar template を継承した option は、**そのセル自身**への set として
/// effects に現れる。要素の綴りは id 軸 (`box-width` → `box_width`) — binding の scope segment
/// が既に写像後の綴りを持つので、effects の entity も result のキーと同じ綴りで並ぶ。
///
/// **この test が pin する退行**: 匿名 leaf の binding key が `""` になることで
/// `project_effects` の sentinel gate が構造 sentinel と一緒に落とし、値は `result` に出るのに
/// effects が空になる (元 bug の姿)。
test "front_door.output: 匿名 scalar template への ref はセル自身への set として effects に現れる" {
  let src =
    #|{"definitions":{"templates":{"size-tmpl":{"type":"number"}}},
    #| "options":[{"name":"box-width","ref":"size-tmpl","long":true},
    #|  {"name":"mirror-name","ref":"box-width","long":true},
    #|  {"name":"mirror-id","ref":"box_width","long":true}]}
  assert_eq(
    wbtest_view_of(src, [
      "--box-width", "12", "--mirror-name", "34", "--mirror-id", "56",
    ]),
    "result={box_width=12,mirror_id=56,mirror_name=34} sources={box_width=cli,mirror_id=cli,mirror_name=cli} effects=box_width,mirror_id,mirror_name",
  )
}

///|
/// 対照 (上の裏面): 記号を含まない = id 軸の写像が効かない最小形でも同じ。写像は entity の
/// 綴りにしか効かず、effects に現れること自体は ref の構造継承だけで決まる。
test "front_door.output: 匿名 template ref の effects 出現は id 写像に依存しない" {
  let src =
    #|{"definitions":{"templates":{"sizetmpl":{"type":"number"}}},
    #| "options":[{"name":"boxwidth","ref":"sizetmpl","long":true}]}
  assert_eq(
    wbtest_view_of(src, ["--boxwidth", "12"]),
    "result={boxwidth=12} sources={boxwidth=cli} effects=boxwidth",
  )
}

///|
/// 保証 (DESIGN §5.1「or の値 = 選ばれた子の値」): 匿名枝が選ばれたとき、値は **親のセル**に
/// 着地する — 枝ノードが結果キーを持たないことと、セルへの op が無いことは別。`--level 5` は
/// 現に `level` のセルへ set しているので、DR-045 の entity 単位 op 列にその綴りで現れる。
/// binding の姿 (`key="" scope=[level]`) は匿名 template ref と同一で、両者を区別する材料は
/// binding に無い。
test "front_door.output: or の匿名枝はセル自身への set として effects に現れる (DESIGN §5.1)" {
  let src =
    #|{"options":[{"name":"level","long":true,"or":[
    #|  {"type":"int"},{"type":"bool"}]},
    #| {"name":"verbose","type":"flag","long":true}]}
  assert_eq(
    wbtest_view_of(src, ["--level", "5", "--verbose"]),
    "result={level=5,verbose=true} sources={level=cli,verbose=cli} effects=level,verbose",
  )
}

///|
/// 対極 (**この鍵空間で effects に出てはいけない側**): `seq` の匿名子が並ぶ配列では、値は
/// `pair` の**値の内部**の要素座 (`pair[0]` / `pair[1]`) に着地するのであってセル `pair` への
/// op ではない。binding の scope は `[pair, "#0"]` と index segment で終わり、ここが上の 2 面
/// との判別子になる。
///
/// **この test が pin する退行**: 空キーを一律に「スコープ自身のセル」へ読み替えると、配列の
/// 各要素が `pair` への set として effects に重複して現れる (`--pair x y` で effects=pair,pair)。
test "front_door.output: seq の匿名子は要素座への着地なので effects に現れない" {
  let src =
    #|{"options":[{"name":"pair","long":true,"seq":[
    #|  {"type":"string"},{"type":"string"}]}]}
  assert_eq(
    wbtest_view_of(src, ["--pair", "x", "y"]),
    "result={pair=[x,y]} sources={pair=[cli,cli]} effects=",
  )
}

///|
/// 対極の続き: `multiple` の row も同じ (`fixtures/multiple-parse/nameless-seq-sources.json` が
/// `effects: []` で pin している面)。発火が 2 回に増えても row が積まれるだけで、セル
/// `pair` への op は生まれない。
test "front_door.output: nameless seq accumulator の row は effects に現れない" {
  let src =
    #|{"options":[{"name":"pair","long":true,"multiple":"append","seq":[
    #|  {"type":"string"},{"type":"string"}]}]}
  assert_eq(
    wbtest_view_of(src, ["--pair", "a", "b"]),
    "result={pair=[[a,b]]} sources={pair=[[cli,cli]]} effects=",
  )
  assert_eq(
    wbtest_view_of(src, ["--pair", "a", "b", "--pair", "c", "d"]),
    "result={pair=[[a,b],[c,d]]} sources={pair=[[cli,cli],[cli,cli]]} effects=",
  )
}

///|
/// 名前付き leaf との対照: 子が結果キーを持つ場合は従来どおり自分の綴りで effects に立ち、
/// 空キー経路を通らない。`export_key` による rename は effects の綴りに効かない (effects の
/// entity は宣言名軸、`result` / `sources` は露出キー軸) — 匿名 leaf 側で scope segment の
/// 綴りを採ることがこの軸と食い違わないことの確認を兼ねる。
test "front_door.output: 名前付き leaf は宣言名軸で effects に立つ (export_key rename は効かない)" {
  let src =
    #|{"options":[{"name":"a","type":"number","long":true,"export_key":"zz"}]}
  assert_eq(
    wbtest_view_of(src, ["--a", "3"]),
    "result={zz=3} sources={zz=cli} effects=a",
  )
}
