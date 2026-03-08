///|
/// mygcc — A sample gcc-like CLI built with kuu to showcase the Variation feature.
///
/// Demonstrates:
///   - variation_false for -W/-Wno- warning control (8 warning flags)
///   - variation_false for -f/-fno- code generation flags (6 codegen flags)
///   - variation_false for --pie/--no-pie (default=true + disable)
///   - variation_false for --debug/--no-debug
///   - explicit variations array (Toggle, Reset) for advanced patterns
///   - string_opt with choices (--optimize, --std, --language)
///   - append_string for repeatable options (--define, --include-path, --lib, --lib-path)
///   - exclusive constraints (--compile/--assemble/--preprocess, --shared/--static, --m32/--m64)
///   - rest positionals with stop_before (source files)
///   - flag with shorts (-v, -c, -S, -E, -g, -o)
fn main {
  // ─── Scenario 1: Typical compilation ───
  println("═══ Scenario 1: Typical compilation with warnings + codegen flags ═══")
  println("")
  let args1 = [
    "--std", "c17",
    "--optimize", "2",
    "--wall",
    "--wextra",
    "--no-wunused-parameter",
    "--werror",
    "--fpic",
    "--no-fomit-frame-pointer",
    "--define", "DEBUG",
    "--define", "VERSION=1.0",
    "--include-path", "/usr/include",
    "--include-path", "/usr/local/include",
    "--output", "main.o",
    "--compile",
    "--debug",
    "--arch", "native",
    "--verbose",
    "main.c",
    "util.c",
  ]
  println("Parsing: " + args1.to_string())
  println("")
  match run(args1) {
    Ok(_) => ()
    Err(msg) => println("ERROR: " + msg)
  }

  // ─── Scenario 2: Linking with libraries ───
  println("═══ Scenario 2: Linking with libraries ═══")
  println("")
  let args2 = [
    "--lib", "m",
    "--lib", "pthread",
    "--lib-path", "/usr/local/lib",
    "--optimize", "3",
    "--flto",
    "--no-pie",
    "--static",
    "main.o",
    "util.o",
  ]
  println("Parsing: " + args2.to_string())
  println("")
  match run(args2) {
    Ok(_) => ()
    Err(msg) => println("ERROR: " + msg)
  }

  // ─── Scenario 3: Short options ───
  println("═══ Scenario 3: Short options ═══")
  println("")
  let args3 = [
    "-o", "a.out",
    "-O", "2",
    "-g",
    "-v",
    "-D", "NDEBUG",
    "-I", "/opt/include",
    "-l", "ssl",
    "-L", "/opt/lib",
    "-x", "c",
    "hello.c",
  ]
  println("Parsing: " + args3.to_string())
  println("")
  match run(args3) {
    Ok(_) => ()
    Err(msg) => println("ERROR: " + msg)
  }

  // ─── Scenario 4: default=true + Variation disable ───
  println("═══ Scenario 4: default=true flags disabled via --no- ═══")
  println("")
  let args4 = [
    "--no-pie",
    "--no-fexceptions",
    "--no-diagnostics-color",
    "--toggle-diagnostics-color",
    // toggle restores true after --no- set false, demonstrating both variations
    "test.c",
  ]
  println("Parsing: " + args4.to_string())
  println("")
  match run(args4) {
    Ok(_) => ()
    Err(msg) => println("ERROR: " + msg)
  }

  // ─── Scenario 5: Exclusive constraint error ───
  println("═══ Scenario 5: Exclusive constraint error (--compile + --assemble) ═══")
  println("")
  let args5 = ["--compile", "--assemble", "test.c"]
  println("Parsing: " + args5.to_string())
  println("")
  match run(args5) {
    Ok(_) => ()
    Err(msg) => println("EXPECTED ERROR: " + msg)
  }

  // ─── Scenario 6: Help output ───
  println("═══ Scenario 6: Help output ═══")
  println("")
  match run(["--help"]) {
    Ok(_) => ()
    Err(msg) => println("ERROR: " + msg)
  }
}

///|
fn run(args : Array[String]) -> Result[Unit, String] {
  // ─── Root parser ───

  let p = @core.Parser::new()
  p.set_description(
    "mygcc - A gcc-like CLI argument parser demo (kuu Variation feature showcase)",
  )

  // ─── Output Control ───

  let output = p.string_opt(
    name="output",
    default="a.out",
    shorts="o",
    description="Place the output into FILE",
    value_name="FILE",
  )
  let compile = p.flag(
    name="compile",
    shorts="c",
    description="Compile and assemble, but do not link",
  )
  let assemble_only = p.flag(
    name="assemble",
    shorts="S",
    description="Compile only; do not assemble or link",
  )
  let preprocess = p.flag(
    name="preprocess",
    shorts="E",
    description="Preprocess only; do not compile, assemble or link",
  )
  // -c, -S, -E are mutually exclusive
  p.exclusive(
    [compile.as_ref(), assemble_only.as_ref(), preprocess.as_ref()],
  )

  // ─── Optimization ───

  let optimize = p.string_opt(
    name="optimize",
    default="0",
    shorts="O",
    choices=["0", "1", "2", "3", "s", "g", "fast"],
    description="Set optimization level",
    value_name="LEVEL",
  )

  // ─── Warning Control (Variation showcase: variation_false sugar) ───
  //
  // gcc pattern: -Wall / -Wno-all, -Wextra / -Wno-extra
  // kuu mapping: --wall / --no-wall, --wextra / --no-wextra
  //
  // All use variation_false=Some("no") to create --no-{name} variant.

  let wall = p.flag(
    name="wall",
    description="Enable most warning messages",
    variation_false=Some("no"),
  )
  let wextra = p.flag(
    name="wextra",
    description="Enable extra warning messages",
    variation_false=Some("no"),
  )
  let werror = p.flag(
    name="werror",
    description="Treat all warnings as errors",
    variation_false=Some("no"),
  )
  let wpedantic = p.flag(
    name="wpedantic",
    description="Issue all diagnostics demanded by strict ISO C/C++",
    variation_false=Some("no"),
  )
  let wformat = p.flag(
    name="wformat",
    description="Check printf/scanf format strings",
    variation_false=Some("no"),
  )
  let wunused_parameter = p.flag(
    name="wunused-parameter",
    description="Warn about unused function parameters",
    variation_false=Some("no"),
  )
  let wimplicit_fallthrough = p.flag(
    name="wimplicit-fallthrough",
    description="Warn about implicit fallthrough in switch statements",
    variation_false=Some("no"),
  )
  let wshadow = p.flag(
    name="wshadow",
    description="Warn when a local variable shadows another",
    variation_false=Some("no"),
  )

  // ─── Debug (Variation: default=false, --debug / --no-debug) ───

  let debug = p.flag(
    name="debug",
    shorts="g",
    description="Produce debugging information in the OS native format",
    variation_false=Some("no"),
  )

  // ─── Language Standard ───

  let std = p.string_opt(
    name="std",
    default="gnu17",
    choices=[
      "c11", "c17", "c23", "gnu11", "gnu17", "gnu23", "c++11", "c++14", "c++17",
      "c++20", "c++23", "gnu++17", "gnu++20", "gnu++23",
    ],
    description="Specify the language standard",
    value_name="STANDARD",
  )

  // ─── Preprocessor (append_string for repeatable options) ───

  let defs = p.append_string(
    name="define",
    shorts="D",
    description="Define a preprocessor macro",
    value_name="MACRO[=VALUE]",
  )
  let undefs = p.append_string(
    name="undefine",
    shorts="U",
    description="Undefine a preprocessor macro",
    value_name="MACRO",
  )
  let include_path = p.append_string(
    name="include-path",
    shorts="I",
    description="Add directory to the include search path",
    value_name="DIR",
  )

  // ─── Linker ───

  let lib = p.append_string(
    name="lib",
    shorts="l",
    description="Search the library named LIBRARY when linking",
    value_name="LIBRARY",
  )
  let lib_path = p.append_string(
    name="lib-path",
    shorts="L",
    description="Add directory to the library search path",
    value_name="DIR",
  )
  let shared = p.flag(
    name="shared",
    description="Produce a shared object",
  )
  let link_static = p.flag(
    name="static",
    description="Prevent linking with shared libraries",
  )
  p.exclusive([shared.as_ref(), link_static.as_ref()])

  // PIE: default=true, --no-pie to disable (Variation showcase)
  let pie = p.flag(
    name="pie",
    default=true,
    description="Create a position-independent executable",
    variation_false=Some("no"),
  )

  // ─── Code Generation (Variation showcase: -f/-fno- pattern) ───
  //
  // gcc pattern: -fPIC / -fno-PIC, -fexceptions / -fno-exceptions
  // kuu mapping: --fpic / --no-fpic, --fexceptions / --no-fexceptions
  //
  // Mix of variation_false sugar and explicit variations array.

  let fpic = p.flag(
    name="fpic",
    description="Generate position-independent code (for shared libraries)",
    variation_false=Some("no"),
  )
  let fomit_frame_pointer = p.flag(
    name="fomit-frame-pointer",
    description="Omit the frame pointer in functions that don't need one",
    variation_false=Some("no"),
  )

  // fexceptions: default=true (enabled by default in C++), --no-fexceptions to disable
  let fexceptions = p.flag(
    name="fexceptions",
    default=true,
    description="Enable exception handling (default for C++)",
    variation_false=Some("no"),
  )

  // Explicit variations array form (equivalent to sugar but more visible)
  let fcommon = p.flag(
    name="fcommon",
    description="Place uninitialized global variables in a common block",
    variations=[@core.False("no")],
  )
  let fstack_protector = p.flag(
    name="fstack-protector",
    description="Enable stack smashing protector",
    variations=[@core.False("no")],
  )
  let flto = p.flag(
    name="flto",
    description="Enable link-time optimization",
    variation_false=Some("no"),
  )

  // ─── Advanced Variation demos ───
  //
  // Toggle: repeated --toggle-diagnostics-color flips the value each time
  // Reset: --reset-warnings restores all warning defaults but marks as "set"

  let diagnostics_color = p.flag(
    name="diagnostics-color",
    default=true,
    description="Use color in diagnostics",
    variation_false=Some("no"),
    variation_toggle=Some("toggle"),
  )

  // ─── Machine Options ───

  let arch = p.string_opt(
    name="arch",
    default="",
    description="Generate code for the specified machine architecture",
    value_name="CPU",
  )
  let tune = p.string_opt(
    name="tune",
    default="",
    description="Optimize for the specified CPU without breaking compatibility",
    value_name="CPU",
  )
  let m32 = p.flag(name="m32", description="Generate 32-bit code")
  let m64 = p.flag(name="m64", description="Generate 64-bit code")
  p.exclusive([m32.as_ref(), m64.as_ref()])

  // ─── Other ───

  let verbose = p.flag(
    name="verbose",
    shorts="v",
    description="Display the programs invoked by the compiler",
  )
  let pipe_opt = p.flag(
    name="pipe",
    description="Use pipes rather than temporary files between stages",
  )
  let language = p.string_opt(
    name="language",
    default="",
    shorts="x",
    choices=["c", "c++", "assembler", "none"],
    description="Specify the language of the following input files",
    value_name="LANG",
  )

  // ─── Positional arguments (source files) ───

  let sources = p.rest(
    name="files",
    description="Source files to compile",
    stop_before=["--"],
  )

  // Design rationale: dashdash() は rest() と同一パーサで使うと built-in
  // "--" separator node と競合して ambiguous になる（DR-001 参照）。
  // gcc では "-Wl,--as-needed" のようにプレフィックスでリンカ引数を渡すため
  // dashdash は不要。

  // ─── Parse ───

  let result : Result[@core.ParseResult, @core.ParseError] = try? p.parse(
    args,
  )
  match result {
    Err(@core.HelpRequested(text)) => {
      println(text)
      Ok(())
    }
    Err(@core.ParseError(info)) => Err(info.to_string())
    Ok(_result) => {
      println("=== Parsed GCC Arguments ===")
      println("")

      // Output control
      println("[Output Control]")
      println("  output: " + output.get().unwrap())
      let c_flag = compile.get().unwrap().to_string()
      println("  compile-only (-c): " + c_flag)
      let s_flag = assemble_only.get().unwrap().to_string()
      println("  assemble-only (-S): " + s_flag)
      let e_flag = preprocess.get().unwrap().to_string()
      println("  preprocess-only (-E): " + e_flag)
      println("")

      // Optimization
      println("[Optimization]")
      println("  level: -O" + optimize.get().unwrap())
      println("")

      // Warnings (Variation showcase)
      println("[Warnings — Variation: --flag / --no-flag]")
      println("  Wall:                  " + wall.get().unwrap().to_string())
      println("  Wextra:                " + wextra.get().unwrap().to_string())
      println("  Werror:                " + werror.get().unwrap().to_string())
      println("  Wpedantic:             " + wpedantic.get().unwrap().to_string())
      println("  Wformat:               " + wformat.get().unwrap().to_string())
      let wup = wunused_parameter.get().unwrap().to_string()
      println("  Wunused-parameter:     " + wup)
      let wif = wimplicit_fallthrough.get().unwrap().to_string()
      println("  Wimplicit-fallthrough: " + wif)
      println("  Wshadow:               " + wshadow.get().unwrap().to_string())
      println("")

      // Debug
      println("[Debug]")
      println("  debug (-g): " + debug.get().unwrap().to_string())
      println("")

      // Language standard
      println("[Language Standard]")
      println("  std: " + std.get().unwrap())
      println("")

      // Preprocessor
      println("[Preprocessor]")
      println("  defines:       " + defs.get().unwrap().to_string())
      println("  undefines:     " + undefs.get().unwrap().to_string())
      println("  include paths: " + include_path.get().unwrap().to_string())
      println("")

      // Linker
      println("[Linker]")
      println("  libraries:    " + lib.get().unwrap().to_string())
      println("  library paths: " + lib_path.get().unwrap().to_string())
      println("  shared: " + shared.get().unwrap().to_string())
      println("  static: " + link_static.get().unwrap().to_string())
      println("  pie:    " + pie.get().unwrap().to_string())
      println("")

      // Code generation (Variation showcase)
      println("[Code Generation — Variation: --flag / --no-flag]")
      println("  fPIC:                " + fpic.get().unwrap().to_string())
      let fofp = fomit_frame_pointer.get().unwrap().to_string()
      println("  fomit-frame-pointer: " + fofp)
      let fex = fexceptions.get().unwrap().to_string()
      println("  fexceptions:         " + fex)
      println("  fcommon:             " + fcommon.get().unwrap().to_string())
      let fsp = fstack_protector.get().unwrap().to_string()
      println("  fstack-protector:    " + fsp)
      println("  flto:                " + flto.get().unwrap().to_string())
      println("")

      // Advanced variation demo
      println("[Advanced Variations]")
      let dc = diagnostics_color.get().unwrap().to_string()
      println("  diagnostics-color (Toggle): " + dc)
      println("")

      // Machine options
      println("[Machine]")
      println("  arch: " + arch.get().unwrap())
      println("  tune: " + tune.get().unwrap())
      println("  m32:  " + m32.get().unwrap().to_string())
      println("  m64:  " + m64.get().unwrap().to_string())
      println("")

      // Other
      println("[Other]")
      println("  verbose:  " + verbose.get().unwrap().to_string())
      println("  pipe:     " + pipe_opt.get().unwrap().to_string())
      println("  language: " + language.get().unwrap())
      println("")

      // Source files
      println("[Source Files]")
      println("  files: " + sources.get().unwrap().to_string())
      println("")

      Ok(())
    }
  }
}
