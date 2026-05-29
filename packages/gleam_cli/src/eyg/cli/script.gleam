import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/hub/cache
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/ir/tree as ir
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import simplifile

pub fn execute(
  input: source.Input,
  arguments: List(String),
  config: config.Config,
) -> promise.Promise(Result(Int, String)) {
  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )
  use input <- promisex.try_sync(execute.normalize_input(cwd, input))
  use code <- promisex.try_sync(source.read_input(input))
  use source <- promisex.try_sync(source.parse_input(code, input))

  let state = execute.State(config, cache.empty())
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

  use result <- promise.map(execute.block(source, [], state))
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
