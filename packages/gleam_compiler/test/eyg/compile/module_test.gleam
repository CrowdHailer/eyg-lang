import eyg/compiler
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import plinthx/javascript/foreign
import plinthx/javascript/module
import plinthx/node/fs
import plinthx/node/timers
import simplifile

fn compile(code) {
  let assert Ok(source) = parser.all_from_string(code)
  compiler.to_module(source, dict.new())
}

fn imported(code) {
  let assert Ok(javascript) = compile(code)
  let assert Ok(directory) = fs.temporary_directory("eyg-module-")
  let path = directory <> "/program.mjs"
  let assert Ok(_) = simplifile.write(path, javascript)
  use loaded <- promise.map(module.load(path))
  let assert Ok(_) = simplifile.delete(directory)
  let assert Ok(loaded) = loaded
  foreign.property(loaded, "default")
}

fn integer(value) {
  let assert Ok(value) = decode.run(value, decode.int)
  value
}

fn handlers() {
  foreign.object(
    array.from_list([
      #(
        "Double",
        foreign.to_dynamic(fn(value) { dynamic.int(integer(value) * 2) }),
      ),
      #(
        "Wait",
        foreign.to_dynamic(fn(value) {
          use _ <- promise.map(timers.sleep(1))
          value
        }),
      ),
    ]),
  )
}

fn run(exported, name, value, handlers) {
  foreign.apply(
    foreign.property(exported, name),
    array.from_list([value, handlers]),
  )
}

pub fn a_pure_program_is_the_exported_value_test() {
  use exported <- promise.map(imported("!int_add(1, 2)"))
  assert foreign.property(exported, "program") == dynamic.int(3)
  assert run(exported, "run", dynamic.int(3), handlers()) == dynamic.int(3)
}

pub fn host_effects_pause_on_import_and_resume_in_order_test() {
  use exported <- promise.map(imported(
    "let a = perform Double(2) !int_add(a, perform Double(10))",
  ))
  let program = foreign.property(exported, "program")
  assert decode.run(
      program,
      decode.field("label", decode.string, decode.success),
    )
    == Ok("Double")
  assert run(exported, "run", program, handlers()) == dynamic.int(24)
  // The suspended program can be resumed independently again.
  assert run(exported, "run", program, handlers()) == dynamic.int(24)
}

pub fn exported_functions_are_callable_from_the_host_test() {
  use exported <- promise.map(imported("(x) -> { perform Double(x) }"))
  let value =
    foreign.apply(
      foreign.property(exported, "program"),
      array.from_list([dynamic.int(21)]),
    )
  assert run(exported, "run", value, handlers()) == dynamic.int(42)
}

pub fn asynchronous_handlers_are_awaited_before_resumption_test() {
  use exported <- promise.await(imported(
    "let a = perform Wait(5) !int_add(a, 1)",
  ))
  use value <- promise.map(
    foreign.to_promise(run(
      exported,
      "runAsync",
      foreign.property(exported, "program"),
      handlers(),
    )),
  )
  assert value == dynamic.int(6)
}

pub fn programs_handle_local_effects_before_reaching_the_host_test() {
  use exported <- promise.map(imported(
    "handle Local((n, resume) -> { resume(!int_add(n, 1)) }, (_) -> { perform Double(perform Local(20)) })",
  ))
  assert run(exported, "run", foreign.property(exported, "program"), handlers())
    == dynamic.int(42)
}

pub fn shallow_return_clauses_survive_a_suspended_host_operation_test() {
  use exported <- promise.map(imported(
    "handle shallow Local((_, _) -> { 0 }, (x) -> { !int_add(x, 1) }, (_) -> { perform Double(20) })",
  ))
  assert run(exported, "run", foreign.property(exported, "program"), handlers())
    == dynamic.int(41)
}

pub fn invalid_and_unresolved_programs_are_not_compiled_test() {
  let assert Error([_]) = compile("!int_add(1, \"two\")")
  let assert Error([_]) = compiler.to_module(ir.package("unknown"), dict.new())
}

pub fn inherited_object_methods_are_not_effect_handlers_test() {
  let source = ir.apply(ir.perform("toString"), ir.unit())
  let assert Ok(javascript) = compiler.to_module(source, dict.new())
  let assert Ok(directory) = fs.temporary_directory("eyg-module-")
  let path = directory <> "/program.mjs"
  let assert Ok(_) = simplifile.write(path, javascript)
  use imported <- promise.await(module.load(path))
  let assert Ok(_) = simplifile.delete(directory)
  let assert Ok(imported) = imported
  let exported = foreign.property(imported, "default")
  use value <- promise.map(
    foreign.to_promise(run(
      exported,
      "runAsync",
      foreign.property(exported, "program"),
      foreign.object(array.from_list([])),
    ))
    |> promise.map(Ok)
    |> promise.rescue(Error),
  )
  let assert Error(reason) = value
  assert decode.run(
      reason,
      decode.at(["eygBreak", "UnhandledEffect"], decode.string),
    )
    == Ok("toString")
}
