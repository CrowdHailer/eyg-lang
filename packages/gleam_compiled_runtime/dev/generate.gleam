//// Bundle the Gleam runtime as a deterministic compiler code-generation input.

import argv
import gleam/io
import gleam/javascript/promise
import gleam/json
import plinthx/bun/bundle
import plinthx/bun/runtime
import simplifile

const output = "../gleam_compiler/src/eyg/compiler/runtime.gleam"

pub fn main() {
  let assert Ok(bun) = runtime.get()
  let options =
    json.object([
      #(
        "entrypoints",
        json.array(
          ["build/dev/javascript/eyg_compiled_runtime/eyg/compiled/runtime.mjs"],
          json.string,
        ),
      ),
      #("target", json.string("browser")),
      #("format", json.string("cjs")),
      #("minify", json.bool(True)),
    ])
    |> json.to_string
  use built <- promise.await(bundle.build(bun, options))
  let assert Ok(built) = built
  assert bundle.success(built) as "Unable to bundle compiled runtime"
  let assert [artifact] = bundle.outputs(built)
  use javascript <- promise.map(bundle.text(artifact))
  let source =
    "(() => { const module = {exports: {}}; const exports = module.exports;\n"
    <> javascript
    <> "\nreturn module.exports; })()"
  let gleam =
    "//// Generated from packages/gleam_compiled_runtime; run gleam run -m generate there.\n"
    <> "//// Runtime logic is authored in Gleam. Do not edit the generated bundle.\n\n"
    <> "pub const source =\n  "
    <> json.to_string(json.string(source))
    <> "\n\n"
    <> "pub fn defines(name) {\n  case name {\n    \"bind\" | \"fix\" | \"list_fold\" | \"binary_fold\" | \"never\" | \"pure\" -> True\n    _ -> False\n  }\n}\n"
  case argv.load().arguments {
    ["--check"] -> {
      let assert Ok(current) = simplifile.read(output)
      case current == gleam {
        True -> io.println("Compiler runtime is current")
        False -> panic as "Regenerate the compiler runtime"
      }
    }
    [] -> {
      let assert Ok(_) = simplifile.write(output, gleam)
      io.println("Generated " <> output)
    }
    _ -> panic as "expected --check or no arguments"
  }
}
