import cloud/fs
import cloud/store
import multiformats/cid/v1

fn setup() {
  let s = store.new()
  #(s, fs.empty(s))
}

pub fn segments_test() {
  assert fs.segments("/a/b") == ["a", "b"]
  assert fs.segments("a//b/") == ["a", "b"]
  assert fs.segments("./a/../b") == ["b"]
  assert fs.segments("../../a") == ["a"]
  assert fs.segments("/") == []
}

pub fn write_then_read_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.write_file(s, root, "/notes.txt", <<"hi">>)
  assert fs.read_file(s, root, "notes.txt") == Ok(<<"hi">>)
}

pub fn write_creates_parents_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.write_file(s, root, "/a/b/c.txt", <<"deep">>)
  assert fs.read_file(s, root, "/a/b/c.txt") == Ok(<<"deep">>)
  assert fs.read_directory(s, root, "/a") == Ok([#("b", fs.Directory)])
}

pub fn earlier_roots_are_unchanged_test() {
  let #(s, empty) = setup()
  let assert Ok(first) = fs.write_file(s, empty, "/f", <<"one">>)
  let assert Ok(second) = fs.write_file(s, first, "/f", <<"two">>)
  assert fs.read_file(s, first, "/f") == Ok(<<"one">>)
  assert fs.read_file(s, second, "/f") == Ok(<<"two">>)
  assert fs.read_file(s, empty, "/f") == Error(fs.not_found)
}

pub fn same_content_same_root_test() {
  let #(s, empty) = setup()
  let assert Ok(a) = fs.write_file(s, empty, "/x/y", <<"same">>)
  let assert Ok(b) = fs.make_directory(s, empty, "/x")
  let assert Ok(b) = fs.write_file(s, b, "/x/y", <<"same">>)
  assert a == b
}

pub fn append_file_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.append_file(s, root, "/log", <<"a">>)
  let assert Ok(root) = fs.append_file(s, root, "/log", <<"b">>)
  assert fs.read_file(s, root, "/log") == Ok(<<"ab">>)
}

pub fn delete_file_test() {
  let #(s, empty) = setup()
  let assert Ok(root) = fs.write_file(s, empty, "/f", <<"x">>)
  let assert Ok(root) = fs.delete_file(s, root, "/f")
  assert root == empty
  assert fs.delete_file(s, root, "/f") == Error(fs.not_found)
}

pub fn delete_directory_fails_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.make_directory(s, root, "/d")
  assert fs.delete_file(s, root, "/d") == Error(fs.is_a_directory)
}

pub fn make_directory_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.make_directory(s, root, "/a/b")
  let assert Ok(again) = fs.make_directory(s, root, "/a/b")
  assert root == again
  assert fs.read_directory(s, root, "/a/b") == Ok([])
}

pub fn make_directory_over_file_fails_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.write_file(s, root, "/f", <<>>)
  assert fs.make_directory(s, root, "/f") == Error(fs.not_a_directory)
  assert fs.write_file(s, root, "/f/g", <<>>) == Error(fs.not_a_directory)
}

pub fn read_errors_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.make_directory(s, root, "/d")
  assert fs.read_file(s, root, "/d") == Error(fs.is_a_directory)
  assert fs.read_file(s, root, "/missing") == Error(fs.not_found)
  assert fs.write_file(s, root, "/d", <<>>) == Error(fs.is_a_directory)
  assert fs.write_file(s, root, "/", <<>>) == Error(fs.is_a_directory)
}

pub fn read_directory_sizes_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.write_file(s, root, "/b", <<"bbb">>)
  let assert Ok(root) = fs.write_file(s, root, "/a", <<"a">>)
  assert fs.read_directory(s, root, "/")
    == Ok([#("a", fs.File(1)), #("b", fs.File(3))])
}

pub fn root_is_standard_unixfs_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.write_file(s, root, "/hello.txt", <<"hello\n">>)
  assert v1.to_string(root)
    == "bafybeigdcg7pksx2zk5336vrfsktjodlr4rbfz37qr3koc5xboxe5ekv24"
}

pub fn files_and_directories_test() {
  let #(s, root) = setup()
  let assert Ok(root) = fs.write_file(s, root, "/b/c.txt", <<>>)
  let assert Ok(root) = fs.write_file(s, root, "/a.txt", <<>>)
  let assert Ok(root) = fs.make_directory(s, root, "/b/d")
  assert fs.files(s, root) == ["a.txt", "b/c.txt"]
  assert fs.directories(s, root) == ["/", "/b", "/b/d"]
}

pub fn graft_test() {
  let #(s, empty) = setup()
  let assert Ok(upload) = fs.write_file(s, empty, "/photos/cat.jpg", <<"cat">>)
  let assert Ok(links) = fs.links(s, upload, "/")
  let assert Ok(root) = fs.graft(s, empty, "/media", links)
  assert fs.read_file(s, root, "/media/photos/cat.jpg") == Ok(<<"cat">>)
  assert fs.graft(s, root, "/media", links)
    == Error("photos already exists in /media")
  let assert Ok(at_root) = fs.graft(s, empty, "/", links)
  assert at_root == upload
}
