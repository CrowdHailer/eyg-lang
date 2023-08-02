import gleam/io
import gleam/list
import plinth/node/process
import plinth/nodejs/fs
import eygir/decode
import platforms/cli
import platforms/serverless
import gleam/javascript/array
import gleam/javascript/promise

// zero arity
pub fn main() {
  do_main(list.drop(array.to_list(process.argv()), 2))
}

// exit can't be used on serverless because the run function returns with the server as a promise
// need to await or work off promises
pub fn do_main(args) {
  let json = fs.read_file_sync("saved/saved.json")
  let assert Ok(source) = decode.from_json(json)

  case args {
    ["cli", ..rest] -> cli.run(source, rest)
    ["web", ..rest] -> serverless.run(source, rest)
    _ -> {
      io.debug(#("no runner for: ", args))
      process.exit(1)
      promise.resolve(1)
    }
  }
}
