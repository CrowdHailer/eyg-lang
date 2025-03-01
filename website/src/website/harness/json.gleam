import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dynamic/decode
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/option.{None, Some}
import gleam/result
import gleam/string

pub const l = "JSON"

pub fn lift() {
  t.Binary
}

pub fn reply() {
  t.result(t.Var(0), t.unit)
}

pub fn type_() {
  #(l, #(lift(), reply()))
}

pub fn blocking(lift) {
  io.debug("jsoning")
  use source <- result.map(cast.as_binary(lift))
  promise.resolve(result_to_eyg(do(source)))
}

// TODO test error message works for eval
fn result_to_eyg(result) {
  case result {
    Ok(value) -> v.ok(value)
    Error(reason) -> v.error(v.String(string.inspect(reason)))
  }
}

// TODO test that effects are open
// This is the value to value
fn do(bytes) {
  json.parse_bits(bytes, decoder())
  // case src {
  //   Ok(src) ->
  //     case r.execute(src, []) {
  //       Ok(value) -> {
  //         let rest = k_to_func(k)
  //         let bindings = infer.new_state()
  //         let #(open_effect, bindings) = binding.mono(1, bindings)
  //         // TODO real refs
  //         let #(tree, bindings) =
  //           infer.infer(rest, open_effect, dict.new(), 0, bindings)
  //         let t = tree.1.1
  //         binding.resolve(t, bindings)
  //         io.debug(t)
  //         Ok(value)
  //       }
  //       Error(_) -> panic as "Why this error"
  //     }
  //   _ -> todo as "don't handle lift werror"
  // }
}

fn decoder() {
  use <- decode.recursive()
  decode.one_of(
    decode.dict(decode.string, decoder())
      |> decode.map(v.Record),
    [
      decode.int |> decode.map(v.Integer),
      decode.string |> decode.map(v.String),
      decode.bool |> decode.map(v.bool),
      // decode.null |> decode.map(v.bool),
    ],
  )
  // decode.success(1)
}
