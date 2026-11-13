import argv
import example_tools
import eyg/compiler
import eyg/parser
import gleam/dict
import gleam/io
import gleam/javascript/promise
import gleam/result
import gleam/string
import simplifile

/// Compile the handler to a module beside the njs entry point.
/// `gleam run -m compile -- handler.eyg dist`
pub fn main() {
  let assert [input, directory] = argv.load().arguments
  let assert Ok(code) = simplifile.read(input)
  let assert Ok(module) = compile(code)
  let assert Ok(Nil) = simplifile.create_directory_all(directory)
  let assert Ok(Nil) = simplifile.write(directory <> "/program.js", module)
  let assert Ok(_) =
    simplifile.write(
      directory <> "/handler.js",
      "import api from './program.js';\nimport { handle } from './host.mjs';\nexport default { handle: request => handle(api, request) };\n",
    )
  use built <- promise.map(example_tools.build(
    "build/dev/javascript/njs/njs/host.mjs",
    directory <> "/host.mjs",
  ))
  let assert Ok(_) = built
  io.println("wrote " <> directory)
}

/// A module exporting the program, or why it was refused.
pub fn compile(code) {
  use source <- result.try(
    parser.all_from_string(code) |> result.replace_error("did not parse"),
  )
  compiler.to_module(source, dict.new())
  |> result.map_error(fn(errors) { string.inspect(errors) })
}
