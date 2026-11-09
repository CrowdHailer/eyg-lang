import eyg/ir/car
import gleam/crypto
import gleam/list
import gleeunit
import multiformats/cid/v1
import multiformats/hashes
import simplifile
import unixfs

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn dir_with_files_test() {
  let assert Ok(bytes) =
    simplifile.read_bits("test/fixtures/dir-with-files.car")
  let assert Ok(car) = car.decode(bytes)
  let root = "bafybeihchr7vmgjaasntayyatmp5sv6xza57iy2h4xj7g46bpjij6yhrmy"
  let assert Ok(#(root, _)) = v1.from_string(root)
  let assert Ok(dir) = list.key_find(car.blocks, root)
  let assert Ok(dir) = unixfs.decode_directory(dir)
  assert ["ascii-copy.txt", "ascii.txt", "hello.txt", "multiblock.txt"]
    == list.map(dir, fn(item) { item.name })
  let assert Ok(block) = unixfs.encode_directory(dir)
  assert root == cid_from_block(block)
}

pub fn cid_from_block(bytes: BitArray) -> v1.Cid {
  let digest = crypto.hash(crypto.Sha256, bytes)
  v1.Cid(unixfs.dag_pb_code, hashes.Multihash(hashes.Sha256, digest))
}
