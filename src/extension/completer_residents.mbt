// completer_residents.mbt — DR-117 builtin shell-action completer vocabulary.

///|
priv struct FilesCompleter {}

///|
impl CompleterExt for FilesCompleter with fn name(_self) {
  "files"
}

///|
pub fn files_completer() -> &CompleterExt {
  FilesCompleter::{  } as &CompleterExt
}

///|
priv struct DirsCompleter {}

///|
impl CompleterExt for DirsCompleter with fn name(_self) {
  "dirs"
}

///|
pub fn dirs_completer() -> &CompleterExt {
  DirsCompleter::{  } as &CompleterExt
}
