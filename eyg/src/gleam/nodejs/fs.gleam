external fn do_read_file_sync(path: String, String) -> String =
  "fs" "readFileSync"

/// Returns the contents of the path as a string.
pub fn read_file_sync(path: String) -> String {
  do_read_file_sync(path, "utf8")
}

/// Write a string to a file.
pub external fn write_file_sync(path: String, content: String) -> Nil =
  "fs" "writeFileSync"
