import gleam/bit_array
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
import eygir/annotated as e2
import eyg/analysis/typ as t
import eyg/runtime/interpreter/runner as r
import eyg/runtime/value as v
import eyg/runtime/break
import eyg/runtime/cast
import harness/effect
import harness/stdlib

pub fn serve() {
  #(t.Str, t.unit, fn(lift) {
    let env = stdlib.env()
    use port <- result.then(cast.field("port", cast.as_integer, lift))
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
        promise.map(r.await(r.resume(handler, [req], env, extrinsic)), fn(resp) {
          case resp {
            Ok(resp) -> from_response(resp)
            Error(#(reason, _path, _env, _k)) -> {
              io.debug(break.reason_to_string(reason))
              #(500, array.from_list([]), bit_array.from_string("Server error"))
            }
          }
        })
      })
    let body = e.Apply(e.Perform("StopServer"), e.Integer(id))
    let body = e2.add_meta(body, Nil)
    Ok(v.Closure("_", body, []))
  })
}

pub fn stop_server() {
  #(t.Str, t.unit, fn(lift) {
    use id <- result.then(cast.as_integer(lift))
    do_stop(id)
    Ok(v.unit)
  })
}

pub fn receive() {
  #(t.Str, t.unit, fn(lift) {
    let env = stdlib.env()
    use port <- result.then(cast.field("port", cast.as_integer, lift))
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
        let assert Ok(reply) = r.resume(handler, [req], env, extrinsic)
        let assert Ok(resp) = cast.field("response", cast.any, reply)
        let assert Ok(data) = cast.field("data", cast.as_tagged, reply)

        let data = case data {
          #("Some", value) -> Some(value)
          #("None", _) -> None
          _ -> panic("unexpected data return")
        }
        #(from_response(resp), data)
      })
    Ok(v.Promise(p))
  })
}

type RawRequest =
  #(String, String, String, String, Dynamic, Array(#(String, String)), String)

type RawResponse =
  #(Int, Array(#(String, String)), BitArray)

fn to_request(raw: RawRequest) {
  let #(method, protocol, host, path, query, headers, body) = raw
  let method = case string.uppercase(method) {
    "GET" -> v.Tagged("GET", v.unit)
    "POST" -> v.Tagged("POST", v.unit)
    "HEAD" -> v.Tagged("HEAD", v.unit)
    "PUT" -> v.Tagged("PUT", v.unit)
    "DELETE" -> v.Tagged("DELETE", v.unit)
    "TRACE" -> v.Tagged("TRACE", v.unit)
    "CONNECT" -> v.Tagged("CONNECT", v.unit)
    "OPTIONS" -> v.Tagged("OPTIONS", v.unit)
    "PATCH" -> v.Tagged("PATCH", v.unit)

    other -> v.Tagged("OTHER", v.Str(other))
  }
  let scheme = case protocol {
    "http" -> v.Tagged("http", v.unit)
    "https" -> v.Tagged("https", v.unit)
    _ -> panic as string.concat(["unexpect protocol in request: ", protocol])
  }
  let host = v.Str(host)
  let path = v.Str(path)
  let assert Ok(query) = dynamic.optional(dynamic.string)(query)
  let query = case query {
    Some(query) -> v.Tagged("Some", v.Str(query))
    None -> v.Tagged("None", v.unit)
  }
  let headers =
    headers
    |> array.to_list
    |> list.map(fn(tuple) {
      let #(key, value) = tuple
      v.Record([#("key", v.Str(key)), #("value", v.Str(value))])
    })
    |> v.LinkedList
  let body = v.Str(body)

  v.Record([
    #("method", method),
    #("scheme", scheme),
    #("host", host),
    #("path", path),
    #("query", query),
    #("headers", headers),
    #("body", body),
  ])
}

// TODO remove handles some old fallbacks in the saved.json
fn binary_or_string(raw) {
  case cast.as_binary(raw) {
    Ok(value) -> Ok(value)
    Error(reason) ->
      case cast.as_string(raw) {
        Ok(s) -> Ok(bit_array.from_string(s))
        Error(_) -> Error(reason)
      }
  }
}

fn from_response(response) {
  let assert Ok(status) = cast.field("status", cast.as_integer, response)
  let assert Ok(headers) = cast.field("headers", cast.as_list, response)
  let assert Ok(body) = cast.field("body", binary_or_string, response)

  let headers =
    list.map(headers, fn(term) {
      let assert Ok(key) = cast.field("key", cast.as_string, term)
      let assert Ok(value) = cast.field("value", cast.as_string, term)

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
