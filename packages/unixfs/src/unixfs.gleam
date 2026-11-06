//// Blocks for files and directories, compatible with UnixFS v1.
////
//// - A file is a single block using the `raw` codec.
//// - A directory is a `dag-pb` node whose data is a UnixFS `Directory`.
////
//// These are the same blocks IPFS tools produce with CIDv1 and raw leaves,
//// so a root CID from this module can be checked against `ipfs add`.
//// Large files, which UnixFS splits into many blocks, are not supported.

import gleam/bit_array
import gleam/crypto
import gleam/list
import gleam/result.{try}
import multiformats/cid/v1.{type Cid}
import multiformats/hashes
import multiformats/leb128

/// Multicodec code for raw bytes.
pub const raw_code = 0x55

/// Multicodec code for dag-pb.
pub const dag_pb_code = 0x70

/// A named link from a directory to a file or directory.
/// `size` is the cumulative size of the linked DAG (`Tsize`).
pub type Link {
  Link(name: String, cid: Cid, size: Int)
}

pub fn cid(code: Int, bytes: BitArray) -> Cid {
  v1.Cid(
    code,
    hashes.Multihash(hashes.Sha256, crypto.hash(crypto.Sha256, bytes)),
  )
}

/// The CID of a file with these contents.
pub fn file_cid(contents: BitArray) -> Cid {
  cid(raw_code, contents)
}

pub fn is_directory(cid: Cid) -> Bool {
  cid.content_type == dag_pb_code
}

/// The UnixFS data of a directory: field 1 (Type) set to 1 (Directory).
const directory_data = <<0x08, 0x01>>

/// Encode a directory, sorting its links by name.
pub fn encode_directory(links: List(Link)) -> BitArray {
  let links =
    list.sort(links, fn(a, b) {
      bit_array.compare(<<a.name:utf8>>, <<b.name:utf8>>)
    })
  let links =
    list.map(links, fn(link) { field_bytes(2, encode_link(link)) })
    |> bit_array.concat
  // dag-pb puts Links before Data.
  <<links:bits, field_bytes(1, directory_data):bits>>
}

/// Size the parent link should record for a directory block.
pub fn directory_size(block: BitArray, links: List(Link)) -> Int {
  list.fold(links, bit_array.byte_size(block), fn(total, link) {
    total + link.size
  })
}

pub fn decode_directory(block: BitArray) -> Result(List(Link), Nil) {
  use fields <- try(decode_fields(block, []))
  use data <- try(list.key_find(fields, 1))
  use Nil <- try(case data {
    Bytes(data) if data == directory_data -> Ok(Nil)
    _ -> Error(Nil)
  })
  fields
  |> list.filter_map(fn(field) {
    case field {
      #(2, Bytes(link)) -> Ok(link)
      _ -> Error(Nil)
    }
  })
  |> list.try_map(decode_link)
}

fn encode_link(link: Link) -> BitArray {
  let Link(name:, cid:, size:) = link
  let assert Ok(size) = leb128.encode(size)
  <<
    field_bytes(1, v1.to_bytes(cid)):bits,
    field_bytes(2, <<name:utf8>>):bits,
    0x18,
    size:bits,
  >>
}

fn decode_link(bytes: BitArray) -> Result(Link, Nil) {
  use fields <- try(decode_fields(bytes, []))
  use hash <- try(list.key_find(fields, 1))
  use name <- try(list.key_find(fields, 2))
  use size <- try(list.key_find(fields, 3))
  case hash, name, size {
    Bytes(hash), Bytes(name), Varint(size) -> {
      use #(cid, rest) <- try(v1.from_bytes(hash) |> result.replace_error(Nil))
      use Nil <- try(case rest {
        <<>> -> Ok(Nil)
        _ -> Error(Nil)
      })
      use name <- try(bit_array.to_string(name))
      Ok(Link(name:, cid:, size:))
    }
    _, _, _ -> Error(Nil)
  }
}

// Minimal protobuf, only the two wire types dag-pb uses.

type Field {
  Varint(Int)
  Bytes(BitArray)
}

fn field_bytes(number: Int, bytes: BitArray) -> BitArray {
  let assert Ok(tag) = leb128.encode(number * 8 + 2)
  let assert Ok(length) = leb128.encode(bit_array.byte_size(bytes))
  <<tag:bits, length:bits, bytes:bits>>
}

fn decode_fields(bytes, acc) -> Result(List(#(Int, Field)), Nil) {
  case bytes {
    <<>> -> Ok(list.reverse(acc))
    _ -> {
      use #(tag, rest) <- try(read_varint(bytes))
      let number = tag / 8
      case tag % 8 {
        0 -> {
          use #(value, rest) <- try(read_varint(rest))
          decode_fields(rest, [#(number, Varint(value)), ..acc])
        }
        2 -> {
          use #(length, rest) <- try(read_varint(rest))
          case rest {
            <<value:bytes-size(length), rest:bytes>> ->
              decode_fields(rest, [#(number, Bytes(value)), ..acc])
            _ -> Error(Nil)
          }
        }
        _ -> Error(Nil)
      }
    }
  }
}

/// Read an unsigned LEB128 varint.
/// gleb128 reads short inputs as one 64 bit integer, which loses precision
/// on JavaScript, so varints are read a byte at a time here.
fn read_varint(bytes: BitArray) -> Result(#(Int, BitArray), Nil) {
  do_read_varint(bytes, 0, 1)
}

fn do_read_varint(bytes, value, scale) {
  case bytes {
    <<more:1, low:7, rest:bytes>> -> {
      let value = value + low * scale
      case more {
        0 -> Ok(#(value, rest))
        _ -> do_read_varint(rest, value, scale * 128)
      }
    }
    _ -> Error(Nil)
  }
}
