import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/dev
import eygir/annotated
import eygir/annotated as e
import eygir/decode
import gleam/dict
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import gleam/list
import magpie/magpie
import midas/node
import platforms/shell
import plinth/javascript/console
import plinth/node/process
import simplifile
import snag

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
    ["develop", ..args] ->
      promise.map(
        node.watch(dev.develop(args), ".", fn(result) {
          case result {
            Ok(Nil) -> Nil
            Error(reason) -> io.println(snag.pretty_print(reason))
          }
        }),
        fn(_) { 0 },
      )
    ["exec", ..] -> shell.run(e.add_annotation(source, Nil))
    ["infer"] -> {
      let #(exp, bindings) =
        infer.infer(source, t.Empty, dict.new(), 0, infer.new_state())
      let acc = annotated.strip_annotation(exp).1
      let errors =
        list.filter_map(acc, fn(row) {
          let #(result, _, _, _) = row
          case result {
            Ok(_) -> Error(Nil)
            Error(reason) -> Ok(io.println(debug.reason(reason)))
          }
        })
      io.debug(#(list.length(errors), list.length(acc)))
      promise.resolve(0)
    }
    ["magpie", ..rest] -> magpie.main(rest)
    _ -> {
      io.debug(#("no runner for: ", args))
      process.exit(1)
      promise.resolve(1)
    }
  }
}
