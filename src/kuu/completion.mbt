// completion.mbt — DR-117 completion capabilities: script generation seat / preset firing
// detection / query-mode entry gate (env × argv 二箇所一致).
//
// 座席の分割線は findings 2026-07-23-completion-ux-layer-plan §1.2 (UXL-Q1=a 裁定) — script
// generation とパイプライン (行指向応答 emit まで) は本 package (kuu.mbt) が実装する。
// パイプライン本体は `completion_query` (completion_query.mbt、M1)、玄関判定と script 焼き込み
// は本ファイル (M3)。glue テンプレは spec `templates/` の正本を M2 転写機構
// (scripts/gen-completion-templates.sh) が `completion_templates.mbt` の String 定数に
// 落とし、`generate_completion_script()` が呼び出し時に literal 置換する (DR-117 §2.5)。

///|
/// Registry carrier for the `completion_script` capability. Script generation itself is provided
/// by `generate_completion_script()` in this file (findings §1.3 — the earlier comment claiming
/// script implementation belongs to the UX/product layer is superseded by UXL-Q1=a).
pub struct CompletionScriptCapability {}

///|
pub impl @engine.CapabilityExt for CompletionScriptCapability with fn name(
  _self,
) {
  "completion_script"
}

///|
pub fn completion_script_capability() -> &@engine.CapabilityExt {
  CompletionScriptCapability::{  } as &@engine.CapabilityExt
}

///|
/// Result of checking the completion_script orchestration seat after parsing and resolution.
pub(all) enum CompletionScriptRequest {
  Requested(String)
  NotRequested
  Unavailable
} derive(Eq, Debug)

///|
/// Confirm the capability is registered, then read the definition-wide internal cell populated by
/// the completion_script preset. Script generation itself is intentionally not invoked here — the
/// orchestrating caller reads the requested shell out of this result and calls
/// `generate_completion_script()` to obtain the emitted glue text.
pub fn dispatch_completion_script(
  registry : @engine.Registry,
  outcome : @engine.Outcome,
) -> CompletionScriptRequest {
  if registry.lookup_capability("completion_script") is None {
    return Unavailable
  }
  guard outcome is @engine.Success(bindings) else { return NotRequested }
  let mut requested : String? = None
  for binding in bindings {
    if binding.key == "#completion_script" && binding.op is @engine.Set {
      match binding.value {
        @engine.String(shell) => requested = Some(shell)
        _ => ()
      }
    }
  }
  match requested {
    Some(shell) => Requested(shell)
    None => NotRequested
  }
}

// ── M3: 玄関判定 (env × argv 二箇所一致) ──────────────────────────────────────

///|
/// `completion_entry` の判定結果 (findings §3.2 UXL-Q3=a シグネチャ輪郭)。
///
/// - `NotCompletion`: env `KUU_COMPLETE` 不在、または argv[1] との不一致 (env 未設定時と観測等価。
///   DR-117 §3.2)。呼び出し側は補完でない通常実行を続ける。判定関数は stdout/stderr/exit のどれにも
///   触れないため、一様性 (§3.2) を構造的に満たす
/// - `Respond(String)`: 二箇所一致 = query モード成立。呼び出し側は返却行応答テキストを stdout に
///   出して exit 0 する (DR-117 §3.5 stdout 純度規約)
pub(all) enum CompletionEntryResult {
  NotCompletion
  Respond(String)
} derive(Eq, Debug)

///|
/// DR-117 §3.1 の玄関判定 (env × argv[1] 二箇所一致) + 成立時の query 実行を一体で行う純関数
/// (findings §3.2 UXL-Q3=a: 分けて公開すると誤用面が開くため一体型)。
///
/// 引数 (`front_door.parse()` の env / config 注入と同じ流儀 — プロセス env / argv を読むのは
/// 呼び出し側の責務):
/// - `ast`: 補完対象アプリの definition (parse_definition で lower 済み)
/// - `registry`: `canonical_registry()` (or 拡張 registry)。help_query capability の lookup 経路
/// - `argv`: プロセス argv 全量 (`argv[0]` = 自身、`argv[1]` = UUID、`argv[2]` = shell 名、
///   `argv[3..]` = words)。glue テンプレは形態 A (env プロトコル) でこの配列を組む
/// - `env`: プロセス環境 map。少なくとも `KUU_COMPLETE` と `KUU_COMPLETE_INDEX` を参照する
///
/// 挙動:
/// - env `KUU_COMPLETE` が無い / argv 長が 2 未満 / `argv[1]` が UUID と不一致 → `NotCompletion`。
///   このうち argv 長 < 2 は「glue が env は付けたが argv[1] を積み忘れた」等の異常系だが、DR-117
///   §3.2 の一様性 (不一致 = env 未設定と観測等価) に従い黙って `NotCompletion` に倒す
/// - 一致 (query モード) 時: `argv[2..]` を words 列 (先頭 = shell 名。DR-117 §3.6 で shell 名は
///   現状ヒント扱いのため completion_query には渡さない) とし、`argv[3..]` を実 words として渡す。
///   `argv` 長が 3 未満で shell 名も無い場合は空 words で `completion_query` を呼ぶ (空 words は
///   `completion_query` 冒頭で空応答に縮退)
/// - `KUU_COMPLETE_INDEX` は正整数だけ受理 (負値・数値外・欠損 → None)。`completion_query` は
///   受け取った cword を範囲チェックし、範囲外なら行末補完に縮退する (§3.3、DR-117)。
///   縮退時 stderr 警告は出さない (findings §7 リスク — library が stderr を持たない設計)
pub fn completion_entry(
  ast : AtomicAST,
  registry : @engine.Registry,
  argv : Array[String],
  env : Map[String, String],
) -> CompletionEntryResult {
  // env × argv 二箇所一致 (DR-117 §3.1)
  let uuid = match env.get("KUU_COMPLETE") {
    Some(s) => s
    None => return NotCompletion
  }
  if argv.length() < 2 {
    return NotCompletion
  }
  if argv[1] != uuid {
    return NotCompletion
  }
  // query モード成立 — words / cword 抽出
  // argv[2] = shell 名 (現状ヒント扱い、渡さない)、argv[3..] = words 実体 (DR-117 §3.4 の全量形)
  let words : Array[String] = []
  for i = 3; i < argv.length(); i = i + 1 {
    words.push(argv[i])
  }
  // KUU_COMPLETE_INDEX (§3.3): 正整数のみ受理。負値・数値外・欠損 → None (行末補完縮退へ倒す)
  let cword = match env.get("KUU_COMPLETE_INDEX") {
    Some(s) => parse_nonneg_int(s)
    None => None
  }
  Respond(completion_query(ast, registry, words, cword~))
}

///|
/// KUU_COMPLETE_INDEX 用の narrow 整数 parser。ASCII 数字 1 文字以上のみ受理して非負 Int を返す。
/// 空文字列 / 数字以外を含む / overflow (Int の範囲を越える) は None を返す。
///
/// standalone に書く理由: `moonbitlang/core/strconv` は kuu package の import に含まれておらず、
/// 補完 index 1 箇所のためだけに import を広げるより素の関数の方が影響範囲が小さい (現行 kuu で
/// も `resolve.mbt` 内で `c.to_int() - '0'.to_int()` 手書きの前例あり)。
fn parse_nonneg_int(s : String) -> Int? {
  let arr = s.to_array()
  if arr.length() == 0 {
    return None
  }
  let mut acc : Int = 0
  for ch in arr {
    let code = ch.to_int()
    if code < '0'.to_int() || code > '9'.to_int() {
      return None
    }
    let d = code - '0'.to_int()
    // Int overflow guard — (Int.max - d) / 10 = 214748364 で十分安全
    if acc > 214748364 {
      return None
    }
    acc = acc * 10 + d
  }
  Some(acc)
}

// ── M3: `generate_completion_script` — glue テンプレへの literal 置換 ─────────

///|
/// `generate_completion_script` の失敗種別。v1 は未対応 shell のみ (findings §3.2 末尾)。
pub(all) enum CompletionScriptError {
  UnsupportedShell(String)
} derive(Eq, Debug)

///|
/// DR-117 §2.5 の焼き込み 3 点 (binary 参照 / program_name / UUID) をテンプレへ literal 置換する。
///
/// 引数:
/// - `shell`: `"zsh"` / `"bash"` / `"fish"` の 1 つ。他は `UnsupportedShell(shell)` エラー
/// - `program_name`: 補完対象コマンド名 (`compdef` / `complete -F` / `complete -c` が要求する
///   値)。既定は definition ルートの `name` (呼び出し側で上書き可、DR-117 §2.5)
/// - `binary`: 問い合わせ先バイナリの参照 (絶対パス or 素の名前 — 生成側の関心。findings §3.2)
/// - `uuid`: env × argv 二箇所一致トークン (DR-117 §3.1)。生成時 1 回採番、呼び出し側で乱数注入
///   (findings §3.2 — library は乱数を持たない)
///
/// 置換の順序と原則:
/// - 置換順は `{{BINARY}}` → `{{PROGRAM_NAME}}` → `{{UUID}}` (順序自体は安全であって意味を持たない
///   — 各 template 変数の値には `{{...}}` を含めない責務が呼び出し側にあるため、順序に依らず
///   結果は決定的。順序を固定するのは決定性ではなく可読性のため)
/// - literal 置換のみ (regex / interpolation 無し) — テンプレの `${...}` (shell 変数) は
///   `{{...}}` と衝突しないため誤置換しない (findings §2 UXL-Q2=a、README 記法)
pub fn generate_completion_script(
  shell : String,
  program_name : String,
  binary : String,
  uuid : String,
) -> Result[String, CompletionScriptError] {
  let template = if shell == "zsh" {
    completion_template_zsh()
  } else if shell == "bash" {
    completion_template_bash()
  } else if shell == "fish" {
    completion_template_fish()
  } else {
    return Err(UnsupportedShell(shell))
  }
  let s = template
    .replace_all(old="{{BINARY}}", new=binary)
    .replace_all(old="{{PROGRAM_NAME}}", new=program_name)
    .replace_all(old="{{UUID}}", new=uuid)
  Ok(s)
}
