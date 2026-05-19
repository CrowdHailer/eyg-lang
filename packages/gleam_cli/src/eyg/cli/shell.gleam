import eyg/cli/internal/execute
import eyg/cli/internal/ir
import eyg/cli/internal/source
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/simple_debug
import eyg/ir/tree
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

pub fn execute(input, config) {
  use cwd <- promisex.try_sync(
    simplifile.current_directory()
    |> result.map_error(simplifile.describe_error),
  )

  let state = execute.State(cwd, config, cache.empty())
  use scope <- promise.try_await(case input {
    Some(input) -> {
      use code <- promisex.try_sync(source.read_input(input))
      use source <- promisex.try_sync(source.parse_input(code, input))
      let source = ir.apply(ir.apply(ir.select("shell"), source), ir.unit())
      use result <- promise.await(execute.block(source, [], state))
      case result {
        Ok(#(_, scope)) -> promise.resolve(Ok(scope))
        Error(#(break.UnhandledEffect("Break", _), _, env, _)) ->
          promise.resolve(Ok(env.scope))
        Error(#(reason, location, _, k)) -> {
          promise.resolve(Error(execute.render_error(reason, location, k, cwd)))
        }
      }
    }
    None -> promise.resolve(Ok([]))
  })
  loop("", scope, state)
}

fn loop(buffer, scope, state) {
  case input.input("> ") {
    Ok("") -> promise.resolve(Ok(0))
    Ok(code) -> {
      let buffer = buffer <> code
      case parser.block_from_string(buffer) {
        Ok(#(#(assignments, tail), _)) -> {
          let tail = option.unwrap(tail, #(tree.Vacant, #(0, 0)))
          let source =
            list.fold_right(assignments, tail, fn(acc, assignment) {
              let #(label, value, at) = assignment
              #(tree.Let(label, value, acc), at)
            })
          let source =
            tree.map_annotation(source, fn(span) {
              source.Location(source.Repl, source.Text(buffer, span))
            })
          use result <- promise.await(execute.block(source, scope, state))
          case result {
            Ok(#(Some(value), scope)) -> {
              io.println(simple_debug.inspect(value))
              loop("", scope, state)
            }
            Ok(#(None, scope)) -> loop("", scope, state)
            Error(#(reason, location, _, k)) -> {
              io.println_error(execute.render_error(
                reason,
                location,
                k,
                state.cwd,
              ))
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
