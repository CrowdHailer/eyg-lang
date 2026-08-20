//// Work with Content Addressable aRchives (CAR / .car) v1 files
//// 
//// https://ipld.io/specs/transport/car/carv1/#summary

import gbor
import gbor/decode as gbor_decode
import gbor/encode
import gleam/bit_array
import gleam/list
import gleam/result.{try}
import gleam/string
import gleb128
import multiformats/cid/v1

pub type Car {
  Car(header: Header, blocks: List(#(v1.Cid, BitArray)))
}

/// A car file does not need to contain a single DAG, so multiple roots can be present
pub type Header {
  Header(version: Int, roots: List(v1.Cid))
}

/// The media type a CAR file is sent as, from the IANA registry.
pub const content_type = "application/vnd.ipld.car"

// const zero_cid = v1.Cid(0, hashes.Multihash(hashes.Sha256, <<>>))

// /// https://ipld.io/specs/codecs/dag-cbor/spec/#links
// /// In DAG-CBOR, Links are the binary form of a CID encoded using the raw-binary identity Multibase.
// /// That is, the Multibase identity prefix (0x00) is prepended to the binary form of a CID and this new byte array is encoded into CBOR as a byte-string (major type 2), and associated with CBOR tag 42.
// /// Tag 42 is associated in the CBOR Tags Registry as "IPLD content identifier" and is further defined in IPLD content identifiers (CIDs) in CBOR.
// fn link_decoder() {
//   // tagged_decoder only works on BEAM
//   gbor_decode.tagged_decoder(
//     42,
//     {
//       use bytes <- decode.then(decode.bit_array)
//       case bytes {
//         <<0, bytes:bytes>> ->
//           case v1.from_bytes(bytes) {
//             Ok(#(cid, _)) -> decode.success(cid)
//             Error(reason) -> decode.failure(zero_cid, reason)
//           }
//         _ ->
//           decode.failure(zero_cid, "expected multibase identity prefix (0x00)")
//       }
//     },
//     zero_cid,
//   )
// }

// fn header_decoder() {
//   use version <- decode.field("version", decode.int)
//   use roots <- decode.field("roots", decode.list(link_decoder()))
//   decode.success(Header(version:, roots:))
// }

pub fn decode(bytes: BitArray) -> Result(Car, String) {
  use #(header, blocks) <- try(frame(bytes))
  use decoded <- try(
    gbor_decode.from_bit_array(header) |> result.map_error(string.inspect),
  )

  use header <- try(case decoded {
    gbor.CBMap(items) ->
      case
        list.key_find(items, gbor.CBString("version")),
        list.key_find(items, gbor.CBString("roots"))
      {
        Ok(gbor.CBInt(version)), Ok(gbor.CBArray(roots)) -> {
          use roots <- try(
            list.try_map(roots, fn(root) {
              case root {
                gbor.CBTagged(42, gbor.CBBinary(<<0, bytes:bytes>>)) ->
                  case v1.from_bytes(bytes) {
                    Ok(#(cid, _)) -> Ok(cid)
                    Error(reason) -> Error(reason)
                  }
                _ -> Error("Not a CID")
              }
            }),
          )
          Ok(Header(version:, roots:))
        }
        _, _ -> Error("could not find header fields")
      }
    _ -> Error("invalid header type")
  })

  // dynamic in gbor library only works on BEAM
  // use header <- try(
  //   dynamic
  //   |> gbor_decode.cbor_to_dynamic
  //   |> decode.run(header_decoder())
  //   |> result.map_error(fn(reason) { string.inspect(reason) }),
  // )

  use blocks <- try(decode_blocks(blocks, []))
  Ok(Car(header:, blocks:))
}

fn decode_blocks(body, acc) {
  case body {
    <<>> -> Ok(list.reverse(acc))
    _ -> {
      use #(block, rest) <- try(frame(body))
      use #(cid, content) <- try(v1.from_bytes(block))

      decode_blocks(rest, [#(cid, content), ..acc])
    }
  }
}

pub fn encode(car: Car) -> Result(BitArray, String) {
  let Car(header:, blocks:) = car
  use header <- try(
    gbor.CBMap([
      #(
        gbor.CBString("roots"),
        gbor.CBArray(
          list.map(header.roots, fn(root) {
            gbor.CBTagged(42, gbor.CBBinary(<<0, v1.to_bytes(root):bits>>))
          }),
        ),
      ),
      #(gbor.CBString("version"), gbor.CBInt(header.version)),
    ])
    |> encode.to_bit_array
    |> result.map_error(fn(reason) {
      let encode.EncodeError(reason) = reason
      reason
    }),
  )
  let blocks =
    list.map(blocks, fn(block) {
      let #(cid, content) = block
      framed(<<v1.to_bytes(cid):bits, content:bits>>)
    })
  Ok(bit_array.concat([header, ..blocks]))
}

// Wrap an array of bytes in an leb128 prefixed frame
fn framed(bytes: BitArray) {
  let assert Ok(size) = gleb128.encode_unsigned(bit_array.byte_size(bytes))
  <<size:bits, bytes:bits>>
}

/// Extract a leb128 prefixed frame from a bit array, return the content and remaining bytes.
fn frame(bytes: BitArray) -> Result(#(BitArray, BitArray), String) {
  use #(number, size) <- try(
    gleb128.decode_unsigned(bytes)
    |> result.replace_error("failed to decode frame size"),
  )
  case bytes {
    <<_:bytes-size(size), header:bytes-size(number), rest:bytes>> ->
      Ok(#(header, rest))
    _ -> Error("frame did not match size")
  }
}
