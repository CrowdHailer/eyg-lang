//// Bundle the native facade and copy its declaration files using Gleam tooling.

import gleam/io
import gleam/javascript/promise
import gleam/json
import plinthx/bun/bundle
import plinthx/bun/runtime
import simplifile

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(_) = simplifile.create_directory_all("dist")
  let options =
    json.object([
      #(
        "entrypoints",
        json.array(
          [
            "build/dev/javascript/embed_js/eyg.mjs",
            "build/dev/javascript/embed_js/browser_client.mjs",
          ],
          json.string,
        ),
      ),
      #("target", json.string("browser")),
      #("format", json.string("esm")),
      #("outdir", json.string("dist")),
      #("naming", json.object([#("entry", json.string("[name].mjs"))])),
    ])
    |> json.to_string
  use built <- promise.map(bundle.build(bun, options))
  let assert Ok(built) = built
  assert bundle.success(built) as "Unable to bundle the native shell"
  let assert Ok(types) = simplifile.read("eyg.d.ts")
  let assert Ok(_) = simplifile.write("dist/eyg.d.ts", types)
  let assert Ok(_) = simplifile.write("dist/eyg.d.mts", types)
  io.println("Built dist/eyg.mjs and native type declarations")
}
