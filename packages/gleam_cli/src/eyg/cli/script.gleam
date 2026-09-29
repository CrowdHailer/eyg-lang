import eyg/cli/internal/config
import eyg/hub/cache
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/list
import gleam/option.{None, Some}
import loam/execute
import loam/source
import loam/system

pub fn execute(
  input: source.Input,
  arguments: List(String),
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use cwd <- system.then(system.cwd())
  use cwd <- system.try(cwd)
  use input <- system.try(source.normalize_input(cwd, input))
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))

  let state = execute.State(config.client.origin, cache.empty())
  // The synthetic `.script(arguments)` wrapper carries the user source's
  // location so any error here is rendered against the actual source.
  let user_meta = source.1
  let arguments =
    list.map(arguments, fn(arg) { #(ir.String(arg), user_meta) })
    |> wrap_list(user_meta)
  let source = #(
    ir.Apply(
      #(ir.Apply(#(ir.Select("script"), user_meta), source), user_meta),
      arguments,
    ),
    user_meta,
  )

  use result <- system.map(execute.block(source, [], state))
  case result {
    Ok(#(Some(exit_code), _)) ->
      case cast.as_integer(exit_code) {
        Ok(exit_code) -> Ok(exit_code)
        Error(reason) ->
          Error(execute.render_error(reason, user_meta, state.Empty, cwd))
      }
    Ok(#(None, _)) -> Ok(0)
    Error(#(reason, location, _, k)) -> {
      Error(execute.render_error(reason, location, k, cwd))
    }
  }
}

fn wrap_list(items, meta) {
  list.fold_right(items, #(ir.Tail, meta), fn(acc, item) {
    #(ir.Apply(#(ir.Apply(#(ir.Cons, meta), item), meta), acc), meta)
  })
}
