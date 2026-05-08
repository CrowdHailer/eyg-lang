import eyg/cli/internal/execute
import eyg/hub/cache
import eyg/interpreter/simple_debug
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/parser.{UnexpectEnd, describe_reason} as _
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
  let state = execute.State(cwd, config, cache.empty(), fn(_: Nil) { #(0, 0) })
  loop("", [], state)
}

fn loop(buffer, scope, state) {
  case input.input("> ") {
    Ok("") -> promise.resolve(Ok(""))
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
          use result <- promise.await(execute.block(source, scope, state))
          case result {
            Ok(#(Some(value), scope)) -> {
              io.println(simple_debug.inspect(value))
              loop("", scope, state)
            }
            Ok(#(None, scope)) -> loop("", scope, state)
            Error(reason) -> {
              io.println_error(simple_debug.describe(reason))
              loop("", scope, state)
            }
          }
        }
        Error(UnexpectEnd) -> loop(buffer, scope, state)
        Error(reason) -> {
          io.println(describe_reason(reason))
          loop("", scope, state)
        }
      }
    }
    Error(Nil) -> promise.resolve(Error("failed input."))
  }
}
