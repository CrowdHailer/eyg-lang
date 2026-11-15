//// Content blocks that are not UnixFS directory nodes.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import multiformats/cid/v1
import multiformats/hashes
import oas/generator/utils

pub const raw = 85

pub const dag_json_code = 297

pub fn identify(codec, bytes) {
  v1.Cid(
    codec,
    hashes.Multihash(hashes.Sha256, crypto.hash(crypto.Sha256, bytes)),
  )
}

pub fn source(codec, bytes) {
  case codec {
    85 -> Ok(ir.binary(bytes))
    297 -> {
      use text <- result.try(
        bit_array.to_string(bytes)
        |> result.replace_error("DAG-JSON must be UTF-8"),
      )
      case json.parse(text, dag_json.decoder(Nil)) {
        Ok(source) ->
          case
            list.any(ir.list_references(source), fn(reference) {
              case reference {
                ir.Relative(_) -> True
                _ -> False
              }
            })
          {
            True ->
              Error("Content-addressed EYG cannot contain relative imports")
            False -> Ok(source)
          }
        Error(_) -> {
          use value <- result.try(
            json.parse(text, utils.any_decoder())
            |> result.replace_error("Invalid DAG-JSON"),
          )
          structure(value)
        }
      }
    }
    _ -> Error("Supported content codecs are raw and dag-json")
  }
}

fn structure(value) {
  case value {
    utils.String(text) -> Ok(ir.string(text))
    utils.Integer(number) -> Ok(ir.integer(number))
    utils.Number(number) ->
      Ok(ir.tagged("Number", ir.string(float.to_string(number))))
    utils.Boolean(True) -> Ok(ir.true())
    utils.Boolean(False) -> Ok(ir.false())
    utils.Null -> Ok(ir.tagged("Null", ir.unit()))
    utils.Array(values) -> {
      use values <- result.map(list.try_map(values, structure))
      let array = ir.list(values)
      let analysis =
        infer.check_with_references(infer.pure(), dict.new(), array)
      case infer.all_errors(analysis) {
        [] -> array
        // Indexed variants preserve arbitrary heterogeneous tuples without
        // pretending EYG has dynamically typed or recursive JSON lists.
        _ ->
          values
          |> list.index_map(fn(value, index) {
            ir.tagged("Item" <> int.to_string(index), value)
          })
          |> ir.list
      }
    }
    utils.Object(fields) ->
      case dict.size(fields), dict.get(fields, "/") {
        1, Ok(utils.String(text)) ->
          case v1.from_string(text) {
            Ok(#(_, <<>>)) -> Ok(ir.tagged("Link", ir.string(text)))
            _ -> Error("Invalid DAG-JSON link")
          }
        1, Ok(utils.Object(bytes)) ->
          case dict.size(bytes), dict.get(bytes, "bytes") {
            1, Ok(utils.String(encoded)) ->
              bit_array.base64_decode(encoded)
              |> result.map(ir.binary)
              |> result.replace_error("Invalid DAG-JSON bytes")
            _, _ -> Error("Invalid DAG-JSON bytes object")
          }
        _, _ -> {
          use fields <- result.map(
            list.try_map(dict.to_list(fields), fn(field) {
              use value <- result.map(structure(field.1))
              #(field.0, value)
            }),
          )
          ir.record(fields)
        }
      }
  }
}
