import gleam/dynamic.{Dynamic}
import gleam/option.{None, Some}
import gleam/string
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
      console.log(port)
      let stop =
        do_serve(
          port,
          fn(method, protocol, host, path, query, body) {
            // let assert Ok(method) =
            //   http.method_from_dynamic(dynamic.from(method))
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
            console.log(method)
            console.log(scheme)
            console.log(host)
            console.log(path)
            console.log(query)
            console.log(body)

            #(200, [200], "Hello")
          },
        )
      r.prim(r.Value(r.unit), rev, env, k)
    },
  )
}

// r.Record([
//       #("method", r.Binary(method)),
//       #("scheme", r.Binary(scheme)),
//       #("host", r.Binary(host)),
//       #("path", r.Binary(path)),
//       #("query", r.Binary(query)),
//       #("body", r.Binary(body)),
//     ])

@external(javascript, "../../express_ffi.mjs", "serve")
fn do_serve(
  port: Int,
  handler: fn(String, String, String, String, Dynamic, String) ->
    #(Int, List(Int), String),
) -> Nil
