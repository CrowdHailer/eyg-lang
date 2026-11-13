//// Standalone policy runtime, built without a host application's source tree.

import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/list
import plinthx/bun/bundle
import plinthx/bun/runtime
import simplifile

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let assert Ok(_) = simplifile.create_directory_all("dist")
  let resources =
    [
      #("dispatcher", "plugin/dispatch-default.eyg"),
      #("plugin", "plugin/default.eyg"),
      #("syntax", "../../guides/syntax.md"),
      #("builtins", "../../guides/builtins_reference.md"),
    ]
    |> list.map(fn(resource) {
      let assert Ok(text) = simplifile.read(resource.1)
      #(resource.0, json.string(text))
    })
    |> json.object
    |> json.to_string
  let assert Ok(_) =
    simplifile.write(
      "build/dev/javascript/opencode_plugin/resources.mjs",
      "export const resources = " <> resources <> ";\n",
    )
  let options =
    json.object([
      #(
        "entrypoints",
        json.array(
          [
            "build/dev/javascript/opencode_plugin/core.mjs",
            "build/dev/javascript/opencode_plugin/dispatch.mjs",
            "build/dev/javascript/opencode_plugin/eyg.mjs",
          ],
          json.string,
        ),
      ),
      #("outdir", json.string("dist")),
      #("naming", json.object([#("entry", json.string("[name].mjs"))])),
      #("format", json.string("esm")),
      #("target", json.string("node")),
      #(
        "external",
        json.array(
          ["ai", "@opencode-ai/plugin", "@opencode-ai/sdk/client"],
          json.string,
        ),
      ),
    ])
    |> json.to_string
  use built <- promise.map(bundle.build(bun, options))
  let assert Ok(built) = built
  assert bundle.success(built)
    as "Unable to build the standalone policy runtime"
  io.println("Built dist/core.mjs, dist/dispatch.mjs and dist/eyg.mjs")
}
