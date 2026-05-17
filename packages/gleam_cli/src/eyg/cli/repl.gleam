import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/hub/cache
import eyg/interpreter/simple_debug
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/parser.{UnexpectEnd} as _
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import input
import simplifile

pub fn execute(config) {
  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )
  let state = execute.State(cwd, config, cache.empty())
  loop("", [], state)
}

fn loop(buffer, scope, state) {
  case input.input("> ") {
    Ok("") -> promise.resolve(Ok(Nil))
    Ok(code) -> {
      let buffer = buffer <> code
      case parser.block_from_string(buffer) {
        Ok(#(#(assignments, tail), _)) -> {
          let tail = option.unwrap(tail, #(ir.Vacant, #(0, 0)))
          let source =
            list.fold_right(assignments, tail, fn(acc, assignment) {
              let #(label, value, at) = assignment
              #(ir.Let(label, value, acc), at)
            })
          let source =
            ir.map_annotation(source, fn(span) {
              source.Location(source.Repl, source.Text(buffer, span))
            })
          use result <- promise.await(execute.block(source, scope, state))
          case result {
            Ok(#(Some(value), scope)) -> {
              io.println(simple_debug.inspect(value))
              loop("", scope, state)
            }
            Ok(#(None, scope)) -> loop("", scope, state)
            Error(#(reason, location, _, _)) -> {
              io.println_error(execute.render_error(reason, location, state.cwd))
              loop("", scope, state)
            }
          }
        }
        Error(UnexpectEnd) -> loop(buffer, scope, state)
        Error(reason) -> {
          io.println(parser.format_error(reason, code))
          loop("", scope, state)
        }
      }
    }
    Error(Nil) -> promise.resolve(Error("failed input."))
  }
}
