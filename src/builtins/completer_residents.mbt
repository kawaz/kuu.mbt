// completer_residents.mbt — DR-117 builtin shell-action completer vocabulary.

///|
priv struct FilesCompleter {}

///|
impl @engine.CompleterExt for FilesCompleter with fn name(_self) {
  "files"
}

///|
pub fn files_completer() -> &@engine.CompleterExt {
  FilesCompleter::{  } as &@engine.CompleterExt
}

///|
priv struct DirsCompleter {}

///|
impl @engine.CompleterExt for DirsCompleter with fn name(_self) {
  "dirs"
}

///|
pub fn dirs_completer() -> &@engine.CompleterExt {
  DirsCompleter::{  } as &@engine.CompleterExt
}
