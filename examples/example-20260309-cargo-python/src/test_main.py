"""mycargo パーサのテスト

kuu WASM bridge を使った cargo CLI 引数パースの検証。
"""

import pytest
from kuu import kuu_parse, ParseSuccess, ParseError, ParseResult
from cargo_schema import OPTS, DESCRIPTION


def parse(args: list[str]) -> ParseResult:
    """テスト用パースヘルパー"""
    return kuu_parse(OPTS, args, description=DESCRIPTION)


# === build ===

class TestBuild:
    def test_build_simple(self):
        result = parse(["build"])
        assert isinstance(result, ParseSuccess)
        assert result.command is not None
        assert result.command.name == "build"

    def test_build_release(self):
        result = parse(["build", "--release"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["release"] is True

    def test_build_short_alias(self):
        """'b' は build のエイリアス — WASM bridge では command aliases 未対応 (DR-002)"""
        result = parse(["b", "--release"])
        assert isinstance(result, ParseError)
        assert result.ok is False

    def test_build_full_options(self):
        result = parse([
            "build",
            "--release",
            "--target", "x86_64-unknown-linux-gnu",
            "--features", "serde,tokio",
            "--jobs", "8",
            "--package", "mylib",
            "--lib",
        ])
        assert isinstance(result, ParseSuccess)
        cmd = result.command
        assert cmd.values["release"] is True
        assert cmd.values["target"] == "x86_64-unknown-linux-gnu"
        assert cmd.values["features"] == "serde,tokio"
        assert cmd.values["jobs"] == 8
        assert cmd.values["package"] == "mylib"
        assert cmd.values["lib"] is True

    def test_build_short_flags(self):
        result = parse(["build", "-r", "-j", "4", "-p", "mylib"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["release"] is True
        assert result.command.values["jobs"] == 4
        assert result.command.values["package"] == "mylib"


# === test ===

class TestTest:
    def test_test_simple(self):
        result = parse(["test"])
        assert isinstance(result, ParseSuccess)
        assert result.command.name == "test"

    def test_test_with_name(self):
        result = parse(["test", "my_test_fn"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["testname"] == "my_test_fn"

    def test_test_alias(self):
        """'t' は test のエイリアス — WASM bridge では command aliases 未対応 (DR-002)"""
        result = parse(["t", "--release"])
        assert isinstance(result, ParseError)
        assert result.ok is False

    def test_test_no_run(self):
        result = parse(["test", "--no-run", "--lib"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["no-run"] is True
        assert result.command.values["lib"] is True

    def test_test_with_test_args(self):
        """-- 以降のテストランナー引数"""
        result = parse(["test", "my_test", "--release", "--", "--nocapture", "--test-threads", "1"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["testname"] == "my_test"
        assert result.command.values["release"] is True
        assert result.command.values["test-args"] == ["--nocapture", "--test-threads", "1"]


# === run ===

class TestRun:
    def test_run_simple(self):
        result = parse(["run"])
        assert isinstance(result, ParseSuccess)
        assert result.command.name == "run"

    def test_run_with_bin_and_args(self):
        result = parse(["run", "--bin", "myapp", "--", "arg1", "arg2"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["bin"] == "myapp"
        assert result.command.values["args"] == ["arg1", "arg2"]

    def test_run_release(self):
        result = parse(["run", "-r", "--example", "demo"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["release"] is True
        assert result.command.values["example"] == "demo"


# === bench ===

class TestBench:
    def test_bench_simple(self):
        result = parse(["bench"])
        assert isinstance(result, ParseSuccess)
        assert result.command is not None
        assert result.command.name == "bench"

    def test_bench_with_name(self):
        result = parse(["bench", "my_bench"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["benchname"] == "my_bench"

    def test_bench_with_args(self):
        """-- 以降のベンチマーク引数"""
        result = parse(["bench", "my_bench", "--release", "--", "--nocapture"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["benchname"] == "my_bench"
        assert result.command.values["release"] is True
        assert result.command.values["bench-args"] == ["--nocapture"]


# === new / init ===

class TestNewInit:
    def test_new_basic(self):
        result = parse(["new", "myproject"])
        assert isinstance(result, ParseSuccess)
        assert result.command.name == "new"
        assert result.command.values["path"] == "myproject"

    def test_new_lib_with_edition(self):
        result = parse(["new", "mylib", "--lib", "--edition", "2021"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["lib"] is True
        assert result.command.values["edition"] == "2021"

    def test_new_with_vcs(self):
        result = parse(["new", "myproject", "--vcs", "git"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["vcs"] == "git"

    def test_init_basic(self):
        result = parse(["init"])
        assert isinstance(result, ParseSuccess)
        assert result.command.name == "init"


# === clippy / fmt ===

class TestLintFormat:
    def test_clippy_with_fix(self):
        result = parse(["clippy", "--fix", "--allow-dirty"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["fix"] is True
        assert result.command.values["allow-dirty"] is True

    def test_clippy_with_args(self):
        """-- 以降の clippy 引数"""
        result = parse(["clippy", "--", "-W", "clippy::pedantic"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["clippy-args"] == ["-W", "clippy::pedantic"]

    def test_fmt_check(self):
        result = parse(["fmt", "--check", "--all"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["check"] is True
        assert result.command.values["all"] is True


# === install ===

class TestInstall:
    def test_install_crate(self):
        result = parse(["install", "ripgrep"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["crate"] == "ripgrep"

    def test_install_full(self):
        result = parse(["install", "ripgrep", "--version", "14.0.0", "--force"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["crate"] == "ripgrep"
        assert result.command.values["version"] == "14.0.0"
        assert result.command.values["force"] is True

    def test_install_from_git(self):
        result = parse(["install", "--git", "https://github.com/BurntSushi/ripgrep", "--branch", "main"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["git"] == "https://github.com/BurntSushi/ripgrep"
        assert result.command.values["branch"] == "main"


# === doc / clean / publish / update ===

class TestOtherCommands:
    def test_doc_open(self):
        result = parse(["doc", "--open", "--no-deps"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["open"] is True
        assert result.command.values["no-deps"] is True

    def test_doc_alias(self):
        """'d' は doc のエイリアス — WASM bridge では command aliases 未対応 (DR-002)"""
        result = parse(["d", "--open"])
        assert isinstance(result, ParseError)
        assert result.ok is False

    def test_clean_release(self):
        result = parse(["clean", "--release"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["release"] is True

    def test_publish_dry_run(self):
        result = parse(["publish", "--dry-run", "--allow-dirty"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["dry-run"] is True
        assert result.command.values["allow-dirty"] is True

    def test_update_package(self):
        result = parse(["update", "serde", "--precise", "1.0.200"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["spec"] == "serde"
        assert result.command.values["precise"] == "1.0.200"


# === グローバルオプション ===

class TestGlobalOptions:
    def test_verbose(self):
        result = parse(["-v", "build"])
        assert isinstance(result, ParseSuccess)
        assert result.values["verbose"] == 1

    def test_very_verbose(self):
        result = parse(["-vv", "build"])
        assert isinstance(result, ParseSuccess)
        assert result.values["verbose"] == 2

    def test_quiet(self):
        result = parse(["-q", "build"])
        assert isinstance(result, ParseSuccess)
        assert result.values["quiet"] is True

    def test_color_default(self):
        """--color 未指定時のデフォルト値は "auto" """
        result = parse(["build"])
        assert isinstance(result, ParseSuccess)
        assert result.values["color"] == "auto"

    def test_color_always(self):
        result = parse(["--color", "always", "build"])
        assert isinstance(result, ParseSuccess)
        assert result.values["color"] == "always"

    def test_manifest_path(self):
        result = parse(["--manifest-path", "/path/to/Cargo.toml", "build"])
        assert isinstance(result, ParseSuccess)
        assert result.values["manifest-path"] == "/path/to/Cargo.toml"

    def test_frozen_locked_offline(self):
        result = parse(["--frozen", "--locked", "--offline", "build"])
        assert isinstance(result, ParseSuccess)
        assert result.values["frozen"] is True
        assert result.values["locked"] is True
        assert result.values["offline"] is True

    def test_global_after_subcommand(self):
        """グローバルオプションはサブコマンドの後ろにも置ける"""
        result = parse(["build", "--release", "-vv"])
        assert isinstance(result, ParseSuccess)
        assert result.values["verbose"] == 2
        assert result.command.values["release"] is True


# === ヘルプ ===

class TestHelp:
    def test_top_level_help(self):
        result = parse(["--help"])
        assert isinstance(result, ParseError)
        assert result.help_requested is True
        assert result.help is not None

    def test_subcommand_help(self):
        result = parse(["build", "--help"])
        assert isinstance(result, ParseError)
        assert result.help_requested is True


# === エラー ===

class TestErrors:
    def test_no_args(self):
        """引数なしで parse した場合"""
        result = parse([])
        assert isinstance(result, ParseSuccess)
        assert result.command is None

    def test_unknown_option(self):
        result = parse(["--nonexistent"])
        assert isinstance(result, ParseError)
        assert result.ok is False

    def test_invalid_color_choice(self):
        result = parse(["--color", "rainbow"])
        assert isinstance(result, ParseError)
        assert result.ok is False


# === check ===

class TestCheck:
    def test_check_simple(self):
        result = parse(["check"])
        assert isinstance(result, ParseSuccess)
        assert result.command is not None
        assert result.command.name == "check"

    def test_check_release(self):
        result = parse(["check", "--release"])
        assert isinstance(result, ParseSuccess)
        assert result.command.values["release"] is True
