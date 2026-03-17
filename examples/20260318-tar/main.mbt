///|
/// mytar — A GNU tar CLI mock built with kuu.
///
/// Demonstrates kuu's ability to handle non-subcommand CLIs with:
///   - exclusive + at_least_one (operation modes)
///   - exclusive (compression methods)
///   - aliases (--extract/--get, --catenate/--concatenate, etc.)
///   - deprecated (--compress → --gzip)
///   - variation (--wildcards/--no-wildcards, --acls/--no-acls, etc.)
///   - variation_reset (--no-verbose)
///   - variation_false (--no-recursion)
///   - count (-v/-vv/-vvv)
///   - append_string (--exclude, -C)
///   - int_opt + post filter (--strip-components)
///   - string_opt + choices (--format)
///   - rest (FILES...)
///   - dashdash (--)
///   - env (TAPE)
///   - required (--file)
fn main {
  println("=== Demo 1: create archive ===")
  run_test([
    "-cvzf", "archive.tar.gz", "--exclude", "*.o", "--exclude", "*.tmp", "src/",
    "lib/",
  ])
  println("")
  println("=== Demo 2: extract archive with verbose ===")
  run_test([
    "-xvvf", "archive.tar", "--strip-components", "1", "-C", "/tmp/out",
  ])
  println("")
  println("=== Demo 3: help ===")
  run_test(["--help"])
}

///|
fn run_test(
  args : Array[String],
  env~ : Map[String, String] = {},
) -> Unit {
  println("  args: " + args.to_string())
  if env.length() > 0 {
    println("  env: " + env.to_string())
  }
  match build_and_parse(args, env=env) {
    Ok(info) => println(info)
    Err(msg) => println("  ERROR: " + msg)
  }
}

///|
fn build_and_parse(
  args : Array[String],
  env~ : Map[String, String] = {},
) -> Result[String, String] {
  let p = @core.Parser::new()
  p.set_description("mytar - A GNU tar CLI mock built with kuu")

  // ─── Operation modes (exclusive + at_least_one) ───

  let create = p.flag(
    name="create",
    shorts="c",
    description="Create a new archive",
  )
  let extract = p.flag(
    name="extract",
    shorts="x",
    aliases=["get"],
    description="Extract files from an archive",
  )
  let list = p.flag(
    name="list",
    shorts="t",
    description="List the contents of an archive",
  )
  let append = p.flag(
    name="append",
    shorts="r",
    description="Append files to the end of an archive",
  )
  let update = p.flag(
    name="update",
    shorts="u",
    description="Only append files newer than copy in archive",
  )
  let diff = p.flag(
    name="diff",
    shorts="d",
    aliases=["compare"],
    description="Find differences between archive and file system",
  )
  let catenate = p.flag(
    name="catenate",
    shorts="A",
    aliases=["concatenate"],
    description="Append tar files to an archive",
  )
  let delete = p.flag(
    name="delete",
    description="Delete from the archive",
  )
  let test_label = p.flag(
    name="test-label",
    description="Test the archive volume label",
  )
  let mode_refs = [
    create.as_ref(),
    extract.as_ref(),
    list.as_ref(),
    append.as_ref(),
    update.as_ref(),
    diff.as_ref(),
    catenate.as_ref(),
    delete.as_ref(),
    test_label.as_ref(),
  ]
  p.exclusive(mode_refs)
  p.at_least_one(mode_refs)

  // ─── Compression methods (exclusive, optional) ───

  let gzip = p.flag(
    name="gzip",
    shorts="z",
    aliases=["gunzip", "ungzip"],
    description="Filter the archive through gzip",
  )
  let bzip2 = p.flag(
    name="bzip2",
    shorts="j",
    description="Filter the archive through bzip2",
  )
  let xz = p.flag(
    name="xz",
    shorts="J",
    description="Filter the archive through xz",
  )
  // Design rationale: -Z short option is omitted because `deprecated` creates an
  // alias that shares value with the target (gzip). Short options on deprecated
  // aliases are not supported by kuu's deprecated combinator. Users should use
  // --gzip/-z instead.
  let _compress_deprecated = p.deprecated(
    "--compress",
    gzip,
    msg="use --gzip instead",
  )
  let zstd = p.flag(name="zstd", description="Filter the archive through zstd")
  let lzip = p.flag(
    name="lzip",
    description="Filter the archive through lzip",
  )
  let lzma = p.flag(
    name="lzma",
    description="Filter the archive through lzma",
  )
  let lzop = p.flag(
    name="lzop",
    description="Filter the archive through lzop",
  )
  let auto_compress = p.flag(
    name="auto-compress",
    shorts="a",
    description="Use archive suffix to determine the compression program",
  )
  let compress_program = p.string_opt(
    name="use-compress-program",
    default="",
    shorts="I",
    description="Filter through COMMAND",
    value_name="COMMAND",
  )
  // Note: compress is now a deprecated alias for gzip, so it's excluded from
  // the exclusive group (it shares gzip's value and doesn't need separate tracking).
  p.exclusive([
    gzip.as_ref(),
    bzip2.as_ref(),
    xz.as_ref(),
    zstd.as_ref(),
    lzip.as_ref(),
    lzma.as_ref(),
    lzop.as_ref(),
    auto_compress.as_ref(),
    compress_program.as_ref(),
  ])

  // ─── Archive file ───

  let file = p.string_opt(
    name="file",
    default="",
    shorts="f",
    description="Use archive file or device ARCHIVE",
    value_name="ARCHIVE",
    env="TAPE",
  )
  p.required(file.as_ref())

  // ─── Common options ───

  let verbose = p.count(
    name="verbose",
    shorts="v",
    description="Verbosely list files processed (-v, -vv, -vvv)",
    variation_reset=Some("no"),
  )
  let directory = p.append_string(
    name="directory",
    shorts="C",
    description="Change to DIR before performing any operations",
    value_name="DIR",
  )
  let exclude = p.append_string(
    name="exclude",
    description="Exclude files matching PATTERN",
    value_name="PATTERN",
  )
  let exclude_from = p.string_opt(
    name="exclude-from",
    default="",
    shorts="X",
    description="Exclude patterns listed in FILE",
    value_name="FILE",
  )
  let files_from = p.string_opt(
    name="files-from",
    default="",
    shorts="T",
    description="Get names to extract or create from FILE",
    value_name="FILE",
  )
  let strip_components = p.int_opt(
    name="strip-components",
    default=0,
    description="Strip NUMBER leading components from file names on extraction",
    value_name="NUMBER",
    post=Some(@core.Filter::in_range(0, 999)),
  )
  let transform = p.append_string(
    name="transform",
    aliases=["xform"],
    description="Use sed replace EXPRESSION to transform file names",
    value_name="EXPRESSION",
  )

  // ─── Format ───

  let format = p.string_opt(
    name="format",
    default="",
    shorts="H",
    description="Create archive of the given format",
    choices=["gnu", "oldgnu", "pax", "posix", "ustar", "v7"],
    value_name="FORMAT",
  )
  let label = p.string_opt(
    name="label",
    default="",
    shorts="V",
    description="Create archive with volume name TEXT",
    value_name="TEXT",
  )
  let blocking_factor = p.int_opt(
    name="blocking-factor",
    default=20,
    shorts="b",
    description="Set record size to BLOCKSx512 bytes",
    value_name="BLOCKS",
  )

  // ─── Permission / metadata flags ───

  let preserve_permissions = p.flag(
    name="preserve-permissions",
    shorts="p",
    aliases=["same-permissions"],
    description="Extract information about file permissions",
  )
  let keep_old_files = p.flag(
    name="keep-old-files",
    shorts="k",
    description="Don't replace existing files when extracting",
  )
  let touch = p.flag(
    name="touch",
    shorts="m",
    description="Don't extract file modified time",
  )
  let unlink_first = p.flag(
    name="unlink-first",
    shorts="U",
    description="Remove each file prior to extracting over it",
  )
  let verify = p.flag(
    name="verify",
    shorts="W",
    description="Attempt to verify the archive after writing it",
  )
  let interactive = p.flag(
    name="interactive",
    shorts="w",
    aliases=["confirmation"],
    description="Ask for confirmation for every action",
  )
  let absolute_names = p.flag(
    name="absolute-names",
    shorts="P",
    description="Don't strip leading '/' from file names",
  )
  let sparse = p.flag(
    name="sparse",
    shorts="S",
    description="Handle sparse files efficiently",
  )
  let dereference = p.flag(
    name="dereference",
    shorts="h",
    description="Follow symlinks; archive the files they point to",
  )
  let numeric_owner = p.flag(
    name="numeric-owner",
    description="Always use numbers for user/group names",
  )
  let overwrite = p.flag(
    name="overwrite",
    description="Overwrite existing files when extracting",
  )
  let recursion = p.flag(
    name="recursion",
    default=true,
    description="Recurse into directories (default: true)",
    variation_false=Some("no"),
  )
  let one_file_system = p.flag(
    name="one-file-system",
    description="Stay in local file system when creating archive",
  )
  let totals = p.flag(
    name="totals",
    description="Print total bytes after processing the archive",
  )
  let full_time = p.flag(
    name="full-time",
    description="Print file time to its full resolution",
  )

  // ─── Metadata override ───

  let owner = p.string_opt(
    name="owner",
    default="",
    description="Force NAME as owner for added files",
    value_name="NAME[:UID]",
  )
  let group = p.string_opt(
    name="group",
    default="",
    description="Force NAME as group for added files",
    value_name="NAME[:GID]",
  )
  let mode = p.string_opt(
    name="mode",
    default="",
    description="Force permission CHANGES for added files",
    value_name="CHANGES",
  )

  // ─── Variation flags (--xxx / --no-xxx) ───

  let wildcards = p.flag(
    name="wildcards",
    description="Use wildcards (default for --exclude)",
    variation_false=Some("no"),
  )
  let anchored = p.flag(
    name="anchored",
    description="Patterns match file name start",
    variation_false=Some("no"),
  )
  let acls = p.flag(
    name="acls",
    description="Enable POSIX ACLs support",
    variation_false=Some("no"),
  )
  let selinux = p.flag(
    name="selinux",
    description="Enable SELinux context support",
    variation_false=Some("no"),
  )
  let xattrs = p.flag(
    name="xattrs",
    description="Enable extended attributes support",
    variation_false=Some("no"),
  )

  // ─── Positional: files ───

  let files = p.rest(
    name="files",
    description="Files or directory members to archive/extract",
  )

  // ─── Parse ───

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(
    args, env=env,
  )
  match result {
    Err(@core.HelpRequested(text)) => {
      let buf = StringBuilder::new()
      buf.write_string(text)
      Ok(buf.to_string())
    }
    Err(@core.ParseError(info)) => Err(info.to_string())
    Ok(_) => {
      let buf = StringBuilder::new()

      // Deprecated warnings
      let warnings = p.deprecated_warnings()
      for warn in warnings {
        buf.write_string(
          "  [deprecated] " + warn.0 + ": " + warn.1 + "\n",
        )
      }

      // Operation mode
      let mode_name = if create.get().unwrap() {
        "create"
      } else if extract.get().unwrap() {
        "extract"
      } else if list.get().unwrap() {
        "list"
      } else if append.get().unwrap() {
        "append"
      } else if update.get().unwrap() {
        "update"
      } else if diff.get().unwrap() {
        "diff"
      } else if catenate.get().unwrap() {
        "catenate"
      } else if delete.get().unwrap() {
        "delete"
      } else {
        "test-label"
      }
      buf.write_string("  mode: " + mode_name + "\n")

      // Compression (deprecated --compress shares gzip's value, so no separate branch needed)
      let comp = if gzip.get().unwrap() {
        "gzip"
      } else if bzip2.get().unwrap() {
        "bzip2"
      } else if xz.get().unwrap() {
        "xz"
      } else if zstd.get().unwrap() {
        "zstd"
      } else if lzip.get().unwrap() {
        "lzip"
      } else if lzma.get().unwrap() {
        "lzma"
      } else if lzop.get().unwrap() {
        "lzop"
      } else if auto_compress.get().unwrap() {
        "auto"
      } else {
        let prog = compress_program.get().unwrap()
        if prog != "" {
          prog
        } else {
          "none"
        }
      }
      buf.write_string("  compression: " + comp + "\n")

      // File
      buf.write_string("  file: " + file.get().unwrap() + "\n")

      // Verbose
      let v = verbose.get().unwrap()
      if v > 0 {
        buf.write_string("  verbose: " + v.to_string() + "\n")
      }

      // Directory
      let dirs = directory.get().unwrap()
      if dirs.length() > 0 {
        buf.write_string("  directory: " + dirs.to_string() + "\n")
      }

      // Exclude
      let excl = exclude.get().unwrap()
      if excl.length() > 0 {
        buf.write_string("  exclude: " + excl.to_string() + "\n")
      }

      // Exclude-from
      let ef = exclude_from.get().unwrap()
      if ef != "" {
        buf.write_string("  exclude-from: " + ef + "\n")
      }

      // Files-from
      let ff = files_from.get().unwrap()
      if ff != "" {
        buf.write_string("  files-from: " + ff + "\n")
      }

      // Strip components
      let sc = strip_components.get().unwrap()
      if sc > 0 {
        buf.write_string("  strip-components: " + sc.to_string() + "\n")
      }

      // Transform
      let tr = transform.get().unwrap()
      if tr.length() > 0 {
        buf.write_string("  transform: " + tr.to_string() + "\n")
      }

      // Format
      let fmt = format.get().unwrap()
      if fmt != "" {
        buf.write_string("  format: " + fmt + "\n")
      }

      // Label
      let lbl = label.get().unwrap()
      if lbl != "" {
        buf.write_string("  label: " + lbl + "\n")
      }

      // Blocking factor
      let bf = blocking_factor.get().unwrap()
      if bf != 20 {
        buf.write_string("  blocking-factor: " + bf.to_string() + "\n")
      }

      // Permission/metadata flags (only show if set)
      let flag_opts : Array[(String, Bool)] = [
        ("preserve-permissions", preserve_permissions.get().unwrap()),
        ("keep-old-files", keep_old_files.get().unwrap()),
        ("touch", touch.get().unwrap()),
        ("unlink-first", unlink_first.get().unwrap()),
        ("verify", verify.get().unwrap()),
        ("interactive", interactive.get().unwrap()),
        ("absolute-names", absolute_names.get().unwrap()),
        ("sparse", sparse.get().unwrap()),
        ("dereference", dereference.get().unwrap()),
        ("numeric-owner", numeric_owner.get().unwrap()),
        ("overwrite", overwrite.get().unwrap()),
        ("one-file-system", one_file_system.get().unwrap()),
        ("totals", totals.get().unwrap()),
        ("full-time", full_time.get().unwrap()),
      ]
      for pair in flag_opts {
        if pair.1 {
          buf.write_string("  " + pair.0 + ": true\n")
        }
      }

      // Recursion (default=true, show only when false)
      if not(recursion.get().unwrap()) {
        buf.write_string("  recursion: false\n")
      }

      // Metadata override
      let ow = owner.get().unwrap()
      if ow != "" {
        buf.write_string("  owner: " + ow + "\n")
      }
      let gr = group.get().unwrap()
      if gr != "" {
        buf.write_string("  group: " + gr + "\n")
      }
      let md = mode.get().unwrap()
      if md != "" {
        buf.write_string("  mode: " + md + "\n")
      }

      // Variation flags (show if explicitly set)
      if wildcards.is_set() {
        buf.write_string(
          "  wildcards: " + wildcards.get().unwrap().to_string() + "\n",
        )
      }
      if anchored.is_set() {
        buf.write_string(
          "  anchored: " + anchored.get().unwrap().to_string() + "\n",
        )
      }
      if acls.is_set() {
        buf.write_string("  acls: " + acls.get().unwrap().to_string() + "\n")
      }
      if selinux.is_set() {
        buf.write_string(
          "  selinux: " + selinux.get().unwrap().to_string() + "\n",
        )
      }
      if xattrs.is_set() {
        buf.write_string(
          "  xattrs: " + xattrs.get().unwrap().to_string() + "\n",
        )
      }

      // Files
      let file_list = files.get().unwrap()
      if file_list.length() > 0 {
        buf.write_string("  files: " + file_list.to_string() + "\n")
      }

      Ok(buf.to_string())
    }
  }
}

test "basic create" {
  let result = build_and_parse(["-cf", "archive.tar", "file1", "file2"])
  inspect!(result, content=(
    #|Ok("  mode: create\n  compression: none\n  file: archive.tar\n  files: [\"file1\", \"file2\"]\n")
  ))
}

test "extract with alias --get" {
  let result = build_and_parse(["--get", "-f", "archive.tar"])
  inspect!(result, content=(
    #|Ok("  mode: extract\n  compression: none\n  file: archive.tar\n")
  ))
}

test "list with verbose count" {
  let result = build_and_parse(["-tvvf", "archive.tar"])
  inspect!(result, content=(
    #|Ok("  mode: list\n  compression: none\n  file: archive.tar\n  verbose: 2\n")
  ))
}

test "create with gzip compression" {
  let result = build_and_parse(["-czf", "archive.tar.gz", "dir/"])
  inspect!(result, content=(
    #|Ok("  mode: create\n  compression: gzip\n  file: archive.tar.gz\n  files: [\"dir/\"]\n")
  ))
}

test "exclusive error: create + extract" {
  let result = build_and_parse(["-cxf", "archive.tar"])
  inspect!(result, content=(
    #|Err("error: mutually exclusive options: --create, --extract\n\nmytar - A GNU tar CLI mock built with kuu\n\nUsage: [OPTIONS] [FILES]...\n\nArguments:\n  [FILES]...  Files or directory members to archive/extract\n\nOptions:\n  -c, --create                                    Create a new archive\n  -x, --extract, --get                            Extract files from an archive\n  -t, --list                                      List the contents of an archive\n  -r, --append                                    Append files to the end of an archive\n  -u, --update                                    Only append files newer than copy in archive\n  -d, --diff, --compare                           Find differences between archive and file system\n  -A, --catenate, --concatenate                   Append tar files to an archive\n      --delete                                    Delete from the archive\n      --test-label                                Test the archive volume label\n  -z, --gzip, --gunzip, --ungzip                  Filter the archive through gzip\n  -j, --bzip2                                     Filter the archive through bzip2\n  -J, --xz                                        Filter the archive through xz\n      --zstd                                      Filter the archive through zstd\n      --lzip                                      Filter the archive through lzip\n      --lzma                                      Filter the archive through lzma\n      --lzop                                      Filter the archive through lzop\n  -a, --auto-compress                             Use archive suffix to determine the compression program\n  -I, --use-compress-program <COMMAND>            Filter through COMMAND\n  -f, --file <ARCHIVE>                            Use archive file or device ARCHIVE [env: TAPE]\n  -v, --verbose, --no-verbose                     Verbosely list files processed (-v, -vv, -vvv)\n  -C, --directory <DIR>                           Change to DIR before performing any operations\n      --exclude <PATTERN>                         Exclude files matching PATTERN\n  -X, --exclude-from <FILE>                       Exclude patterns listed in FILE\n  -T, --files-from <FILE>                         Get names to extract or create from FILE\n      --strip-components <NUMBER>                 Strip NUMBER leading components from file names on extraction [default: 0]\n      --transform, --xform <EXPRESSION>           Use sed replace EXPRESSION to transform file names\n  -H, --format <FORMAT>                           Create archive of the given format [possible values: gnu, oldgnu, pax, posix, ustar, v7]\n  -V, --label <TEXT>                              Create archive with volume name TEXT\n  -b, --blocking-factor <BLOCKS>                  Set record size to BLOCKSx512 bytes [default: 20]\n  -p, --preserve-permissions, --same-permissions  Extract information about file permissions\n  -k, --keep-old-files                            Don't replace existing files when extracting\n  -m, --touch                                     Don't extract file modified time\n  -U, --unlink-first                              Remove each file prior to extracting over it\n  -W, --verify                                    Attempt to verify the archive after writing it\n  -w, --interactive, --confirmation               Ask for confirmation for every action\n  -P, --absolute-names                            Don't strip leading '/' from file names\n  -S, --sparse                                    Handle sparse files efficiently\n  -h, --dereference                               Follow symlinks; archive the files they point to\n      --numeric-owner                             Always use numbers for user/group names\n      --overwrite                                 Overwrite existing files when extracting\n      --recursion, --no-recursion                 Recurse into directories (default: true)\n      --one-file-system                           Stay in local file system when creating archive\n      --totals                                    Print total bytes after processing the archive\n      --full-time                                 Print file time to its full resolution\n      --owner <NAME[:UID]>                        Force NAME as owner for added files\n      --group <NAME[:GID]>                        Force NAME as group for added files\n      --mode <CHANGES>                            Force permission CHANGES for added files\n      --wildcards, --no-wildcards                 Use wildcards (default for --exclude)\n      --anchored, --no-anchored                   Patterns match file name start\n      --acls, --no-acls                           Enable POSIX ACLs support\n      --selinux, --no-selinux                     Enable SELinux context support\n      --xattrs, --no-xattrs                       Enable extended attributes support\n      --help                                      Print help\n")
  ))
}

test "compression exclusive error: gzip + xz" {
  let result = build_and_parse(["-czJf", "archive.tar.gz", "."])
  inspect!(result, content=(
    #|Err("error: mutually exclusive options: --gzip, --xz\n\nmytar - A GNU tar CLI mock built with kuu\n\nUsage: [OPTIONS] [FILES]...\n\nArguments:\n  [FILES]...  Files or directory members to archive/extract\n\nOptions:\n  -c, --create                                    Create a new archive\n  -x, --extract, --get                            Extract files from an archive\n  -t, --list                                      List the contents of an archive\n  -r, --append                                    Append files to the end of an archive\n  -u, --update                                    Only append files newer than copy in archive\n  -d, --diff, --compare                           Find differences between archive and file system\n  -A, --catenate, --concatenate                   Append tar files to an archive\n      --delete                                    Delete from the archive\n      --test-label                                Test the archive volume label\n  -z, --gzip, --gunzip, --ungzip                  Filter the archive through gzip\n  -j, --bzip2                                     Filter the archive through bzip2\n  -J, --xz                                        Filter the archive through xz\n      --zstd                                      Filter the archive through zstd\n      --lzip                                      Filter the archive through lzip\n      --lzma                                      Filter the archive through lzma\n      --lzop                                      Filter the archive through lzop\n  -a, --auto-compress                             Use archive suffix to determine the compression program\n  -I, --use-compress-program <COMMAND>            Filter through COMMAND\n  -f, --file <ARCHIVE>                            Use archive file or device ARCHIVE [env: TAPE]\n  -v, --verbose, --no-verbose                     Verbosely list files processed (-v, -vv, -vvv)\n  -C, --directory <DIR>                           Change to DIR before performing any operations\n      --exclude <PATTERN>                         Exclude files matching PATTERN\n  -X, --exclude-from <FILE>                       Exclude patterns listed in FILE\n  -T, --files-from <FILE>                         Get names to extract or create from FILE\n      --strip-components <NUMBER>                 Strip NUMBER leading components from file names on extraction [default: 0]\n      --transform, --xform <EXPRESSION>           Use sed replace EXPRESSION to transform file names\n  -H, --format <FORMAT>                           Create archive of the given format [possible values: gnu, oldgnu, pax, posix, ustar, v7]\n  -V, --label <TEXT>                              Create archive with volume name TEXT\n  -b, --blocking-factor <BLOCKS>                  Set record size to BLOCKSx512 bytes [default: 20]\n  -p, --preserve-permissions, --same-permissions  Extract information about file permissions\n  -k, --keep-old-files                            Don't replace existing files when extracting\n  -m, --touch                                     Don't extract file modified time\n  -U, --unlink-first                              Remove each file prior to extracting over it\n  -W, --verify                                    Attempt to verify the archive after writing it\n  -w, --interactive, --confirmation               Ask for confirmation for every action\n  -P, --absolute-names                            Don't strip leading '/' from file names\n  -S, --sparse                                    Handle sparse files efficiently\n  -h, --dereference                               Follow symlinks; archive the files they point to\n      --numeric-owner                             Always use numbers for user/group names\n      --overwrite                                 Overwrite existing files when extracting\n      --recursion, --no-recursion                 Recurse into directories (default: true)\n      --one-file-system                           Stay in local file system when creating archive\n      --totals                                    Print total bytes after processing the archive\n      --full-time                                 Print file time to its full resolution\n      --owner <NAME[:UID]>                        Force NAME as owner for added files\n      --group <NAME[:GID]>                        Force NAME as group for added files\n      --mode <CHANGES>                            Force permission CHANGES for added files\n      --wildcards, --no-wildcards                 Use wildcards (default for --exclude)\n      --anchored, --no-anchored                   Patterns match file name start\n      --acls, --no-acls                           Enable POSIX ACLs support\n      --selinux, --no-selinux                     Enable SELinux context support\n      --xattrs, --no-xattrs                       Enable extended attributes support\n      --help                                      Print help\n")
  ))
}

test "missing mode error" {
  let result = build_and_parse(["-f", "archive.tar"])
  inspect!(result, content=(
    #|Err("error: at least one required: --create, --extract, --list, --append, --update, --diff, --catenate, --delete, --test-label\n\nmytar - A GNU tar CLI mock built with kuu\n\nUsage: [OPTIONS] [FILES]...\n\nArguments:\n  [FILES]...  Files or directory members to archive/extract\n\nOptions:\n  -c, --create                                    Create a new archive\n  -x, --extract, --get                            Extract files from an archive\n  -t, --list                                      List the contents of an archive\n  -r, --append                                    Append files to the end of an archive\n  -u, --update                                    Only append files newer than copy in archive\n  -d, --diff, --compare                           Find differences between archive and file system\n  -A, --catenate, --concatenate                   Append tar files to an archive\n      --delete                                    Delete from the archive\n      --test-label                                Test the archive volume label\n  -z, --gzip, --gunzip, --ungzip                  Filter the archive through gzip\n  -j, --bzip2                                     Filter the archive through bzip2\n  -J, --xz                                        Filter the archive through xz\n      --zstd                                      Filter the archive through zstd\n      --lzip                                      Filter the archive through lzip\n      --lzma                                      Filter the archive through lzma\n      --lzop                                      Filter the archive through lzop\n  -a, --auto-compress                             Use archive suffix to determine the compression program\n  -I, --use-compress-program <COMMAND>            Filter through COMMAND\n  -f, --file <ARCHIVE>                            Use archive file or device ARCHIVE [env: TAPE]\n  -v, --verbose, --no-verbose                     Verbosely list files processed (-v, -vv, -vvv)\n  -C, --directory <DIR>                           Change to DIR before performing any operations\n      --exclude <PATTERN>                         Exclude files matching PATTERN\n  -X, --exclude-from <FILE>                       Exclude patterns listed in FILE\n  -T, --files-from <FILE>                         Get names to extract or create from FILE\n      --strip-components <NUMBER>                 Strip NUMBER leading components from file names on extraction [default: 0]\n      --transform, --xform <EXPRESSION>           Use sed replace EXPRESSION to transform file names\n  -H, --format <FORMAT>                           Create archive of the given format [possible values: gnu, oldgnu, pax, posix, ustar, v7]\n  -V, --label <TEXT>                              Create archive with volume name TEXT\n  -b, --blocking-factor <BLOCKS>                  Set record size to BLOCKSx512 bytes [default: 20]\n  -p, --preserve-permissions, --same-permissions  Extract information about file permissions\n  -k, --keep-old-files                            Don't replace existing files when extracting\n  -m, --touch                                     Don't extract file modified time\n  -U, --unlink-first                              Remove each file prior to extracting over it\n  -W, --verify                                    Attempt to verify the archive after writing it\n  -w, --interactive, --confirmation               Ask for confirmation for every action\n  -P, --absolute-names                            Don't strip leading '/' from file names\n  -S, --sparse                                    Handle sparse files efficiently\n  -h, --dereference                               Follow symlinks; archive the files they point to\n      --numeric-owner                             Always use numbers for user/group names\n      --overwrite                                 Overwrite existing files when extracting\n      --recursion, --no-recursion                 Recurse into directories (default: true)\n      --one-file-system                           Stay in local file system when creating archive\n      --totals                                    Print total bytes after processing the archive\n      --full-time                                 Print file time to its full resolution\n      --owner <NAME[:UID]>                        Force NAME as owner for added files\n      --group <NAME[:GID]>                        Force NAME as group for added files\n      --mode <CHANGES>                            Force permission CHANGES for added files\n      --wildcards, --no-wildcards                 Use wildcards (default for --exclude)\n      --anchored, --no-anchored                   Patterns match file name start\n      --acls, --no-acls                           Enable POSIX ACLs support\n      --selinux, --no-selinux                     Enable SELinux context support\n      --xattrs, --no-xattrs                       Enable extended attributes support\n      --help                                      Print help\n")
  ))
}

test "file required error" {
  let result = build_and_parse(["-c", "file"])
  inspect!(result, content=(
    #|Err("error: required option missing: --file\n\nmytar - A GNU tar CLI mock built with kuu\n\nUsage: [OPTIONS] [FILES]...\n\nArguments:\n  [FILES]...  Files or directory members to archive/extract\n\nOptions:\n  -c, --create                                    Create a new archive\n  -x, --extract, --get                            Extract files from an archive\n  -t, --list                                      List the contents of an archive\n  -r, --append                                    Append files to the end of an archive\n  -u, --update                                    Only append files newer than copy in archive\n  -d, --diff, --compare                           Find differences between archive and file system\n  -A, --catenate, --concatenate                   Append tar files to an archive\n      --delete                                    Delete from the archive\n      --test-label                                Test the archive volume label\n  -z, --gzip, --gunzip, --ungzip                  Filter the archive through gzip\n  -j, --bzip2                                     Filter the archive through bzip2\n  -J, --xz                                        Filter the archive through xz\n      --zstd                                      Filter the archive through zstd\n      --lzip                                      Filter the archive through lzip\n      --lzma                                      Filter the archive through lzma\n      --lzop                                      Filter the archive through lzop\n  -a, --auto-compress                             Use archive suffix to determine the compression program\n  -I, --use-compress-program <COMMAND>            Filter through COMMAND\n  -f, --file <ARCHIVE>                            Use archive file or device ARCHIVE [env: TAPE]\n  -v, --verbose, --no-verbose                     Verbosely list files processed (-v, -vv, -vvv)\n  -C, --directory <DIR>                           Change to DIR before performing any operations\n      --exclude <PATTERN>                         Exclude files matching PATTERN\n  -X, --exclude-from <FILE>                       Exclude patterns listed in FILE\n  -T, --files-from <FILE>                         Get names to extract or create from FILE\n      --strip-components <NUMBER>                 Strip NUMBER leading components from file names on extraction [default: 0]\n      --transform, --xform <EXPRESSION>           Use sed replace EXPRESSION to transform file names\n  -H, --format <FORMAT>                           Create archive of the given format [possible values: gnu, oldgnu, pax, posix, ustar, v7]\n  -V, --label <TEXT>                              Create archive with volume name TEXT\n  -b, --blocking-factor <BLOCKS>                  Set record size to BLOCKSx512 bytes [default: 20]\n  -p, --preserve-permissions, --same-permissions  Extract information about file permissions\n  -k, --keep-old-files                            Don't replace existing files when extracting\n  -m, --touch                                     Don't extract file modified time\n  -U, --unlink-first                              Remove each file prior to extracting over it\n  -W, --verify                                    Attempt to verify the archive after writing it\n  -w, --interactive, --confirmation               Ask for confirmation for every action\n  -P, --absolute-names                            Don't strip leading '/' from file names\n  -S, --sparse                                    Handle sparse files efficiently\n  -h, --dereference                               Follow symlinks; archive the files they point to\n      --numeric-owner                             Always use numbers for user/group names\n      --overwrite                                 Overwrite existing files when extracting\n      --recursion, --no-recursion                 Recurse into directories (default: true)\n      --one-file-system                           Stay in local file system when creating archive\n      --totals                                    Print total bytes after processing the archive\n      --full-time                                 Print file time to its full resolution\n      --owner <NAME[:UID]>                        Force NAME as owner for added files\n      --group <NAME[:GID]>                        Force NAME as group for added files\n      --mode <CHANGES>                            Force permission CHANGES for added files\n      --wildcards, --no-wildcards                 Use wildcards (default for --exclude)\n      --anchored, --no-anchored                   Patterns match file name start\n      --acls, --no-acls                           Enable POSIX ACLs support\n      --selinux, --no-selinux                     Enable SELinux context support\n      --xattrs, --no-xattrs                       Enable extended attributes support\n      --help                                      Print help\n")
  ))
}

test "multiple exclude" {
  let result = build_and_parse([
    "-cf", "a.tar", "--exclude", "*.log", "--exclude", "*.tmp", ".",
  ])
  inspect!(result, content=(
    #|Ok("  mode: create\n  compression: none\n  file: a.tar\n  exclude: [\"*.log\", \"*.tmp\"]\n  files: [\".\"]\n")
  ))
}

test "strip-components" {
  let result = build_and_parse(["-xf", "a.tar", "--strip-components", "1"])
  inspect!(result, content=(
    #|Ok("  mode: extract\n  compression: none\n  file: a.tar\n  strip-components: 1\n")
  ))
}

test "format choices valid" {
  let result = build_and_parse(["-cf", "a.tar", "--format", "pax", "."])
  inspect!(result, content=(
    #|Ok("  mode: create\n  compression: none\n  file: a.tar\n  format: pax\n  files: [\".\"]\n")
  ))
}

test "format choices invalid" {
  let result = build_and_parse(["-cf", "a.tar", "--format", "zip", "."])
  inspect!(result, content=(
    #|Err("error: value must be one of: gnu, oldgnu, pax, posix, ustar, v7\n\nmytar - A GNU tar CLI mock built with kuu\n\nUsage: [OPTIONS] [FILES]...\n\nArguments:\n  [FILES]...  Files or directory members to archive/extract\n\nOptions:\n  -c, --create                                    Create a new archive\n  -x, --extract, --get                            Extract files from an archive\n  -t, --list                                      List the contents of an archive\n  -r, --append                                    Append files to the end of an archive\n  -u, --update                                    Only append files newer than copy in archive\n  -d, --diff, --compare                           Find differences between archive and file system\n  -A, --catenate, --concatenate                   Append tar files to an archive\n      --delete                                    Delete from the archive\n      --test-label                                Test the archive volume label\n  -z, --gzip, --gunzip, --ungzip                  Filter the archive through gzip\n  -j, --bzip2                                     Filter the archive through bzip2\n  -J, --xz                                        Filter the archive through xz\n      --zstd                                      Filter the archive through zstd\n      --lzip                                      Filter the archive through lzip\n      --lzma                                      Filter the archive through lzma\n      --lzop                                      Filter the archive through lzop\n  -a, --auto-compress                             Use archive suffix to determine the compression program\n  -I, --use-compress-program <COMMAND>            Filter through COMMAND\n  -f, --file <ARCHIVE>                            Use archive file or device ARCHIVE [env: TAPE]\n  -v, --verbose, --no-verbose                     Verbosely list files processed (-v, -vv, -vvv)\n  -C, --directory <DIR>                           Change to DIR before performing any operations\n      --exclude <PATTERN>                         Exclude files matching PATTERN\n  -X, --exclude-from <FILE>                       Exclude patterns listed in FILE\n  -T, --files-from <FILE>                         Get names to extract or create from FILE\n      --strip-components <NUMBER>                 Strip NUMBER leading components from file names on extraction [default: 0]\n      --transform, --xform <EXPRESSION>           Use sed replace EXPRESSION to transform file names\n  -H, --format <FORMAT>                           Create archive of the given format [possible values: gnu, oldgnu, pax, posix, ustar, v7]\n  -V, --label <TEXT>                              Create archive with volume name TEXT\n  -b, --blocking-factor <BLOCKS>                  Set record size to BLOCKSx512 bytes [default: 20]\n  -p, --preserve-permissions, --same-permissions  Extract information about file permissions\n  -k, --keep-old-files                            Don't replace existing files when extracting\n  -m, --touch                                     Don't extract file modified time\n  -U, --unlink-first                              Remove each file prior to extracting over it\n  -W, --verify                                    Attempt to verify the archive after writing it\n  -w, --interactive, --confirmation               Ask for confirmation for every action\n  -P, --absolute-names                            Don't strip leading '/' from file names\n  -S, --sparse                                    Handle sparse files efficiently\n  -h, --dereference                               Follow symlinks; archive the files they point to\n      --numeric-owner                             Always use numbers for user/group names\n      --overwrite                                 Overwrite existing files when extracting\n      --recursion, --no-recursion                 Recurse into directories (default: true)\n      --one-file-system                           Stay in local file system when creating archive\n      --totals                                    Print total bytes after processing the archive\n      --full-time                                 Print file time to its full resolution\n      --owner <NAME[:UID]>                        Force NAME as owner for added files\n      --group <NAME[:GID]>                        Force NAME as group for added files\n      --mode <CHANGES>                            Force permission CHANGES for added files\n      --wildcards, --no-wildcards                 Use wildcards (default for --exclude)\n      --anchored, --no-anchored                   Patterns match file name start\n      --acls, --no-acls                           Enable POSIX ACLs support\n      --selinux, --no-selinux                     Enable SELinux context support\n      --xattrs, --no-xattrs                       Enable extended attributes support\n      --help                                      Print help\n")
  ))
}

test "deprecated --compress" {
  let result = build_and_parse(["-cf", "a.tar", "--compress", "."])
  inspect!(result, content=(
    #|Ok("  [deprecated] --compress: use --gzip instead\n  mode: create\n  compression: gzip\n  file: a.tar\n  files: [\".\"]\n")


  ))
}

test "variation --no-recursion" {
  let result = build_and_parse(["-cf", "a.tar", "--no-recursion", "."])
  inspect!(result, content=(
    #|Ok("  mode: create\n  compression: none\n  file: a.tar\n  recursion: false\n  files: [\".\"]\n")
  ))
}

test "variation --no-verbose" {
  let result = build_and_parse(["-tvf", "a.tar", "--no-verbose"])
  inspect!(result, content=(
    #|Ok("  mode: list\n  compression: none\n  file: a.tar\n")
  ))
}

test "variation --no-wildcards" {
  let result = build_and_parse([
    "-cf", "a.tar", "--no-wildcards", "--exclude", "literal*", ".",
  ])
  inspect!(result, content=(
    #|Ok("  mode: create\n  compression: none\n  file: a.tar\n  exclude: [\"literal*\"]\n  wildcards: false\n  files: [\".\"]\n")
  ))
}

test "short option combining" {
  let result = build_and_parse(["-czvf", "archive.tar.gz", "dir/"])
  inspect!(result, content=(
    #|Ok("  mode: create\n  compression: gzip\n  file: archive.tar.gz\n  verbose: 1\n  files: [\"dir/\"]\n")
  ))
}

test "env TAPE fallback for --file" {
  let result = build_and_parse(["-c", "file1"], env={ "TAPE": "backup.tar" })
  inspect!(result, content=(
    #|Ok("  mode: create\n  compression: none\n  file: backup.tar\n  files: [\"file1\"]\n")
  ))
}

test "help display" {
  let result = build_and_parse(["--help"])
  inspect!(result, content=(
    #|Ok("mytar - A GNU tar CLI mock built with kuu\n\nUsage: [OPTIONS] [FILES]...\n\nArguments:\n  [FILES]...  Files or directory members to archive/extract\n\nOptions:\n  -c, --create                                    Create a new archive\n  -x, --extract, --get                            Extract files from an archive\n  -t, --list                                      List the contents of an archive\n  -r, --append                                    Append files to the end of an archive\n  -u, --update                                    Only append files newer than copy in archive\n  -d, --diff, --compare                           Find differences between archive and file system\n  -A, --catenate, --concatenate                   Append tar files to an archive\n      --delete                                    Delete from the archive\n      --test-label                                Test the archive volume label\n  -z, --gzip, --gunzip, --ungzip                  Filter the archive through gzip\n  -j, --bzip2                                     Filter the archive through bzip2\n  -J, --xz                                        Filter the archive through xz\n      --zstd                                      Filter the archive through zstd\n      --lzip                                      Filter the archive through lzip\n      --lzma                                      Filter the archive through lzma\n      --lzop                                      Filter the archive through lzop\n  -a, --auto-compress                             Use archive suffix to determine the compression program\n  -I, --use-compress-program <COMMAND>            Filter through COMMAND\n  -f, --file <ARCHIVE>                            Use archive file or device ARCHIVE [env: TAPE]\n  -v, --verbose, --no-verbose                     Verbosely list files processed (-v, -vv, -vvv)\n  -C, --directory <DIR>                           Change to DIR before performing any operations\n      --exclude <PATTERN>                         Exclude files matching PATTERN\n  -X, --exclude-from <FILE>                       Exclude patterns listed in FILE\n  -T, --files-from <FILE>                         Get names to extract or create from FILE\n      --strip-components <NUMBER>                 Strip NUMBER leading components from file names on extraction [default: 0]\n      --transform, --xform <EXPRESSION>           Use sed replace EXPRESSION to transform file names\n  -H, --format <FORMAT>                           Create archive of the given format [possible values: gnu, oldgnu, pax, posix, ustar, v7]\n  -V, --label <TEXT>                              Create archive with volume name TEXT\n  -b, --blocking-factor <BLOCKS>                  Set record size to BLOCKSx512 bytes [default: 20]\n  -p, --preserve-permissions, --same-permissions  Extract information about file permissions\n  -k, --keep-old-files                            Don't replace existing files when extracting\n  -m, --touch                                     Don't extract file modified time\n  -U, --unlink-first                              Remove each file prior to extracting over it\n  -W, --verify                                    Attempt to verify the archive after writing it\n  -w, --interactive, --confirmation               Ask for confirmation for every action\n  -P, --absolute-names                            Don't strip leading '/' from file names\n  -S, --sparse                                    Handle sparse files efficiently\n  -h, --dereference                               Follow symlinks; archive the files they point to\n      --numeric-owner                             Always use numbers for user/group names\n      --overwrite                                 Overwrite existing files when extracting\n      --recursion, --no-recursion                 Recurse into directories (default: true)\n      --one-file-system                           Stay in local file system when creating archive\n      --totals                                    Print total bytes after processing the archive\n      --full-time                                 Print file time to its full resolution\n      --owner <NAME[:UID]>                        Force NAME as owner for added files\n      --group <NAME[:GID]>                        Force NAME as group for added files\n      --mode <CHANGES>                            Force permission CHANGES for added files\n      --wildcards, --no-wildcards                 Use wildcards (default for --exclude)\n      --anchored, --no-anchored                   Patterns match file name start\n      --acls, --no-acls                           Enable POSIX ACLs support\n      --selinux, --no-selinux                     Enable SELinux context support\n      --xattrs, --no-xattrs                       Enable extended attributes support\n      --help                                      Print help\n")
  ))
}
