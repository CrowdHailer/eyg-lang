import gleam/io
import gleam/list
import plinth/node/process
import simplifile
import eygir/decode
import platforms/shell
import gleam/javascript/array
import gleam/javascript/promise
import magpie/magpie

// zero arity
pub fn main() {
  do_main(list.drop(array.to_list(process.argv()), 2))
}

// exit can't be used onfunction returns of as a promise
// need to await or work off promises
pub fn do_main(args) {
  let assert Ok(json) = simplifile.read("saved/saved.json")
  let assert Ok(source) = decode.from_json(json)

  // heroku copy all files use gleam run
  // in browser but proxy in netlify
  // copy build directory but how do I make exec look the same
  //   - JSON is not copied in build step
  // Go style serverless
  // What is the common entry point I want
  // recipe is an app, service worker makes js necessay, query string params are also only interesting if rendered with JS

  case args {
    ["exec", ..] -> shell.run(source)
    [magpie, ..rest] -> magpie.main(rest)
    _ -> {
      io.debug(#("no runner for: ", args))
      process.exit(1)
      promise.resolve(1)
    }
  }
}
