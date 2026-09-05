import eyg/cli/helpers/fs
import simplifile

pub fn default_permissions_test() {
  let file = fs.file("")
  assert 0o666 == simplifile.file_permissions_to_octal(file.permissions)
  let dir = fs.directory([])
  assert 0o777 == simplifile.file_permissions_to_octal(dir.permissions)
}

pub fn resolve_test() {
  let sub =
    fs.directory([
      #("empty", fs.directory([])),
      #("nested", fs.file("I am nested")),
    ])
  let fs = fs.directory([#("sub", sub), #("top", fs.file("Top level"))])

  assert Ok("Top level") == fs.read(fs, "//other/.././/top")
}

pub fn read_errors_test() {
  let assert fs.File(permissions:, ..) = fs.file("")
  let fs =
    fs.directory([
      #("directory", fs.directory([])),
      #("file", fs.file("contents")),
      #("invalid_utf8", fs.File(<<255>>, permissions)),
    ])

  assert Error(simplifile.Eisdir) == fs.read(fs, "/directory")
  assert Error(simplifile.Enoent) == fs.read(fs, "/missing")
  assert Error(simplifile.Enotdir) == fs.read(fs, "/file/child")
  assert Error(simplifile.Enotdir) == fs.read(fs, "/file/")
  assert Error(simplifile.NotUtf8) == fs.read(fs, "/invalid_utf8")
}

pub fn write_create_directory_and_read_directory_test() {
  let file_system = fs.directory([])
  let assert #(Ok(Nil), file_system) =
    fs.create_directory(file_system, "/one/two")
  let assert #(Ok(Nil), file_system) =
    fs.write(file_system, "/one/two/b", "second")
  let assert #(Ok(Nil), file_system) =
    fs.write(file_system, "/one/two/a", "first")

  assert fs.read_directory(file_system, "/one/two") == Ok(["a", "b"])
  assert fs.read(file_system, "/one/two/a") == Ok("first")
  assert fs.write(file_system, "/missing/file", "no parent").0
    == Error(simplifile.Enoent)
  assert fs.create_directory(file_system, "/one/two/a/child").0
    == Error(simplifile.Enotdir)
  assert fs.write(file_system, "/one/two/a/", "invalid").0
    == Error(simplifile.Eisdir)
  assert fs.set_permissions(file_system, "/one/two/a/", 0o600).0
    == Error(simplifile.Enotdir)
  assert fs.write(file_system, "/one/two/bad\u{0}", "invalid").0
    == Error(simplifile.Unknown("ERR_INVALID_ARG_VALUE"))
}

pub fn permissions_are_metadata_not_access_checks_test() {
  let file_system = fs.directory([#("file", fs.file("old"))])
  let assert #(Ok(Nil), file_system) =
    fs.set_permissions(file_system, "/file", 0o000)
  let assert Ok(fs.File(permissions:, ..)) = fs.inspect(file_system, "/file")
  assert simplifile.file_permissions_to_octal(permissions) == 0o000
  assert fs.read(file_system, "/file") == Ok("old")

  let assert #(Ok(Nil), file_system) = fs.write(file_system, "/file", "new")
  assert fs.read(file_system, "/file") == Ok("new")
  let assert Ok(fs.File(permissions:, ..)) = fs.inspect(file_system, "/file")
  assert simplifile.file_permissions_to_octal(permissions) == 0o000
}
