import gleam/io
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
  do_main(array.to_list(args(3)))
}

external fn read_file_sync(String, String) -> String =
  "fs" "readFileSync"

external fn exit(Int) -> Nil =
  "" "process.exit"

// exit can't be used on serverless because the run function returns with the server as a promise
// need to await or work off promises
pub fn do_main(args) -> Nil {
  let json = read_file_sync("saved/saved.json", "utf8")
  assert Ok(source) = decode.from_json(json)

  case args {
    ["cli", ..rest] -> cli.run(source, rest)
    ["web", ..rest] -> serverless.run(source, rest)
    _ -> {
      io.debug(#("no runner for: ", args))
      exit(1)
    }
  }
}
