import eyg/analysis/typ as t
import eyg/interpreter/cast
import eyg/interpreter/expression as r
import eyg/interpreter/value as v
import eyg/runtime/break as old_break
import gleam/http/request
import gleam/http/response
import gleam/io
import gleam/javascript/promise
import gleam/result
import glen
import glen_node
import harness/effect
import harness/http
import harness/stdlib
import plinth/javascript/console

pub fn serve() {
  #(t.Str, t.unit, fn(lift) {
    use port <- result.then(cast.field("port", cast.as_integer, lift))
    use handler <- result.then(cast.field("handler", cast.any, lift))
    let result =
      glen_node.serve(port, fn(req) {
        use body <- promise.await(glen.read_body_bits(req))
        use response <- promise.map(case body {
          Ok(body) -> {
            let req =
              req
              |> request.set_body(body)
              |> http.request_to_eyg()
            let extrinsic =
              {
                effect.init()
                |> effect.extend("Log", effect.debug_logger())
                |> effect.extend("File_Write", effect.file_write())
                |> effect.extend("Await", effect.await())
                |> effect.extend("Wait", effect.wait())
                |> effect.extend("LoadDB", effect.load_db())
                |> effect.extend("QueryDB", effect.query_db())
              }.1
            io.debug("needs to handle handlers extrinsic")

            use response <- promise.map(r.await(r.call(handler, [#(req, Nil)])))
            case response {
              Ok(response) ->
                case http.response_to_gleam(response) {
                  Ok(response) -> response
                  Error(reason) -> {
                    response.new(500)
                    |> response.set_body(<<
                      "server failure",
                      old_break.reason_to_string(reason):utf8,
                    >>)
                  }
                }
              Error(#(reason, _path, _env, _k)) -> {
                response.new(500)
                |> response.set_body(<<
                  "server failure",
                  old_break.reason_to_string(reason):utf8,
                >>)
              }
            }
          }
          Error(_) ->
            response.new(500)
            |> response.set_body(<<"failed to read request body">>)
            |> promise.resolve
        })
        response.set_body(response, glen.Bits(response.body))
      })
    case result {
      Ok(_) -> v.ok(v.unit())
      Error(reason) -> v.error(v.String(reason))
    }
    |> Ok
  })
}

pub fn stop_server() {
  #(t.Str, t.unit, fn(lift) {
    use id <- result.then(cast.as_integer(lift))
    panic as "dont keep track to stop"
  })
}

pub fn receive() {
  #(t.Str, t.unit, fn(lift) {
    let env = stdlib.env()
    use port <- result.then(cast.field("port", cast.as_integer, lift))
    console.log(port)
    use handler <- result.then(cast.field("handler", cast.any, lift))
    panic as "not supported anymore"
    // function pass in raw return on option or re run
    // return blah or nil using dynamic
    // let p =
    //   do_receive(port, fn(raw) {
    //     let req = to_request(raw)
    //     let extrinsic =
    //       {
    //         effect.init()
    //         |> effect.extend("Log", effect.debug_logger())
    //         |> effect.extend("Await", effect.await())
    //         |> effect.extend("Wait", effect.wait())
    //       }.1
    //     let assert Ok(reply) = r.call(handler, [#(req, Nil)], env, extrinsic)
    //     let assert Ok(resp) = cast.field("response", cast.any, reply)
    //     let assert Ok(data) = cast.field("data", cast.as_tagged, reply)

    //     let data = case data {
    //       #("Some", value) -> Some(value)
    //       #("None", _) -> None
    //       _ -> panic as "unexpected data return"
    //     }
    //     #(from_response(resp), data)
    //   })
    // Ok(v.Promise(p))
  })
}
