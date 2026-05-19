import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/hub/cache
import eyg/interpreter/cast
import eyg/interpreter/state
import eyg/ir/tree as ir
import filepath
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
  use code <- promisex.try_sync(source.read_input(input))
  use source <- promisex.try_sync(source.parse_input(code, input))

  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )
  let dir = case input {
    source.File(path:) -> {
      use path <- result.try(execute.resolve_relative(cwd, path))
      Ok(filepath.directory_name(path))
    }
    source.Code(_) | source.Stdin -> Ok(cwd)
  }
  use dir <- promisex.try_sync(dir)
  let state = execute.State(dir, config, cache.empty())

  let arguments =
    list.map(arguments, fn(arg) { #(ir.String(arg), meta) }) |> list

  let source = apply(apply(select("script"), source), arguments)

  use result <- promise.map(execute.block(source, [], state))
  case result {
    Ok(#(Some(exit_code), _)) ->
      case cast.as_integer(exit_code) {
        Ok(exit_code) -> Ok(exit_code)
        Error(reason) ->
          Error(execute.render_error(reason, meta, state.Empty, cwd))
      }
    Ok(#(None, _)) -> Ok(0)
    Error(#(reason, location, _, k)) -> {
      Error(execute.render_error(reason, location, k, cwd))
    }
  }
}

const meta = source.Location(source.Repl, source.Json)

pub fn list(items) {
  do_list(list.reverse(items), tail())
}

pub fn do_list(reversed, acc) {
  case reversed {
    [item, ..rest] -> do_list(rest, apply(apply(cons(), item), acc))
    [] -> acc
  }
}

pub fn tail() {
  #(ir.Tail, meta)
}

pub fn cons() {
  #(ir.Cons, meta)
}

pub fn apply(func, argument) {
  #(ir.Apply(func, argument), meta)
}

pub fn select(label) {
  #(ir.Select(label), meta)
}
