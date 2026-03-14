// mygit パーサのテスト
// node:test と node:assert を使用

import { describe, it, before } from "node:test";
import { strict as assert } from "node:assert";
import { loadKuu, type KuuResult, type KuuInput } from "./kuu-wasm.ts";
import { opts, description } from "./git-schema.ts";

// パース関数を保持する変数
let parse: (input: KuuInput) => KuuResult;

// WASM の読み込みは1回だけ
before(async () => {
  parse = await loadKuu();
});

/** スキーマ付きでパースするヘルパー */
function gitParse(args: string[]): KuuResult {
  return parse({ version: 1, description, opts, args });
}

describe("mygit parser", () => {
  // 1. clone
  it("clone https://github.com/foo/bar --depth 5 -b main", () => {
    const result = gitParse([
      "clone",
      "https://github.com/foo/bar",
      "--depth",
      "5",
      "-b",
      "main",
    ]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "clone");
    assert.equal(result.command?.values.url, "https://github.com/foo/bar");
    assert.equal(result.command?.values.depth, 5);
    assert.equal(result.command?.values.branch, "main");
  });

  // 2. commit
  it("commit -m 'fix bug' -a", () => {
    const result = gitParse(["commit", "-m", "fix bug", "-a"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "commit");
    assert.equal(result.command?.values.message, "fix bug");
    assert.equal(result.command?.values.all, true);
  });

  // 3. log
  it("log --oneline -n 10 --graph", () => {
    const result = gitParse(["log", "--oneline", "-n", "10", "--graph"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "log");
    assert.equal(result.command?.values.oneline, true);
    assert.equal(result.command?.values["max-count"], 10);
    assert.equal(result.command?.values.graph, true);
  });

  // 4. add
  it("add -f file1.txt file2.txt", () => {
    const result = gitParse(["add", "-f", "file1.txt", "file2.txt"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "add");
    assert.equal(result.command?.values.force, true);
    assert.deepEqual(result.command?.values.files, [
      "file1.txt",
      "file2.txt",
    ]);
  });

  // 5. push
  it("push origin main -u", () => {
    const result = gitParse(["push", "origin", "main", "-u"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "push");
    assert.equal(result.command?.values.remote, "origin");
    assert.deepEqual(result.command?.values.refspecs, ["main"]);
    assert.equal(result.command?.values["set-upstream"], true);
  });

  // 6. pull
  it("pull --rebase origin main", () => {
    const result = gitParse(["pull", "--rebase", "origin", "main"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "pull");
    assert.equal(result.command?.values.rebase, true);
    assert.equal(result.command?.values.remote, "origin");
    // "main" は rest の refspecs に入る
    assert.deepEqual(result.command?.values.refspecs, ["main"]);
  });

  // 7. branch
  it("branch -d feature/old", () => {
    const result = gitParse(["branch", "-d", "feature/old"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "branch");
    assert.equal(result.command?.values.delete, true);
    assert.equal(result.command?.values.name, "feature/old");
  });

  // 8. checkout
  it("checkout -b new-branch", () => {
    const result = gitParse(["checkout", "-b", "new-branch"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "checkout");
    assert.equal(result.command?.values.create, "new-branch");
  });

  // 9. diff
  it("diff --staged --stat", () => {
    const result = gitParse(["diff", "--staged", "--stat"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "diff");
    assert.equal(result.command?.values.staged, true);
    assert.equal(result.command?.values.stat, true);
  });

  // 10. status (short combine)
  it("status -sb", () => {
    const result = gitParse(["status", "-sb"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "status");
    assert.equal(result.command?.values.short, true);
    assert.equal(result.command?.values.branch, true);
  });

  // 11. tag
  it("tag -a v1.0 -m 'Release'", () => {
    const result = gitParse(["tag", "-a", "v1.0", "-m", "Release"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "tag");
    assert.equal(result.command?.values.annotate, true);
    assert.equal(result.command?.values.tagname, "v1.0");
    assert.equal(result.command?.values.message, "Release");
  });

  // 12. remote add (ネストしたサブコマンド)
  it("remote add origin https://...", () => {
    const result = gitParse([
      "remote",
      "add",
      "origin",
      "https://github.com/foo/bar",
    ]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "remote");
    assert.equal(result.command?.command?.name, "add");
    assert.equal(result.command?.command?.values.name, "origin");
    assert.deepEqual(result.command?.command?.values.urls, [
      "https://github.com/foo/bar",
    ]);
  });

  // 13. stash push (ネストしたサブコマンド)
  it("stash push -m 'wip'", () => {
    const result = gitParse(["stash", "push", "-m", "wip"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "stash");
    assert.equal(result.command?.command?.name, "push");
    assert.equal(result.command?.command?.values.message, "wip");
  });

  // 14. グローバルオプション + サブコマンド
  it("-vvv --color always status", () => {
    const result = gitParse(["-vvv", "--color", "always", "status"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.values.verbose, 3);
    assert.equal(result.values.color, "always");
    assert.equal(result.command?.name, "status");
  });

  // 15. --help
  it("--help でヘルプ表示", () => {
    const result = gitParse(["--help"]);
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.help_requested, true);
    assert.ok(result.help);
    assert.ok(result.help.length > 0);
  });

  // 16. clone --help
  it("clone --help でサブコマンドのヘルプ表示", () => {
    const result = gitParse(["clone", "--help"]);
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.equal(result.help_requested, true);
    assert.ok(result.help);
    // clone 関連の情報が含まれていること
    assert.ok(result.help.includes("clone") || result.help.includes("URL"));
  });

  // 17. 不明なフラグ
  it("--unknown-flag でエラー", () => {
    const result = gitParse(["--unknown-flag"]);
    assert.equal(result.ok, false);
    if (result.ok) return;
    assert.ok(result.error);
    assert.ok(result.error.includes("unknown-flag"));
  });

  // 18. 引数なし実行
  it("引数なしで ok=true, command=undefined", () => {
    const result = gitParse([]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    // require_cmd 非対応なので ok=true で command なし
    assert.equal(result.command, undefined);
  });

  // 19. グローバルオプションがサブコマンドの後でも機能する
  it("clone https://... -vv でグローバルオプションが後方でも有効", () => {
    const result = gitParse(["clone", "https://example.com", "-vv"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.values.verbose, 2);
    assert.equal(result.command?.name, "clone");
    assert.equal(result.command?.values.url, "https://example.com");
  });

  // 20. rest に複数値
  it("push origin main ref1 ref2 で rest に複数値", () => {
    const result = gitParse(["push", "origin", "main", "ref1", "ref2"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "push");
    assert.equal(result.command?.values.remote, "origin");
    assert.deepEqual(result.command?.values.refspecs, ["main", "ref1", "ref2"]);
  });

  // 21. 存在しないサブコマンド
  it("nonexistent でエラーになる", () => {
    const result = gitParse(["nonexistent"]);
    // kuu は定義にない位置引数をエラーにする
    assert.equal(result.ok, false);
  });

  // 22. diff --cached でエイリアスが機能する
  it("diff --cached でエイリアスが有効", () => {
    const result = gitParse(["diff", "--cached"]);
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.command?.name, "diff");
    assert.equal(result.command?.values.staged, true);
  });
});
