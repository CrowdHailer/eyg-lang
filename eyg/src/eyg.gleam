import gleam/javascript/array.{Array}
import eygir/decode
import platforms/cli
import platforms/serverless

// document that rad start shell at dollar
// This becomes the entry point
external fn args(Int) -> Array(String) =
  "" "process.argv.slice"

// zero arity
pub fn main() {
  do_main(array.to_list(args(1)))
}

external fn read_file_sync(String, String) -> String =
  "fs" "readFileSync"

pub fn do_main(args) {
  let json = read_file_sync("saved/saved.json", "utf8")
  assert Ok(source) = decode.from_json(json)

  case args {
    ["cli", ..rest] -> cli.run(source, rest)
    ["web", ..rest] -> serverless.run(source, rest)
    _ -> todo("no action matched")
  }
}
