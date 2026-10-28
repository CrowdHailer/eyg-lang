import build
import example_tools as site
import gleam/int
import gleam/io
import gleam/javascript/promise
import plinthx/bun/server

pub fn main() {
  use _ <- promise.map(build.main())
  let assert Ok(index) =
    site.file("/", "index.html", "text/html; charset=utf-8")
  let assert Ok(app) = site.file("/app.mjs", "dist/app.mjs", "text/javascript")
  let assert Ok(base_style) =
    site.file(
      "/todomvc.css",
      "../todomvc_lustre/node_modules/todomvc-app-css/index.css",
      "text/css",
    )
  let assert Ok(style) =
    site.file("/main.css", "../todomvc_lustre/main.css", "text/css")
  let assert Ok(library) =
    site.file(
      "/library.eyg",
      "../todomvc_lustre/library.eyg",
      "text/plain; charset=utf-8",
    )
  let assert Ok(api) =
    site.file(
      "/eyg.mjs",
      "../../packages/embed_js/dist/eyg.mjs",
      "text/javascript",
    )
  let assert Ok(guide) =
    site.file(
      "/syntax.md",
      "../../guides/syntax.md",
      "text/plain; charset=utf-8",
    )
  let assert Ok(local) =
    site.serve(site.environment(7821), [
      index,
      app,
      base_style,
      style,
      library,
      guide,
      api,
    ])
  io.println(
    "TodoMVC listening on http://127.0.0.1:"
    <> int.to_string(server.port(local)),
  )
}
