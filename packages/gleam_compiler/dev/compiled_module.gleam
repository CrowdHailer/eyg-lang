//// Build and import the actual module from the compiled-module guide.

import eyg/compiler
import eyg/parser
import gleam/dict
import gleam/dynamic
import gleam/io
import gleam/javascript/array
import gleam/javascript/promise
import plinthx/javascript/foreign
import plinthx/javascript/module
import plinthx/node/timers
import simplifile

pub fn main() {
  let assert Ok(source) =
    parser.all_from_string("let n = perform Wait(21) !int_multiply(n, 2)")
  let assert Ok(javascript) = compiler.to_module(source, dict.new())
  let assert Ok(cwd) = simplifile.current_directory()
  let directory = cwd <> "/build/exported"
  let assert Ok(_) = simplifile.create_directory_all(directory)
  let path = directory <> "/program.mjs"
  let assert Ok(_) = simplifile.write(path, javascript)
  use loaded <- promise.await(module.load(path))
  let assert Ok(loaded) = loaded
  let exported = foreign.property(loaded, "default")
  let handlers =
    foreign.object(
      array.from_list([
        #(
          "Wait",
          foreign.to_dynamic(fn(value) {
            use _ <- promise.map(timers.sleep(10))
            value
          }),
        ),
      ]),
    )
  let value =
    foreign.apply(
      foreign.property(exported, "runAsync"),
      array.from_list([
        foreign.property(exported, "program"),
        handlers,
      ]),
    )
  use value <- promise.map(foreign.to_promise(value))
  assert value == dynamic.int(42)
  io.println("PASS build/exported/program.mjs awaited its host and returned 42")
}
