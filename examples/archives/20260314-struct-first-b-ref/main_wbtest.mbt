// sf-b-ref: RefBinder テスト（TDD）

// === Step 1: RefBinder 基本バインド ===

test "flag: basic bind" {
  let target : Ref[Bool] = { val: false }
  let b = RefBinder::new()
  b.flag(name="verbose", target~)
  b.parse(["--verbose"]) |> ignore
  assert_eq(target.val, true)
}

test "flag: default when not specified" {
  let target : Ref[Bool] = { val: false }
  let b = RefBinder::new()
  b.flag(name="verbose", target~)
  b.parse([]) |> ignore
  assert_eq(target.val, false)
}

test "string: basic bind" {
  let target : Ref[String] = { val: "" }
  let b = RefBinder::new()
  b.string(name="output", target~)
  b.parse(["--output", "file.txt"]) |> ignore
  assert_eq(target.val, "file.txt")
}

test "string: default value" {
  let target : Ref[String] = { val: "" }
  let b = RefBinder::new()
  b.string(name="output", target~, default="stdout")
  b.parse([]) |> ignore
  assert_eq(target.val, "stdout")
}

test "int: basic bind" {
  let target : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  b.int(name="count", target~)
  b.parse(["--count", "42"]) |> ignore
  assert_eq(target.val, 42)
}

test "int: default value" {
  let target : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  b.int(name="depth", target~, default=1)
  b.parse([]) |> ignore
  assert_eq(target.val, 1)
}

test "count: basic bind" {
  let target : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  b.count(name="verbose", target~, shorts="v")
  b.parse(["--verbose", "--verbose", "--verbose"]) |> ignore
  assert_eq(target.val, 3)
}

test "count: short combining" {
  let target : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  b.count(name="verbose", target~, shorts="v")
  b.parse(["-vvv"]) |> ignore
  assert_eq(target.val, 3)
}

test "append_string: basic bind" {
  let target : Ref[Array[String]] = { val: [] }
  let b = RefBinder::new()
  b.append_string(name="config", target~)
  b.parse(["--config", "a=1", "--config", "b=2"]) |> ignore
  assert_eq(target.val, ["a=1", "b=2"])
}

test "append_string: empty when not specified" {
  let target : Ref[Array[String]] = { val: [] }
  let b = RefBinder::new()
  b.append_string(name="config", target~)
  b.parse([]) |> ignore
  assert_eq(target.val, [])
}

// === Step 2: git clone サブコマンド ===

test "git clone: url + depth + branch (sub_xxx methods)" {
  let g = GitGlobal::new()
  let clone = CloneOpts::new()
  let b = RefBinder::new()
  b.flag(name="verbose", target=g.verbose, global=true)
  let clone_parser = b.sub(name="clone")
  b.positional(parser=clone_parser, name="url", target=clone.url)
  b.sub_int(parser=clone_parser, name="depth", target=clone.depth)
  b.sub_string(parser=clone_parser, name="branch", target=clone.branch)
  b.parse(["clone", "--depth", "3", "--branch", "dev", "https://example.com/repo.git"]) |> ignore
  assert_eq(clone.url.val, "https://example.com/repo.git")
  assert_eq(clone.depth.val, 3)
  assert_eq(clone.branch.val, "dev")
}

// === Step 3: git commit サブコマンド ===

test "git commit: message + all (sub_xxx methods)" {
  let commit = CommitOpts::new()
  let b = RefBinder::new()
  let commit_parser = b.sub(name="commit")
  b.sub_string(parser=commit_parser, name="message", target=commit.message, shorts="m")
  b.sub_flag(parser=commit_parser, name="all", target=commit.all, shorts="a")
  b.parse(["commit", "-m", "initial commit", "--all"]) |> ignore
  assert_eq(commit.message.val, "initial commit")
  assert_eq(commit.all.val, true)
}

// === Step 4: git log サブコマンド ===

test "git log: oneline + count (sub_xxx methods)" {
  let log = LogOpts::new()
  let b = RefBinder::new()
  let log_parser = b.sub(name="log")
  b.sub_flag(parser=log_parser, name="oneline", target=log.oneline)
  b.sub_int(parser=log_parser, name="count", target=log.count, shorts="n")
  b.parse(["log", "--oneline", "-n", "10"]) |> ignore
  assert_eq(log.oneline.val, true)
  assert_eq(log.count.val, 10)
}

// === Step 5: グローバルオプションの伝搬 ===

test "global option propagates to subcommand" {
  let g = GitGlobal::new()
  let b = RefBinder::new()
  b.flag(name="verbose", target=g.verbose, global=true)
  b.append_string(name="config", target=g.config_entries, global=true)
  let _clone = b.sub(name="clone")
  let _url = _clone.positional(name="url")
  b.parse(["--verbose", "clone", "--config", "core.bare=true", "https://example.com/repo.git"]) |> ignore
  assert_eq(g.verbose.val, true)
  assert_eq(g.config_entries.val, ["core.bare=true"])
}

test "global option after subcommand" {
  let g = GitGlobal::new()
  let b = RefBinder::new()
  b.flag(name="verbose", target=g.verbose, global=true)
  let _clone = b.sub(name="clone")
  let _url = _clone.positional(name="url")
  b.parse(["clone", "https://example.com/repo.git", "--verbose"]) |> ignore
  assert_eq(g.verbose.val, true)
}

// === Step 6: ネストサブコマンド (remote add/remove) ===

test "nested subcommand: remote add (positional method)" {
  let add_opts = RemoteAddOpts::new()
  let b = RefBinder::new()
  let remote = b.sub(name="remote")
  let add = remote.sub(name="add")
  b.positional(parser=add, name="name", target=add_opts.name)
  b.positional(parser=add, name="url", target=add_opts.url)
  b.parse(["remote", "add", "origin", "https://example.com/repo.git"]) |> ignore
  assert_eq(add_opts.name.val, "origin")
  assert_eq(add_opts.url.val, "https://example.com/repo.git")
}

test "nested subcommand: remote remove (positional method)" {
  let rm_opts = RemoteRemoveOpts::new()
  let b = RefBinder::new()
  let remote = b.sub(name="remote")
  let _add = remote.sub(name="add")
  b.positional(parser=_add, name="name", target={ val: "" })
  b.positional(parser=_add, name="url", target={ val: "" })
  let remove = remote.sub(name="remove")
  b.positional(parser=remove, name="name", target=rm_opts.name)
  b.parse(["remote", "remove", "origin"]) |> ignore
  assert_eq(rm_opts.name.val, "origin")
}

// === Step 7: デフォルト値の確認 ===

test "defaults: no args leaves Ref at initial value" {
  let flag_target : Ref[Bool] = { val: false }
  let str_target : Ref[String] = { val: "default_str" }
  let int_target : Ref[Int] = { val: 99 }
  let count_target : Ref[Int] = { val: 0 }
  let arr_target : Ref[Array[String]] = { val: [] }
  let b = RefBinder::new()
  b.flag(name="flag", target=flag_target)
  b.string(name="str", target=str_target, default="default_str")
  b.int(name="num", target=int_target, default=99)
  b.count(name="cnt", target=count_target)
  b.append_string(name="items", target=arr_target)
  b.parse([]) |> ignore
  assert_eq(flag_target.val, false)
  assert_eq(str_target.val, "default_str")
  assert_eq(int_target.val, 99)
  assert_eq(count_target.val, 0)
  assert_eq(arr_target.val, [])
}

// === Step 8: パースエラー時の Ref 状態 ===

test "parse error: Ref unchanged on error" {
  let target : Ref[String] = { val: "original" }
  let b = RefBinder::new()
  b.string(name="output", target~)
  // --unknown はエラーになる
  let result : Result[@core.ParseResult, @core.ParseError] = try? b.parse(["--unknown", "foo"])
  // エラーのはず
  assert_true(result is Err(_))
  // copiers は実行されないので Ref は元の値のまま
  assert_eq(target.val, "original")
}

// === Step 9: エッジケーステスト ===

test "int: negative value" {
  let target : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  b.int(name="offset", target~)
  b.parse(["--offset", "-42"]) |> ignore
  assert_eq(target.val, -42)
}

test "int: zero value" {
  let target : Ref[Int] = { val: 99 }
  let b = RefBinder::new()
  b.int(name="count", target~, default=99)
  b.parse(["--count", "0"]) |> ignore
  assert_eq(target.val, 0)
}

test "string: empty string value" {
  let target : Ref[String] = { val: "initial" }
  let b = RefBinder::new()
  b.string(name="output", target~, default="initial")
  b.parse(["--output", ""]) |> ignore
  assert_eq(target.val, "")
}

test "multiple options: flag + string + int combined" {
  let verbose : Ref[Bool] = { val: false }
  let output : Ref[String] = { val: "" }
  let count : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  b.flag(name="verbose", target=verbose, shorts="v")
  b.string(name="output", target=output, shorts="o")
  b.int(name="count", target=count, shorts="n")
  b.parse(["--verbose", "--output", "result.txt", "--count", "5"]) |> ignore
  assert_eq(verbose.val, true)
  assert_eq(output.val, "result.txt")
  assert_eq(count.val, 5)
}

test "short option: flag alone" {
  let verbose : Ref[Bool] = { val: false }
  let b = RefBinder::new()
  b.flag(name="verbose", target=verbose, shorts="v")
  b.parse(["-v"]) |> ignore
  assert_eq(verbose.val, true)
}

test "short option: -o with value" {
  let output : Ref[String] = { val: "" }
  let b = RefBinder::new()
  b.string(name="output", target=output, shorts="o")
  b.parse(["-o", "file.txt"]) |> ignore
  assert_eq(output.val, "file.txt")
}

test "require_cmd: error when no subcommand" {
  let b = RefBinder::new()
  let _clone = b.sub(name="clone")
  let _commit = b.sub(name="commit")
  b.require_cmd()
  let result : Result[@core.ParseResult, @core.ParseError] = try? b.parse([])
  assert_true(result is Err(_))
}

test "require_cmd: ok when subcommand given" {
  let b = RefBinder::new()
  let _clone = b.sub(name="clone")
  let _commit = b.sub(name="commit")
  b.require_cmd()
  b.parse(["clone"]) |> ignore
}

test "sub_int: negative value in subcommand" {
  let offset : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  let log_parser = b.sub(name="log")
  b.sub_int(parser=log_parser, name="offset", target=offset)
  b.parse(["log", "--offset", "-10"]) |> ignore
  assert_eq(offset.val, -10)
}

test "sub_count: counting in subcommand" {
  let verbosity : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  let run_parser = b.sub(name="run")
  b.sub_count(parser=run_parser, name="verbose", target=verbosity, shorts="v")
  b.parse(["run", "-vvv"]) |> ignore
  assert_eq(verbosity.val, 3)
}

test "sub_append_string: multiple values in subcommand" {
  let labels : Ref[Array[String]] = { val: [] }
  let b = RefBinder::new()
  let build_parser = b.sub(name="build")
  b.sub_append_string(
    parser=build_parser, name="label", target=labels, shorts="l",
  )
  b.parse(["build", "--label", "app=web", "-l", "env=prod"]) |> ignore
  assert_eq(labels.val, ["app=web", "env=prod"])
}

test "sub_string: default value in subcommand" {
  let branch : Ref[String] = { val: "" }
  let b = RefBinder::new()
  let clone_parser = b.sub(name="clone")
  b.sub_string(parser=clone_parser, name="branch", target=branch, default="main")
  b.parse(["clone"]) |> ignore
  assert_eq(branch.val, "main")
}

test "sub_int: default value in subcommand" {
  let depth : Ref[Int] = { val: 0 }
  let b = RefBinder::new()
  let clone_parser = b.sub(name="clone")
  b.sub_int(parser=clone_parser, name="depth", target=depth, default=1)
  b.parse(["clone"]) |> ignore
  assert_eq(depth.val, 1)
}

test "global + sub options: simultaneous use" {
  let verbose : Ref[Bool] = { val: false }
  let config_entries : Ref[Array[String]] = { val: [] }
  let message : Ref[String] = { val: "" }
  let all : Ref[Bool] = { val: false }
  let b = RefBinder::new()
  b.flag(name="verbose", target=verbose, global=true)
  b.append_string(name="config", target=config_entries, global=true)
  let commit_parser = b.sub(name="commit")
  b.sub_string(parser=commit_parser, name="message", target=message, shorts="m")
  b.sub_flag(parser=commit_parser, name="all", target=all, shorts="a")
  b.parse(["--verbose", "--config", "user.name=test", "commit", "-m", "hello", "--all", "--config", "user.email=t@t.com"]) |> ignore
  assert_eq(verbose.val, true)
  assert_eq(config_entries.val, ["user.name=test", "user.email=t@t.com"])
  assert_eq(message.val, "hello")
  assert_eq(all.val, true)
}
