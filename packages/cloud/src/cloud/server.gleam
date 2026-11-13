//// The cloud's HTTP server, it serves artifacts.
////
//// | Request | Response |
//// | --- | --- |
//// | `GET /` | A list of artifacts |
//// | `GET /artifacts/<name>/<path>` | A file from the latest version, `index.html` for an empty path |
//// | `GET /artifacts/<name>/v/<version>/<path>` | A file from a version |
////
//// Artifact files are served with a sandbox content security policy,
//// so scripts in a bundle run in an opaque origin without network access.

import cloud/artifacts
import gleam/bytes_tree
import gleam/erlang/process.{type Subject}
import gleam/http/response.{type Response}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleam/uri
import howdy
import howdy/content.{type Content}
import howdy/controller.{type Context as Request}

pub fn start(port: Int, store: Subject(artifacts.Message)) {
  app(store)
  |> howdy.bind(to: "0.0.0.0")
  |> howdy.listening(on: port)
  |> howdy.start
}

pub fn app(store: Subject(artifacts.Message)) -> howdy.App {
  let routes =
    controller.new("/")
    |> controller.get("/", fn(_) { index(store) })
    |> controller.get("/artifacts", fn(_) { index(store) })
    |> controller.get("/artifacts/:name/v/:version/*path", fn(ctx) {
      case int.parse(param(ctx, "version")) {
        Ok(version) ->
          serve(store, param(ctx, "name"), Some(version), param(ctx, "path"))
        Error(Nil) -> text(404, "not found")
      }
    })
    |> controller.get("/artifacts/:name/*path", fn(ctx) {
      serve(store, param(ctx, "name"), None, param(ctx, "path"))
    })
    |> controller.get("/artifacts/:name", fn(ctx) {
      serve(store, param(ctx, "name"), None, "")
    })
    |> controller.build
  howdy.new() |> howdy.controller(routes)
}

fn param(ctx: Request, name) {
  controller.param(ctx, name)
  |> result.unwrap("")
  |> uri.percent_decode
  |> result.unwrap("")
}

fn serve(store, name, version, path) {
  case artifacts.call(store, artifacts.Get(name, version, _)) {
    Error(reason) -> text(404, reason)
    Ok(#(_version, bundle)) ->
      case artifacts.file(bundle, path) {
        Error(Nil) -> text(404, "not found")
        Ok(file) ->
          response.new(200)
          |> response.set_header("content-type", file.media_type)
          |> response.set_header(
            "content-security-policy",
            "sandbox allow-scripts; default-src 'self' 'unsafe-inline' data:",
          )
          |> response.set_body(
            content.Bytes(bytes_tree.from_bit_array(file.content)),
          )
      }
  }
}

fn index(store) {
  let rows =
    artifacts.call(store, artifacts.List)
    |> list.map(fn(entry) {
      let #(name, artifact) = entry
      let href = "/artifacts/" <> uri.percent_encode(name) <> "/"
      let sharing = case artifact.shared {
        True -> "shared"
        False -> "private"
      }
      "<li><a href=\""
      <> href
      <> "\">"
      <> escape(name)
      <> "</a> by #"
      <> escape(artifact.owner.name)
      <> ", "
      <> int.to_string(list.length(artifact.versions))
      <> " versions, "
      <> sharing
      <> "</li>"
    })
    |> string.concat
  html(
    "<!doctype html><title>Artifacts</title><style>body{font-family:sans-serif;margin:2em}</style><h1>Artifacts</h1><ul>"
    <> rows
    <> "</ul>",
  )
}

fn escape(text) {
  text
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

fn html(body) -> Response(Content) {
  response.new(200)
  |> response.set_header("content-type", "text/html; charset=utf-8")
  |> response.set_body(content.Text(body))
}

fn text(status, body) -> Response(Content) {
  response.new(status)
  |> response.set_body(content.Text(body))
}
