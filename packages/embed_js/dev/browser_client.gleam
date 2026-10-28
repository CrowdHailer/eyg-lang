//// A Gleam browser host consuming the standalone native bundle through plain values.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/string
import javascript/mutable_reference as reference
import plinth/browser/document
import plinth/browser/element
import plinthx/javascript/foreign
import plinthx/javascript/module

pub fn main() {
  use loaded <- promise.await(module.load("/eyg.mjs"))
  let assert Ok(loaded) = loaded
  let assert Ok(options) =
    json.parse(
      "{\"effects\":{\"Add\":{\"lift\":\"integer\",\"lower\":\"integer\"}}}",
      decode.dynamic,
    )
  let create = foreign.property(loaded, "createShell")
  let options =
    foreign.object(
      array.from_list([
        #("effects", foreign.property(options, "effects")),
        #(
          "hub",
          dynamic.string(string.replace(module.url(), "/browser_client.mjs", "")),
        ),
      ]),
    )
  use shell <- promise.await(
    foreign.apply(create, array.from_list([options])) |> foreign.to_promise,
  )
  let total = reference.new(0)
  let handlers =
    foreign.object(
      array.from_list([
        #(
          "Add",
          foreign.to_dynamic(fn(value) {
            let assert Ok(value) = decode.run(value, decode.int)
            reference.set(total, reference.get(total) + value)
            dynamic.int(reference.get(total))
          }),
        ),
      ]),
    )
  let first =
    foreign.apply(
      foreign.property(shell, "runAsync"),
      array.from_list([dynamic.string("let n = perform Add(5) n"), handlers]),
    )
  use first <- promise.map(foreign.to_promise(first))
  assert foreign.property(first, "value") == dynamic.int(5)
  let result =
    foreign.apply(
      foreign.property(shell, "run"),
      array.from_list([dynamic.string("!int_add(n, 1)"), handlers]),
    )
  assert foreign.property(result, "value") == dynamic.int(6)
  assert reference.get(total) == 5
  let assert Ok(output) = document.get_element_by_id("result")
  element.set_inner_text(
    output,
    "PASS native bundle: async host counter=5; retained n+1=6",
  )
}
