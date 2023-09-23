import gleam/dynamic.{Dynamic}
import gleam/option.{None, Some}
import gleam/string
import gleam/javascript/promise.{Promise}
import plinth/javascript/console
import eyg/analysis/typ as t
import eyg/runtime/interpreter as r
import harness/ffi/cast
import harness/ffi/env

pub fn serve() {
  #(
    t.Binary,
    t.unit,
    fn(lift, k) {
      let env = env.empty()
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
      console.log(port)
      let stop =
        do_serve(
          port,
          fn(raw) {
            let req = request(raw)
            // console.log(req)
            // console.log(handler)
            let assert r.Value(resp) =
              r.loop(
                r.V(r.Value(handler)),
                [],
                env,
                Some(r.Kont(r.CallWith(req, rev, env), None)),
              )
            // r.eval(handler, env, None)
            // mulch returns string but type check properly for record
            r.to_string(resp)
            |> console.log()
            // TODO record
            // fn to resturn resp and reply, BUT how to small step
            // if put in kontinutation then cant serialize continuations
            let assert r.Binary(page) = resp

            #(200, [200], "Hello")
          },
        )
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

pub fn receive() {
  #(
    t.Binary,
    t.unit,
    fn(lift, k) {
      let env = env.empty()
      let rev = []
      console.log(lift)
      use port <- cast.require(cast.integer(lift), rev, env, k)
      console.log(port)
      let p = do_receive(port)
      r.prim(
        r.Value(r.Promise(promise.map(
          p,
          fn(input) {
            let #(raw, reply) = input
            r.ok(r.Record([
              #("request", request(raw)),
              // TODO how do I pass a builtin fn back
              #("reply", r.Defunc(r.Builtin("!NOTSerializabe"), [])),
            ]))
          },
        ))),
        rev,
        env,
        k,
      )
    },
  )
}

type RawRequest =
  #(String, String, String, String, Dynamic, String)

fn request(raw: RawRequest) {
  console.log(raw)
  let #(method, protocol, host, path, query, body) = raw
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
  // TODO headers
  let body = r.Binary(body)

  r.Record([
    #("method", method),
    #("scheme", scheme),
    #("host", host),
    #("path", path),
    #("query", query),
    #("body", body),
  ])
}

@external(javascript, "../../express_ffi.mjs", "serve")
fn do_serve(
  port: Int,
  // TODO make request type problay in tuple here
  handler: fn(RawRequest) -> #(Int, List(Int), String),
) -> Nil

@external(javascript, "../../express_ffi.mjs", "receive")
fn do_receive(
  port: Int,
) -> Promise(#(RawRequest, fn(#(Int, List(Int), String)) -> Nil))