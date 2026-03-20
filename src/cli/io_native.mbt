///|
extern "C" fn read_stdin_ffi() -> String = "read_stdin"

///|
#borrow(path)
extern "C" fn read_file_ffi(path : String) -> String = "read_file"

///|
extern "C" fn get_argc_ffi() -> Int = "get_argc"

///|
extern "C" fn get_argv_item_ffi(index : Int) -> String = "get_argv_item"

///|
#borrow(msg)
extern "C" fn write_stderr_ffi(msg : String) -> Unit = "write_stderr"

///|
extern "C" fn exit_ffi(code : Int) -> Unit = "exit_process"

///|
/// Get all command line arguments as an Array[String].
/// Skips argv[0] (program name).
fn get_argv() -> Array[String] {
  let argc = get_argc_ffi()
  let args : Array[String] = []
  for i in 1..<argc {
    args.push(get_argv_item_ffi(i))
  }
  args
}

///|
/// Get the program name (argv[0]).
fn get_program_name() -> String {
  if get_argc_ffi() > 0 {
    get_argv_item_ffi(0)
  } else {
    "kuu"
  }
}
