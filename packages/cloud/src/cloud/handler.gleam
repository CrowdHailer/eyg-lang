//// Admit a pure native-input handler and decode its work requests.

import cloud/beam/execute
import cloud/work
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import gleam/result
import overlay/check

pub fn check(
  handle: execute.Value,
  input: binding.Mono,
  state: execute.State,
) -> Result(execute.Value, String) {
  use _ <- result.map(
    check.value(
      handle,
      t.Fun(input, t.Empty, t.List(work.type_())),
      #(0, 0),
      fn(reference) { execute.lookup(reference, state).0 },
    ),
  )
  handle
}

pub fn run(
  handle: execute.Value,
  input: execute.Value,
  state: execute.State,
) -> Result(List(work.Work), String) {
  let #(returned, _) =
    execute.pure_loop(expression.call(handle, [#(input, #(0, 0))]), state)
  use value <- result.try(
    returned
    |> result.map_error(fn(error) { simple_debug.describe(error.0) }),
  )
  work.decode(value)
}
