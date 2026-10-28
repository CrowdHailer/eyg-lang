//// Consume the actual bundled native API; all host logic and checks are Gleam.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/json
import gleam/string
import javascript/mutable_reference as reference
import plinthx/javascript/foreign
import plinthx/javascript/module
import plinthx/node/timers
import simplifile

fn data(text) {
  let assert Ok(value) = json.parse(text, decode.dynamic)
  value
}

fn object(fields) {
  foreign.object(array.from_list(fields))
}

fn invoke(target, name, arguments) {
  foreign.apply(foreign.property(target, name), array.from_list(arguments))
}

fn create(options) {
  let assert Ok(cwd) = simplifile.current_directory()
  use loaded <- promise.await(module.load(cwd <> "/dist/eyg.mjs"))
  let assert Ok(loaded) = loaded
  invoke(loaded, "createShell", [data(options)]) |> foreign.to_promise
}

const options =
  "{\"effects\":{\"Add\":{\"lift\":\"integer\",\"lower\":\"integer\"},\"Find\":{\"lift\":\"string\",\"lower\":{\"result\":{\"ok\":{\"record\":{\"id\":\"integer\",\"done\":\"boolean\"}},\"error\":\"unit\"}}}}}"

fn integer(value) {
  let assert Ok(value) = decode.run(value, decode.int)
  value
}

fn counter() {
  let total = reference.new(0)
  object([
    #(
      "Add",
      foreign.to_dynamic(fn(value) {
        let next = reference.get(total) + integer(value)
        reference.set(total, next)
        dynamic.int(next)
      }),
    ),
    #(
      "Find",
      foreign.to_dynamic(fn(name) {
        case name == dynamic.string("a") {
          True -> data("{\"$\":\"Ok\",\"value\":{\"id\":1,\"done\":true}}")
          False -> data("{\"$\":\"Error\"}")
        }
      }),
    ),
  ])
}

fn run(shell, code, handlers) {
  invoke(shell, "run", [dynamic.string(code), handlers])
}

fn run_async(shell, code, handlers) {
  invoke(shell, "runAsync", [dynamic.string(code), handlers])
  |> foreign.to_promise
}

pub fn bundled_api_runs_host_effects_and_retains_bindings_test() {
  use shell <- promise.map(create(options))
  let result = run(shell, "let _ = perform Add(2) perform Add(3)", counter())
  assert result == data("{\"value\":5,\"display\":\"5\"}")
  assert run(shell, "let x = 4", counter()) == object([])
  assert foreign.property(run(shell, "!int_add(x, 1)", counter()), "value")
    == dynamic.int(5)
}

pub fn tagged_records_cross_the_bundle_boundary_as_plain_data_test() {
  use shell <- promise.map(create(options))
  let result = run(shell, "perform Find(\"a\")", counter())
  assert foreign.property(result, "value")
    == data("{\"$\":\"Ok\",\"value\":{\"id\":1,\"done\":true}}")
  let result =
    run(
      shell,
      "match perform Find(\"b\") { Ok(_) -> { 1 } Error(_) -> { 0 } }",
      counter(),
    )
  assert foreign.property(result, "value") == dynamic.int(0)
}

pub fn bundled_shell_rebuilds_dependent_and_destructured_bindings_in_order_test() {
  use shell <- promise.map(create(options))
  let result =
    run(shell, "let a = 1 let {b} = {b: !int_add(a, 1)} b", object([]))
  assert foreign.property(result, "value") == dynamic.int(2)
  assert foreign.property(run(shell, "b", object([])), "value")
    == dynamic.int(2)
}

pub fn offered_effects_and_host_replies_are_checked_test() {
  use shell <- promise.map(create(options))
  let result = run(shell, "perform Launch({})", counter())
  let assert Ok(error) =
    decode.run(result, decode.field("error", decode.string, decode.success))
  assert string.starts_with(error, "The code did not type check, nothing ran.")
  let result =
    run(
      shell,
      "perform Add(1)",
      object([
        #("Add", foreign.to_dynamic(fn(_) { dynamic.string("one") })),
      ]),
    )
  let assert Ok(error) =
    decode.run(result, decode.field("error", decode.string, decode.success))
  assert string.contains(error, "reply \"one\" is not a Integer")
}

pub fn modules_are_loaded_and_the_readme_field_defaults_test() {
  use shell <- promise.map(create(
    "{\"effects\":{\"Add\":{\"lift\":\"integer\",\"lower\":\"integer\"}},\"modules\":{\"lib\":\"{readme: \\\"Adds\\\", twice: (n) -> { let _ = perform Add(n) perform Add(n) }}\"}}",
  ))
  assert invoke(shell, "text", [dynamic.string("lib")])
    == dynamic.string("Adds")
  let result = run(shell, "lib.twice(3)", counter())
  assert foreign.property(result, "value") == dynamic.int(6)
}

pub fn native_handlers_may_return_promises_test() {
  use shell <- promise.await(create(options))
  let handlers =
    object([
      #(
        "Add",
        foreign.to_dynamic(fn(value) {
          use _ <- promise.map(timers.sleep(1))
          dynamic.int(integer(value) * 2)
        }),
      ),
    ])
  use result <- promise.map(run_async(shell, "perform Add(7)", handlers))
  assert foreign.property(result, "value") == dynamic.int(14)
}

pub fn async_runs_are_serialized_and_sync_runs_cannot_overwrite_them_test() {
  use shell <- promise.await(create(options))
  let handlers =
    object([
      #(
        "Add",
        foreign.to_dynamic(fn(value) {
          use _ <- promise.map(timers.sleep(5))
          value
        }),
      ),
    ])
  let first = run_async(shell, "let x = perform Add(1)", handlers)
  let second = run_async(shell, "!int_add(x, 1)", handlers)
  let refused =
    foreign.try_apply(
      foreign.to_dynamic(fn() { run(shell, "let x = 99", handlers) }),
      array.from_list([]),
    )
  let assert Error(_) = refused
  use first <- promise.await(first)
  assert first == object([])
  use second <- promise.map(second)
  assert foreign.property(second, "value") == dynamic.int(2)
  assert foreign.property(run(shell, "x", object([])), "value")
    == dynamic.int(1)
}

pub fn a_throwing_host_does_not_leave_the_shell_busy_test() {
  use shell <- promise.await(create(options))
  let handlers =
    object([
      #(
        "Add",
        foreign.to_dynamic(fn(_) { foreign.raise(foreign.error("host failed")) }),
      ),
    ])
  let refused =
    foreign.try_apply(
      foreign.to_dynamic(fn() { run(shell, "perform Add(1)", handlers) }),
      array.from_list([]),
    )
  let assert Error(_) = refused
  assert foreign.property(run(shell, "42", object([])), "value")
    == dynamic.int(42)
  let first =
    run_async(shell, "perform Add(1)", handlers)
    |> promise.map(Ok)
    |> promise.rescue(Error)
  let second = run_async(shell, "let n = 7 n", object([]))
  use first <- promise.await(first)
  let assert Error(_) = first
  use second <- promise.map(second)
  assert foreign.property(second, "value") == dynamic.int(7)
  assert foreign.property(run(shell, "n", object([])), "value")
    == dynamic.int(7)
}

pub fn undefined_replies_are_unit_and_sync_calls_reject_promises_test() {
  use shell <- promise.await(create(
    "{\"effects\":{\"Print\":{\"lift\":\"string\",\"lower\":\"unit\"}}}",
  ))
  let handlers = object([#("Print", foreign.to_dynamic(fn(_) { Nil }))])
  assert foreign.property(
      run(shell, "perform Print(\"hi\")", handlers),
      "value",
    )
    == object([])
  let handlers =
    object([#("Print", foreign.to_dynamic(fn(_) { promise.resolve(Nil) }))])
  let refused =
    foreign.try_apply(
      foreign.to_dynamic(fn() { run(shell, "perform Print(\"hi\")", handlers) }),
      array.from_list([]),
    )
  let assert Error(_) = refused
  use result <- promise.map(run_async(shell, "perform Print(\"hi\")", handlers))
  assert foreign.property(result, "value") == object([])
}

pub fn configuration_and_module_errors_reject_creation_test() {
  use invalid <- promise.await(
    create("{\"effects\":{\"Bad\":{}}}")
    |> promise.map(Ok)
    |> promise.rescue(Error),
  )
  let assert Error(_) = invalid
  use invalid <- promise.await(
    create("{\"effects\":{},\"hub\":\"not an origin\"}")
    |> promise.map(Ok)
    |> promise.rescue(Error),
  )
  let assert Error(_) = invalid
  use invalid <- promise.map(
    create("{\"effects\":{},\"modules\":{\"bad\":\"perform Launch({})\"}}")
    |> promise.map(Ok)
    |> promise.rescue(Error),
  )
  let assert Error(_) = invalid
}
