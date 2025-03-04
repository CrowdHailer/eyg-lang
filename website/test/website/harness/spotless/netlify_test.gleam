import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict
import gleam/http
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None}
import gleeunit/should
import oas
import simplifile

pub fn netlify_test() {
  let assert Ok(spec) =
    simplifile.read("../../midas_sdk/priv/netlify.openapi.json")
  let assert Ok(spec) = json.decode(spec, oas.decoder)
  let oas.Document(paths: paths, components: components, ..) = spec
  dict.fold(paths, [], fn(acc, path, item) {
    let oas.PathItem(operations:, ..) = item
    list.fold(operations, acc, fn(acc, op) {
      case build_operation(op, path, item) {
        Ok(r) -> [r, ..acc]
        Error(_) -> acc
      }
    })
  })
  |> list.fold(ir.empty(), fn(acc, field) {
    let #(label, value) = field
    ir.call(ir.extend(label), [value, acc])
  })
  |> dag_json.to_block
  |> bit_array.to_string
  |> should.be_ok
  // dict.keys(paths)
  |> io.println
  todo
}

//  {"0":"@","l":{"/":"baguqeeragtrji4oxi2ro6bpuo6bqiogjrwhvnmung3d7z5uf4hriebz5ujua"},"p":"standard","r":1}
//  {"0":"@","l":{"/":"baguqeeragtrji4oxi2ro6bpuo6bqiogjrwhvnmung3d7z5uf4hriebz5ujua"},"p":"standard","r":1}

fn get(path, query) {
  ir.record([
    #("method", ir.tagged("GET", ir.unit())),
    #("path", ir.string(path)),
    #("query", ir.list([])),
    #("headers", ir.list([])),
    #("body", ir.binary(<<>>)),
  ])
}

fn build_operation(op, path, path_item) {
  let standard = ir.release("standard", 1, "")

  let #(method, op) = op
  let oas.Operation(operation_id: id, ..) = op
  // use tags instead
  case id {
    "listSites" -> {
      let request = case method, op.request_body {
        http.Get, None -> get(path, [])
        _, _ -> todo
      }

      // io.debug()
      let responses = op.responses |> dict.to_list
      let #(responses) = case list.key_pop(responses, oas.Default) {
        Ok(#(default, rest)) -> #(rest)
        Error(Nil) -> #(responses)
      }

      let assert Ok(responses) =
        list.try_map(responses, fn(response) {
          let #(status, value) = response
          case status {
            oas.Status(status) -> Ok(#(status, value))
            oas.Default -> Error(Nil)
          }
        })
      io.debug(responses)
      let body =
        ir.block(
          [
            #("request", request),
            #(
              "response",
              ir.apply(ir.perform("Netlify"), ir.variable("request")),
            ),
          ],
          ir.match(ir.variable("response"), [
            #(
              "Ok",
              ir.lambda(
                "$",
                ir.block(
                  [
                    #("status", ir.get(ir.variable("$"), "status")),
                    #("body", ir.get(ir.variable("$"), "body")),
                  ],
                  ir.variable("body"),
                ),
              ),
            ),
          ]),
        )

      let action = ir.lambda("_", body)
      Ok(#(id, action))
    }
    _ -> Error(Nil)
  }
}
