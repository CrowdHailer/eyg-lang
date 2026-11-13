//// Admit a pure native-input handler and decode its work requests.

import cloud/beam/execute
import cloud/check
import cloud/work
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import gleam/result

pub fn check(type_: binding.Poly, input: binding.Mono) -> Result(Nil, String) {
  check.matches(type_, t.Fun(input, t.Empty, t.List(work.type_())))
}

pub fn select_type(type_: binding.Poly, platform: String) {
  case type_ {
    t.Record(_) ->
      check.field(type_, platform) |> result.or(check.field(type_, "fallback"))
    _ -> Ok(type_)
  }
}

pub fn select(value: execute.Value, platform: String) {
  case value {
    v.Record(_) ->
      cast.field(platform, Ok, value)
      |> result.or(cast.field("fallback", Ok, value))
    _ -> Ok(value)
  }
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
