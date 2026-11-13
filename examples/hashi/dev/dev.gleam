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
  let assert Ok(original) =
    site.file("/vendor/hashi.css", "vendor/hashi.css", "text/css")
  let assert Ok(style) = site.file("/main.css", "main.css", "text/css")
  let assert Ok(library) =
    site.file("/library.eyg", "library.eyg", "text/plain; charset=utf-8")
  let assert Ok(guide) =
    site.file(
      "/syntax.md",
      "../../guides/syntax.md",
      "text/plain; charset=utf-8",
    )
  let assert Ok(local) =
    site.serve(site.environment(7822), [
      index,
      app,
      original,
      style,
      library,
      guide,
    ])
  io.println(
    "Hashi listening on http://127.0.0.1:" <> int.to_string(server.port(local)),
  )
}
