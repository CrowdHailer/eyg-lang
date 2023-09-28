import gleam/dynamic.{Dynamic}
import gleam/io
import gleam/list
import gleam/map
// nullable fn for casting option
import gleam/option.{None, Option, Some}
import gleam/string
import gleam/javascript/array.{Array}
import gleam/javascript/promise.{Promise}
import plinth/javascript/console
import eygir/expression as e
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/cast
import harness/ffi/env
import harness/effect
import harness/stdlib

pub fn serve() {
  #(
    t.Binary,
    t.unit,
    fn(lift, k) {
      let env = stdlib.env()
      let rev = []
      use port <- cast.require(
        cast.field("port", cast.integer, lift),
        rev,
        env,
        k,
      )
      use handler <- cast.require(
        cast.field("handler", cast.any, lift),
        rev,
        env,
        k,
      )
      let id =
        do_serve(
          port,
          fn(raw) {
            let req = to_request(raw)

            promise.map(
              r.flatten_promise(
                r.handle(
                  r.loop(
                    r.V(r.Value(handler)),
                    [],
                    env,
                    Some(r.Kont(r.CallWith(req, rev, env), None)),
                  ),
                  [],
                  {
                    effect.init()
                    |> effect.extend("Log", effect.debug_logger())
                    |> effect.extend("HTTP", effect.http())
                    |> effect.extend("Await", effect.await())
                    |> effect.extend("Wait", effect.wait())
                  }.1,
                ),
                {
                  effect.init()
                  |> effect.extend("Log", effect.debug_logger())
                  |> effect.extend("HTTP", effect.http())
                  |> effect.extend("Await", effect.await())
                  |> effect.extend("Wait", effect.wait())
                }.1,
              ),
              fn(resp) {
                let assert Ok(resp) = resp
                from_response(resp)
              },
            )
          },
        )
      let body = e.Apply(e.Perform("StopServer"), e.Integer(id))
      r.prim(r.Value(r.Function("_", body, [], [])), rev, env, k)
    },
  )
}

pub fn stop_server() {
  #(
    t.Binary,
    t.unit,
    fn(lift, k) {
      let env = stdlib.env()
      let rev = []
      use id <- cast.require(cast.integer(lift), rev, env, k)
      do_stop(id)
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

pub fn receive() {
  #(
    t.Binary,
    t.unit,
    fn(lift, k) {
      let env = stdlib.env()
      let rev = []
      use port <- cast.require(
        cast.field("port", cast.integer, lift),
        rev,
        env,
        k,
      )
      console.log(port)
      use handler <- cast.require(
        cast.field("handler", cast.any, lift),
        rev,
        env,
        k,
      )
      // function pass in raw return on option or re run
      // return blah or nil using dynamic
      let p =
        do_receive(
          port,
          fn(raw) {
            let req = to_request(raw)
            let assert r.Value(reply) =
              r.handle(
                r.loop(
                  r.V(r.Value(handler)),
                  [],
                  env,
                  Some(r.Kont(r.CallWith(req, rev, env), None)),
                ),
                [],
                {
                  effect.init()
                  |> effect.extend("Log", effect.debug_logger())
                  |> effect.extend("HTTP", effect.http())
                  |> effect.extend("Await", effect.await())
                  |> effect.extend("Wait", effect.wait())
                }.1,
              )
            let assert Ok(resp) = r.field(reply, "response")
            let assert Ok(data) = r.field(reply, "data")

            let data = case data {
              r.Tagged("Some", value) -> Some(value)
              r.Tagged("None", _) -> None
              _ -> panic("unexpected data return")
            }
            #(from_response(resp), data)
          },
        )
      r.prim(r.Value(r.Promise(p)), rev, env, k)
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

    other -> r.Tagged("OTHER", r.Binary(other))
  }
  let scheme = case protocol {
    "http" -> r.Tagged("http", r.unit)
    "https" -> r.Tagged("https", r.unit)
  }
  let host = r.Binary(host)
  let path = r.Binary(path)
  let assert Ok(query) = dynamic.optional(dynamic.string)(query)
  let query = case query {
    Some(query) -> r.Tagged("Some", r.Binary(query))
    None -> r.Tagged("None", r.unit)
  }
  let headers =
    headers
    |> array.to_list
    |> list.map(fn(tuple) {
      let #(key, value) = tuple
      r.Record([#("key", r.Binary(key)), #("value", r.Binary(value))])
    })
    |> r.LinkedList
  let body = r.Binary(body)

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
  let assert Ok(r.Binary(body)) = r.field(response, "body")

  let headers =
    list.map(
      headers,
      fn(term) {
        let assert Ok(r.Binary(key)) = r.field(term, "key")
        let assert Ok(r.Binary(value)) = r.field(term, "value")

        #(key, value)
      },
    )
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
