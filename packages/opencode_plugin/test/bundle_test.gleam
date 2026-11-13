//// A native host consumes the real standalone file through its public API.

import gleam/dynamic
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/javascript/promise
import gleam/string
import plinthx/javascript/foreign
import plinthx/javascript/module
import simplifile

fn invoke(target, name, arguments) {
  foreign.call(target, name, array.from_list(arguments))
}

pub fn standalone_native_host_uses_policy_context_and_host_callbacks_test() {
  let assert Ok(cwd) = simplifile.current_directory()
  use loaded <- promise.await(module.load(cwd <> "/dist/core.mjs"))
  let assert Ok(api) = loaded
  use created <- promise.await(
    invoke(api, "load_source", [
      dynamic.string("{policy: {task: Pass}, context: {answer: 42}}"),
      dynamic.string(cwd <> "/config.eyg"),
    ])
    |> foreign.to_promise,
  )
  assert invoke(created, "isOk", []) == dynamic.bool(True)
  let config = foreign.index(created, 0)
  let host =
    invoke(api, "host", [
      dynamic.string("Task"),
      dynamic.string("{prompt: String}"),
      dynamic.string("String"),
      foreign.to_dynamic(fn(input, _raw) {
        promise.resolve(foreign.property(input, "prompt"))
      }),
    ])
  let hosts =
    invoke(api, "toList", [foreign.to_dynamic(array.from_list([host]))])
  use report <- promise.map(
    invoke(api, "run", [
      dynamic.string(
        "let _ = perform StandardOut(\"native\\n\") let _ = perform Task({prompt: \"go\"}) context.answer",
      ),
      invoke(api, "config_policy", [config]),
      invoke(api, "config_context", [config]),
      dynamic.string(cwd),
      hosts,
    ])
    |> foreign.to_promise,
  )
  assert invoke(api, "report_ok", [report]) == dynamic.bool(True)
  let assert Ok(text) =
    decode.run(invoke(api, "report_text", [report]), decode.string)
  assert string.contains(text, "native\n")
  assert string.contains(text, "42")
  let effects = invoke(api, "report_effects", [report])
  let effects = invoke(effects, "toArray", [])
  let assert Ok(effects) = decode.run(effects, decode.list(decode.string))
  assert effects == ["StandardOut", "Task"]
}
