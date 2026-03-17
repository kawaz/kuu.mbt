///|
/// mytar — A GNU tar CLI mock built with kuu.
///
/// Demonstrates kuu's ability to handle non-subcommand CLIs with:
///   - exclusive + at_least_one (operation modes)
///   - exclusive (compression methods)
///   - aliases (--extract/--get, --catenate/--concatenate, etc.)
///   - variation (--wildcards/--no-wildcards, --acls/--no-acls, etc.)
///   - count (-v/-vv/-vvv)
///   - append_string (--exclude, -C)
///   - int_opt + post filter (--strip-components)
///   - string_opt + choices (--format)
///   - rest (FILES...)
///   - dashdash (--)
///   - env (TAR_OPTIONS metadata)
fn main {
  println("=== Test 1: create archive ===")
  run_test([
    "-cvzf", "archive.tar.gz", "--exclude", "*.o", "--exclude", "*.tmp", "src/",
    "lib/",
  ])
  println("")
  println("=== Test 2: extract archive ===")
  run_test([
    "-xvf", "archive.tar", "--strip-components", "1", "-C", "/tmp/out",
  ])
  println("")
  println("=== Test 3: list archive ===")
  run_test(["-tvf", "archive.tar"])
  println("")
  println("=== Test 4: help ===")
  run_test(["--help"])
  println("")
  println("=== Test 5: exclusive error (create + extract) ===")
  run_test(["-cxf", "archive.tar"])
  println("")
  println("=== Test 6: compression exclusive error (gzip + xz) ===")
  run_test(["-czJf", "archive.tar.gz", "."])
  println("")
  println("=== Test 7: missing mode error ===")
  run_test(["-f", "archive.tar"])
  println("")
  println("=== Test 8: variation (--no-wildcards) ===")
  run_test(["-cf", "archive.tar", "--no-wildcards", "--exclude", "literal*", "."])
  println("")
  println("=== Test 9: dashdash ===")
  run_test(["-cf", "archive.tar", "--", "--weird-filename"])
  println("")
  println("=== Test 10: short bundling (-cvzf) ===")
  run_test(["-cvzf", "archive.tar.gz", "."])
}

///|
fn run_test(args : Array[String]) -> Unit {
  println("  args: " + args.to_string())
  match build_and_parse(args) {
    Ok(info) => println(info)
    Err(msg) => println("  ERROR: " + msg)
  }
}

///|
fn build_and_parse(args : Array[String]) -> Result[String, String] {
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
  let compress = p.flag(
    name="compress",
    shorts="Z",
    aliases=["uncompress"],
    description="Filter the archive through compress",
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
  p.exclusive([
    gzip.as_ref(),
    bzip2.as_ref(),
    xz.as_ref(),
    compress.as_ref(),
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
    default="-",
    shorts="f",
    description="Use archive file or device ARCHIVE",
    value_name="ARCHIVE",
    env="TAR_ARCHIVE",
  )

  // ─── Common options ───

  let verbose = p.count(
    name="verbose",
    shorts="v",
    description="Verbosely list files processed (-v, -vv, -vvv)",
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
  let no_recursion = p.flag(
    name="no-recursion",
    description="Avoid descending automatically in directories",
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

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(args)
  match result {
    Err(@core.HelpRequested(text)) => {
      println(text)
      Ok("  (help displayed)")
    }
    Err(@core.ParseError(info)) => Err(info.to_string())
    Ok(_) => {
      let buf = StringBuilder::new()

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

      // Compression
      let comp = if gzip.get().unwrap() {
        "gzip"
      } else if bzip2.get().unwrap() {
        "bzip2"
      } else if xz.get().unwrap() {
        "xz"
      } else if compress.get().unwrap() {
        "compress"
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
        ("no-recursion", no_recursion.get().unwrap()),
        ("one-file-system", one_file_system.get().unwrap()),
        ("totals", totals.get().unwrap()),
        ("full-time", full_time.get().unwrap()),
      ]
      for pair in flag_opts {
        if pair.1 {
          buf.write_string("  " + pair.0 + ": true\n")
        }
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
