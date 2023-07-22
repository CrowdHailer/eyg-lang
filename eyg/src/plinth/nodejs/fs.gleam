@external(javascript, "fs", "readFileSync")
fn do_read_file_sync(a: String, b: String) -> String

/// Returns the contents of the path as a string.
pub fn read_file_sync(path: String) -> String {
  do_read_file_sync(path, "utf8")
}

/// Write a string to a file.
@external(javascript, "fs", "writeFileSync")
pub fn write_file_sync(path path: String, content content: String) -> Nil
