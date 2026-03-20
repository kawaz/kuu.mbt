///|
extern "C" fn read_stdin_ffi() -> String = "read_stdin"

///|
#borrow(path)
extern "C" fn read_file_ffi(path : String) -> String = "read_file"
