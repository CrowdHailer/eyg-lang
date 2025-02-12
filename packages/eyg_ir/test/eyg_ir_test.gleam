import gleam/io
import gleam/json
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

// @external(javascript, "@ipld/dag-json", "encode")
// fn encode(data: json.Json) -> String

@external(javascript, "./eyg_ir_ffi.mjs", "encode")
fn encode(data: json.Json) -> String
// // gleeunit test functions end in `_test`
// pub fn hello_world_test() {
//   io.debug("sooo")
//   // code()
//   encode(json.object([#("a", json.int(3)), #("/", json.int(4))]))
//   |> io.debug
//   1
//   |> should.equal(1)
// }
