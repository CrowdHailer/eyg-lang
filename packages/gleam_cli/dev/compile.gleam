//// Build host or cross-platform CLI executables using Gleam and Bun's native API.

import argv
import filepath
import gleam/io
import gleam/javascript/promise
import gleam/json
import gleam/result
import gleam/string
import loam/system
import plinthx/bun/bundle
import plinthx/bun/runtime
import simplifile

pub fn main() {
  let #(target, output) = case argv.load().arguments {
    [] -> #("", "dist/eyg")
    [target] -> #(target, "dist/eyg")
    [target, output] -> #(target, output)
    _ -> panic as "expected an optional Bun compile target and output path"
  }
  let assert Ok(_) =
    simplifile.create_directory_all(filepath.directory_name(output))
  let assert Ok(bun) = runtime.get()
  use tag <- promise.await(
    system.run(system.command(
      "git",
      ["describe", "--tags", "--exact-match", "--match", "gleam_cli-*", "HEAD"],
      ".",
    )),
  )
  let version =
    tag
    |> result.map(fn(tag) {
      string.trim(tag) |> string.replace("gleam_cli-", "")
    })
    |> result.unwrap("dev")
  let compile = case target {
    "" -> [#("outfile", json.string(output))]
    target -> [
      #("target", json.string(target)),
      #("outfile", json.string(output)),
    ]
  }
  let options =
    json.object([
      #(
        "entrypoints",
        json.array(["build/dev/javascript/eyg_cli/eyg_cli.mjs"], json.string),
      ),
      #("target", json.string("bun")),
      #("compile", json.object(compile)),
      #(
        "define",
        json.object([
          #("EYG_VERSION", json.string(json.to_string(json.string(version)))),
        ]),
      ),
      #("footer", json.string("main();")),
    ])
    |> json.to_string
  use built <- promise.map(bundle.build(bun, options))
  let assert Ok(built) = built
  assert bundle.success(built) as string.join(bundle.logs(built), "\n")
  io.println("Built " <> output <> " (" <> version <> ")")
}
