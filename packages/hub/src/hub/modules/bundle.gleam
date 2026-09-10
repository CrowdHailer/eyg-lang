import eyg/ir/car
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/json
import gleam/list
import hub/cid
import multiformats/cid/v1

pub fn from_car(file: car.Car) {
  let car.Car(header:, blocks:) = file
  case header.roots {
    [root] ->
      case list.key_find(blocks, root) {
        Ok(block) ->
          case cid.from_block(block) == root {
            True ->
              case json.parse_bits(block, dag_json.decoder(Nil)) {
                Ok(source) -> {
                  let children = content_references(source)
                  case check_dependencies(children, blocks, []) {
                    Ok(acc) -> Ok(#(#(root, source), acc))
                    Error(reason) -> Error(reason)
                  }
                }
                Error(_) ->
                  Error(v1.to_string(root) <> " is not valid EYG source")
              }
            False ->
              Error(v1.to_string(root) <> " does not match block content")
          }
        Error(Nil) -> Error("root block is missing")
      }
    _ -> Error("bundle must contain single root")
  }
}

fn check_dependencies(dependencies, blocks, acc) {
  case dependencies {
    [] -> Ok(acc)
    [cid, ..rest] ->
      case list.key_find(acc, cid) {
        // if in acc all further dependencies are also in acc
        Ok(_source) -> check_dependencies(rest, blocks, acc)
        Error(Nil) ->
          case list.key_find(blocks, cid) {
            Ok(block) -> {
              // new block needs checking before pushing
              case cid.from_block(block) == cid {
                True ->
                  case json.parse_bits(block, dag_json.decoder(Nil)) {
                    Ok(source) -> {
                      let children = content_references(source)
                      case check_dependencies(children, blocks, acc) {
                        Ok(acc) -> {
                          let acc = [#(cid, source), ..acc]
                          check_dependencies(rest, blocks, acc)
                        }
                        Error(reason) -> Error(reason)
                      }
                    }
                    Error(_) ->
                      Error(v1.to_string(cid) <> " is not valid EYG source")
                  }
                False ->
                  Error(v1.to_string(cid) <> " does not match block content")
              }
            }
            // A content reference might be in the database and should be kept
            Error(Nil) -> check_dependencies(rest, blocks, acc)
          }
      }
  }
}

fn content_references(source) {
  ir.list_references(source)
  |> list.filter_map(fn(reference) {
    case reference {
      ir.Content(cid:) -> Ok(cid)
      _ -> Error(Nil)
    }
  })
}
