import gleam/dynamic.{type Dynamic}
import gleam/io
import gleam/list
// nullable fn for casting option
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/javascript/array.{type Array}
import gleam/javascript/promise.{type Promise}
import plinth/javascript/console
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/cast
import harness/effect
import harness/stdlib

pub fn serve() {
  #(
    t.Str,
    t.unit,
    fn(lift, k) {
      let env = stdlib.env()
      let rev = []
      use port <- result.then(cast.field("port", cast.integer, lift))
      use handler <- result.then(cast.field("handler", cast.any, lift))
      let id =
        do_serve(port, fn(raw) {
          let req = to_request(raw)
          let extrinsic =
            {
              effect.init()
              |> effect.extend("Log", effect.debug_logger())
              |> effect.extend("HTTP", effect.http())
              |> effect.extend("File_Write", effect.file_write())
              |> effect.extend("Await", effect.await())
              |> effect.extend("Wait", effect.wait())
              |> effect.extend("LoadDB", effect.load_db())
              |> effect.extend("QueryDB", effect.query_db())
            }.1
          promise.map(
            r.await(r.loop(
              r.V(handler),
              [],
              env,
              r.Stack(r.CallWith(req, rev, env), r.WillRenameAsDone(extrinsic)),
            )),
            fn(resp) {
              case resp {
                r.Value(resp) -> from_response(resp)
                r.Abort(reason, _path, _env, _k) -> {
                  io.debug(r.reason_to_string(reason))
                  #(500, array.from_list([]), "Server error")
                }
              }
            },
          )
        })
      let body = e.Apply(e.Perform("StopServer"), e.Integer(id))
      Ok(r.Function("_", body, [], []))
    },
  )
}

pub fn stop_server() {
  #(
    t.Str,
    t.unit,
    fn(lift, k) {
      use id <- result.then(cast.integer(lift))
      do_stop(id)
      Ok(r.unit)
    },
  )
}

pub fn receive() {
  #(
    t.Str,
    t.unit,
    fn(lift, k) {
      let env = stdlib.env()
      let rev = []
      use port <- result.then(cast.field("port", cast.integer, lift))
      console.log(port)
      use handler <- result.then(cast.field("handler", cast.any, lift))
      // function pass in raw return on option or re run
      // return blah or nil using dynamic
      let p =
        do_receive(port, fn(raw) {
          let req = to_request(raw)
          let extrinsic =
            {
              effect.init()
              |> effect.extend("Log", effect.debug_logger())
              |> effect.extend("HTTP", effect.http())
              |> effect.extend("Await", effect.await())
              |> effect.extend("Wait", effect.wait())
            }.1
          let assert r.Value(reply) =
            r.loop(
              r.V(handler),
              [],
              env,
              r.Stack(r.CallWith(req, rev, env), r.WillRenameAsDone(extrinsic)),
            )
          let assert Ok(resp) = r.field(reply, "response")
          let assert Ok(data) = r.field(reply, "data")

          let data = case data {
            r.Tagged("Some", value) -> Some(value)
            r.Tagged("None", _) -> None
            _ -> panic("unexpected data return")
          }
          #(from_response(resp), data)
        })
      Ok(r.Promise(p))
    },
  )
}

type RawRequest =
  #(String, String, String, String, Dynamic, Array(#(String, String)), String)

type RawResponse =
  #(Int, Array(#(String, String)), String)

fn to_request(raw: RawRequest) {
  let #(method, protocol, host, path, query, headers, body) = raw
  let method = case string.uppercase(method) {
    "GET" -> r.Tagged("GET", r.unit)
    "POST" -> r.Tagged("POST", r.unit)
    "HEAD" -> r.Tagged("HEAD", r.unit)
    "PUT" -> r.Tagged("PUT", r.unit)
    "DELETE" -> r.Tagged("DELETE", r.unit)
    "TRACE" -> r.Tagged("TRACE", r.unit)
    "CONNECT" -> r.Tagged("CONNECT", r.unit)
    "OPTIONS" -> r.Tagged("OPTIONS", r.unit)
    "PATCH" -> r.Tagged("PATCH", r.unit)

    other -> r.Tagged("OTHER", r.Str(other))
  }
  let scheme = case protocol {
    "http" -> r.Tagged("http", r.unit)
    "https" -> r.Tagged("https", r.unit)
    _ -> panic as string.concat(["unexpect protocol in request: ", protocol])
  }
  let host = r.Str(host)
  let path = r.Str(path)
  let assert Ok(query) = dynamic.optional(dynamic.string)(query)
  let query = case query {
    Some(query) -> r.Tagged("Some", r.Str(query))
    None -> r.Tagged("None", r.unit)
  }
  let headers =
    headers
    |> array.to_list
    |> list.map(fn(tuple) {
      let #(key, value) = tuple
      r.Record([#("key", r.Str(key)), #("value", r.Str(value))])
    })
    |> r.LinkedList
  let body = r.Str(body)

  r.Record([
    #("method", method),
    #("scheme", scheme),
    #("host", host),
    #("path", path),
    #("query", query),
    #("headers", headers),
    #("body", body),
  ])
}

fn from_response(response) {
  let assert Ok(r.Integer(status)) = r.field(response, "status")
  let assert Ok(r.LinkedList(headers)) = r.field(response, "headers")
  let assert Ok(r.Str(body)) = r.field(response, "body")

  let headers =
    list.map(headers, fn(term) {
      let assert Ok(r.Str(key)) = r.field(term, "key")
      let assert Ok(r.Str(value)) = r.field(term, "value")

      #(key, value)
    })
    |> array.from_list()

  #(status, headers, body)
}

@external(javascript, "../../express_ffi.mjs", "serve")
fn do_serve(port: Int, handler: fn(RawRequest) -> Promise(RawResponse)) -> Int

@external(javascript, "../../express_ffi.mjs", "stopServer")
fn do_stop(id: Int) -> Nil

@external(javascript, "../../express_ffi.mjs", "receive")
fn do_receive(
  port: Int,
  handler: fn(RawRequest) -> #(RawResponse, Option(a)),
) -> Promise(a)
