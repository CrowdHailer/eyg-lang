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
            "build/dev/javascript/pi_extension/index.mjs",
            "build/dev/javascript/pi_extension/bash_only.mjs",
          ],
          json.string,
        ),
      ),
      #("outdir", json.string("dist")),
      #("naming", json.object([#("entry", json.string("[name].mjs"))])),
      #("format", json.string("esm")),
      #("target", json.string("node")),
      #("external", json.array(["@earendil-works/*", "typebox"], json.string)),
    ])
    |> json.to_string
  use built <- promise.map(bundle.build(bun, options))
  let assert Ok(built) = built
  assert bundle.success(built) as "Unable to bundle the pi extension"
  let assert Ok(_) =
    simplifile.copy_file("../../guides/syntax.md", "dist/syntax.md")
  let assert Ok(_) =
    simplifile.copy_file(
      "../opencode_plugin/plugin/default.eyg",
      "dist/default.eyg",
    )
  io.println("Built dist/index.mjs")
}
