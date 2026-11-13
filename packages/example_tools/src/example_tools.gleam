//// Build and serve explicit browser assets, proxying hub and model requests.

import filepath
import gleam/dict
import gleam/int
import gleam/javascript/promise
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import plinthx/browser/fetch
import plinthx/bun/bundle
import plinthx/bun/runtime
import plinthx/bun/server
import plinthx/node/process
import simplifile

pub type Asset {
  Asset(path: String, body: BitArray, content_type: String)
}

pub type Options {
  Options(port: Int, hub: String, model: String)
}

pub fn environment(default_port: Int) -> Options {
  let assert Ok(host) = process.get()
  let env = process.env(host) |> dict.from_list
  let port =
    dict.get(env, "PORT")
    |> result.try(int.parse)
    |> result.unwrap(default_port)
  let hub = dict.get(env, "EYG_HUB") |> result.unwrap("https://eyg.run")
  let model =
    dict.get(env, "OLLAMA_ORIGIN") |> result.unwrap("http://127.0.0.1:11434")
  Options(port:, hub:, model:)
}

pub fn file(
  path: String,
  file: String,
  content_type: String,
) -> Result(Asset, String) {
  use body <- result.map(
    simplifile.read_bits(file) |> result.map_error(simplifile.describe_error),
  )
  Asset(path:, body:, content_type:)
}

/// Bundle a compiled Gleam browser entry; its exported main is called by HTML glue.
pub fn build(
  entry: String,
  output: String,
) -> promise.Promise(Result(Nil, String)) {
  let assert Ok(bun) = runtime.get()
  let options =
    json.object([
      #("entrypoints", json.array([entry], json.string)),
      #("target", json.string("browser")),
      #("format", json.string("esm")),
    ])
    |> json.to_string
  use built <- promise.await(bundle.build(bun, options))
  case built {
    Error(reason) -> promise.resolve(Error(reason))
    Ok(built) ->
      case bundle.success(built), bundle.outputs(built) {
        True, [artifact] -> {
          use text <- promise.map(bundle.text(artifact))
          use _ <- result.try(
            simplifile.create_directory_all(filepath.directory_name(output))
            |> result.map_error(simplifile.describe_error),
          )
          simplifile.write(output, text)
          |> result.map_error(simplifile.describe_error)
        }
        _, _ -> promise.resolve(Error(string.join(bundle.logs(built), "\n")))
      }
  }
}

pub fn serve(
  options: Options,
  assets: List(Asset),
) -> Result(server.Server, String) {
  let assert Ok(bun) = runtime.get()
  let assert Ok(native) = fetch.get()
  let assert Ok(response) = fetch.get_response()
  server.serve(
    bun,
    server.Options(options.port, "127.0.0.1", fn(request) {
      let assert Ok(url) = uri.parse(fetch.request_url(request))
      let target = case
        string.starts_with(url.path, "/packages/")
        || string.starts_with(url.path, "/modules/"),
        string.starts_with(url.path, "/api/")
      {
        True, _ -> Some(options.hub)
        _, True -> Some(options.model)
        _, _ -> None
      }
      case target {
        Some(target) -> {
          use body <- promise.await(fetch.request_bytes(request))
          let headers =
            fetch.request_headers(request)
            |> list.filter(fn(header) {
              header.0 != "host" && header.0 != "content-length"
            })
          let query = case url.query {
            None -> ""
            Some(query) -> "?" <> query
          }
          let init =
            fetch.RequestBitsInit(
              fetch.request_method(request),
              headers,
              result.unwrap(body, <<>>),
              None,
            )
          let target = case string.ends_with(target, "/") {
            True -> string.slice(target, 0, string.length(target) - 1)
            False -> target
          }
          use reply <- promise.map(fetch.send_bits(
            native,
            target <> url.path <> query,
            init,
          ))
          case reply {
            Ok(reply) -> reply
            Error(reason) -> {
              let assert Ok(reply) =
                fetch.new_response(response, reason, 502, [])
              reply
            }
          }
        }
        None -> {
          let found = list.find(assets, fn(asset) { asset.path == url.path })
          let assert Ok(reply) = case found {
            Ok(asset) ->
              fetch.new_response_bits(response, asset.body, 200, [
                #("content-type", asset.content_type),
              ])
            Error(_) -> fetch.new_response(response, "not found", 404, [])
          }
          promise.resolve(reply)
        }
      }
    }),
  )
}
