//// The minimal implementation of unixFS to support creating content addressible storage of a file system.
//// All decode errors return Error(Nil), good input is assumed.

import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import multiformats/cid/v1
import unixfs/protobuf

pub const raw_code = 0x55

pub const dag_pb_code = 0x70

pub type Link {
  Link(cid: v1.Cid, name: String, size: Int)
}

pub type Directory =
  List(Link)

pub fn decode_directory(block: BitArray) -> Result(Directory, Nil) {
  case protobuf.decode(block) {
    Ok(fields) -> do_decode_fields(fields, [], None)
    Error(Nil) -> Error(Nil)
  }
}

/// This accepts a Data field (field 1) at any position in the list of field,
/// even though the standard expects all links fields to be together.
fn do_decode_fields(fields: List(#(Int, protobuf.Field)), acc, type_) {
  case fields, type_ {
    [], Some(Nil) -> Ok(list.reverse(acc))
    [], None -> Error(Nil)
    [#(1, protobuf.Bytes(<<08, 01>>)), ..rest], None ->
      do_decode_fields(rest, acc, Some(Nil))
    [#(2, protobuf.Bytes(link)), ..rest], _ -> {
      case decode_link(link) {
        Ok(link) -> do_decode_fields(rest, [link, ..acc], type_)
        Error(_) -> Error(Nil)
      }
    }
    [_, ..], _ -> Error(Nil)
  }
}

pub fn encode_directory(directory: Directory) {
  let assert Ok(links) =
    list.map(directory, fn(link) {
      #(v1.to_bytes(link.cid), <<link.name:utf8>>, link.size)
    })
    |> list.sort(fn(l1, l2) { bit_array.compare(l1.1, l2.1) })
    |> list.try_map(fn(link) {
      use link <- result.try(encode_link(link))
      protobuf.bytes_field(2, link)
    })
  use data <- result.try(protobuf.bytes_field(1, <<08, 01>>))
  // dag-pb puts Links before Data.
  Ok(<<bit_array.concat(links):bits, data:bits>>)
}

fn decode_link(link: BitArray) {
  use fields <- result.try(protobuf.decode(link))
  let assert [
    #(1, protobuf.Bytes(cid)),
    #(2, protobuf.Bytes(name)),
    #(3, protobuf.Varint(size)),
  ] = fields
  let assert Ok(#(cid, <<>>)) = v1.from_bytes(cid)
  let assert Ok(name) = bit_array.to_string(name)
  Ok(Link(cid:, name:, size:))
}

fn encode_link(link) {
  let #(cid, name, size) = link
  use hash <- result.try(protobuf.bytes_field(1, cid))
  use name <- result.try(protobuf.bytes_field(2, name))
  use size <- result.try(protobuf.varint_field(3, size))
  Ok(<<hash:bits, name:bits, size:bits>>)
}
