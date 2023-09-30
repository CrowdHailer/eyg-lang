import gleam/io
import gleam/list
import plinth/node/process
import simplifile
import eygir/decode
import platforms/cli
import platforms/shell
import gleam/javascript/array
import gleam/javascript/promise

// zero arity
pub fn main() {
  do_main(list.drop(array.to_list(process.argv()), 2))
}

// exit can't be used onfunction returns of as a promise
// need to await or work off promises
pub fn do_main(args) {
  let assert Ok(json) = simplifile.read("saved/saved.json")
  let assert Ok(source) = decode.from_json(json)

  case args {
    ["cli", ..rest] -> cli.run(source, rest)
    ["exec", ..rest] -> shell.run(source, rest)
    _ -> {
      io.debug(#("no runner for: ", args))
      process.exit(1)
      promise.resolve(1)
    }
  }
}
