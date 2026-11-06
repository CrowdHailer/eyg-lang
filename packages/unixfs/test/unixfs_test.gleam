// Expected CIDs were generated with the reference JavaScript implementation,
// `ipfs-unixfs-importer` using `cidVersion: 1` and `rawLeaves: true`.

import gleam/bit_array
import gleam/list
import gleeunit
import multiformats/cid/v1
import unixfs.{Link}

pub fn main() -> Nil {
  gleeunit.main()
}

fn file(name, contents) {
  Link(name, unixfs.file_cid(contents), bit_array.byte_size(contents))
}

fn directory(name, links) {
  let block = unixfs.encode_directory(links)
  Link(
    name,
    unixfs.cid(unixfs.dag_pb_code, block),
    unixfs.directory_size(block, links),
  )
}

fn root(links) {
  unixfs.cid(unixfs.dag_pb_code, unixfs.encode_directory(links))
  |> v1.to_string
}

pub fn raw_file_test() {
  assert v1.to_string(unixfs.file_cid(<<>>))
    == "bafkreihdwdcefgh4dqkjv67uzcmw7ojee6xedzdetojuzjevtenxquvyku"
  assert v1.to_string(unixfs.file_cid(<<"hello\n">>))
    == "bafkreicysg23kiwv34eg2d7qweipxwosdo2py4ldv42nbauguluen5v6am"
}

pub fn empty_directory_test() {
  assert root([])
    == "bafybeiczsscdsbs7ffqz55asqdf3smv6klcw3gofszvwlyarci47bgf354"
}

pub fn single_file_directory_test() {
  assert root([file("hello.txt", <<"hello\n">>)])
    == "bafybeigdcg7pksx2zk5336vrfsktjodlr4rbfz37qr3koc5xboxe5ekv24"
}

pub fn links_are_sorted_test() {
  assert root([file("b.txt", <<"bbb">>), file("a.txt", <<"a">>)])
    == "bafybeiemvvz75hd6tu4co735dubwwlqy4rlcvpg7ggmrljmflythyi33gu"
}

pub fn nested_directory_test() {
  assert root([
      directory("dir", [file("inner.txt", <<"inner">>)]),
      file("top.txt", <<"top">>),
    ])
    == "bafybeihkpgg5prgapqksfj3kimxxlnlyyqfa26cybu5jzsb7lgodoeaweq"
}

pub fn empty_file_in_directory_test() {
  assert root([file("e", <<>>)])
    == "bafybeickkij2h35ew77mbnmdn7skotsf6jlvyvzi2mewamolk3q25eatka"
}

pub fn decode_round_trip_test() {
  let links = [
    file("a.txt", <<"a">>),
    directory("dir", [file("inner.txt", <<"inner">>)]),
  ]
  assert unixfs.decode_directory(unixfs.encode_directory(links)) == Ok(links)
}

pub fn decode_rejects_non_directory_test() {
  assert unixfs.decode_directory(<<"not a directory">>) == Error(Nil)
}

// A short name puts the whole link in eight bytes or fewer,
// which a 64 bit varint fast path decodes wrongly on JavaScript.
pub fn decode_short_names_test() {
  let links = [file("a.txt", <<"a">>), file("b.txt", <<"bb">>)]
  assert unixfs.decode_directory(unixfs.encode_directory(links)) == Ok(links)
}

// dag-pb sorts link names as bytes, a name before any longer name it prefixes.
pub fn shorter_name_sorts_first_test() {
  let links = [file("ab", <<"2">>), file("a", <<"1">>), file("B", <<"0">>)]
  let assert Ok(decoded) =
    unixfs.decode_directory(unixfs.encode_directory(links))
  assert list.map(decoded, fn(link) { link.name }) == ["B", "a", "ab"]
}
