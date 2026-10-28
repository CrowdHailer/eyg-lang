//// Run compiled EYG with just the two capabilities offered by this nginx host.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import njs/request
import plinthx/javascript/foreign

fn object(fields) {
  foreign.object(array.from_list(fields))
}

fn field(value, name, decoder) {
  let assert Ok(value) = decode.run(foreign.property(value, name), decoder)
  value
}

pub fn handle(api: Dynamic, incoming: request.Request) {
  let headers = request.headers(incoming) |> array.to_list
  let headers =
    list.fold_right(
      headers,
      foreign.to_dynamic(array.from_list([])),
      fn(tail, name) {
        foreign.to_dynamic(array.from_list([dynamic.string(name), tail]))
      },
    )
  let input =
    object([
      #(
        "method",
        object([
          #("$T", dynamic.string(request.method(incoming))),
          #("$V", object([])),
        ]),
      ),
      #("path", dynamic.string(request.path(incoming))),
      #("headers", headers),
    ])
  let program =
    foreign.apply(foreign.property(api, "program"), array.from_list([input]))
  let handlers =
    object([
      #(
        "Log",
        foreign.to_dynamic(fn(message) {
          let assert Ok(message) = decode.run(message, decode.string)
          request.log(incoming, message)
          object([])
        }),
      ),
      #(
        "Subrequest",
        foreign.to_dynamic(fn(path) {
          let assert Ok(path) = decode.run(path, decode.string)
          use reply <- promise.map(request.subrequest(incoming, path))
          object([
            #("status", dynamic.int(field(reply, "status", decode.int))),
            #(
              "body",
              dynamic.string(field(reply, "responseText", decode.string)),
            ),
          ])
        }),
      ),
    ])
  let response =
    foreign.apply(
      foreign.property(api, "runAsync"),
      array.from_list([program, handlers]),
    )
  use response <- promise.map(foreign.to_promise(response))
  request.finish(
    incoming,
    field(response, "status", decode.int),
    field(response, "body", decode.string),
  )
}
