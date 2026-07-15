import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug as type_debug
import eyg/analysis/type_/isomorphic as t
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
import gleam/string
import input
import simplifile

pub fn execute(input, config) {
  let state = execute.State(config, cache.empty())
  use scope <- promise.try_await(case input {
    Some(input) -> {
      use cwd <- promisex.try_sync(
        simplifile.current_directory()
        |> result.map_error(simplifile.describe_error),
      )
      use input <- promisex.try_sync(execute.normalize_input(cwd, input))
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
  io.println("type /help for shell commands")
  loop("", scope, [], state)
}

// `defs` is the assignments entered so far, kept so `/type` can type
// check an expression against the variables in scope. The runtime
// `scope` holds values, not types, so type checking re-runs inference
// over the accumulated definitions.
fn loop(buffer, scope, defs, state: execute.State) {
  case input.input("> ") {
    Ok("") -> promise.resolve(Ok(0))
    Ok(code) -> {
      use #(output, #(buffer, scope, defs, state)) <- promise.await(handle(
        buffer <> code,
        scope,
        defs,
        state,
      ))

      list.each(output, fn(line) {
        case line {
          Ok(line) -> io.println(line)
          Error(line) -> io.println_error(line)
        }
      })
      loop(buffer, scope, defs, state)
    }
    Error(Nil) -> promise.resolve(Error("failed input."))
  }
}

pub fn handle(code, scope, defs, state) {
  case code {
    "/" <> command -> handle_meta(command, scope, defs, state)
    _ -> {
      case parser.block_from_string(code) {
        Ok(#(#(assignments, tail), _)) -> {
          let tail = option.unwrap(tail, #(tree.Vacant, #(0, 0)))
          let source =
            list.fold_right(assignments, tail, fn(acc, assignment) {
              let #(label, value, at) = assignment
              #(tree.Let(label, value, acc), at)
            })
          let located =
            tree.map_annotation(source, fn(span) {
              source.Location(source.Repl, source.Text(code, span))
            })
          use result <- promise.map(execute.block(located, scope, state))
          case result {
            Ok(#(Some(value), scope)) -> #(
              [Ok(simple_debug.inspect(value))],
              #("", scope, list.append(defs, assignments), state),
            )
            Ok(#(None, scope)) -> #(
              [],
              #("", scope, list.append(defs, assignments), state),
            )
            Error(#(reason, location, _env, k)) -> #(
              [
                Error(execute.render_error(reason, location, k, "/todo")),
              ],
              #("", scope, defs, state),
            )
          }
        }
        Error(UnexpectEnd) ->
          promise.resolve(#([], #(code, scope, defs, state)))
        Error(reason) ->
          promise.resolve(#(
            [Error(parser.format_error(reason, code))],
            #("", scope, defs, state),
          ))
      }
    }
  }
}

fn handle_meta(command, scope, defs, state: execute.State) {
  let #(name, argument) = case string.split_once(command, " ") {
    Ok(#(name, argument)) -> #(name, argument)
    Error(Nil) -> #(string.trim(command), "")
  }
  let message = case name {
    "help" -> help_text
    "scope" -> render_scope(scope)
    "type" | "t" -> type_of(argument, defs, cache.types(state.cache))
    "" -> "missing command, try :help"
    _ -> "unknown command :" <> name <> ", try :help"
  }
  promise.resolve(#([Ok(message)], #("", scope, defs, state)))
}

pub const help_text = "shell commands:
  /help            show this message
  /scope           list the variables in scope
  /trace           show the stack trace of the most recent error
  /type <expr>     infer and show the type of an expression
  /t <expr>        alias for /type
an empty line exits the shell"

/// Render the variables in scope, oldest binding first. A name rebound by
/// a later `let` is shown once, at its most recent value.
pub fn render_scope(scope) -> String {
  let #(_, lines) =
    list.fold(scope, #([], []), fn(acc, entry) {
      let #(seen, lines) = acc
      let #(name, value) = entry
      case list.contains(seen, name) {
        True -> acc
        False -> #([name, ..seen], [
          name <> " = " <> simple_debug.inspect(value),
          ..lines
        ])
      }
    })
  case lines {
    [] -> "(no variables in scope)"
    _ -> string.join(lines, "\n")
  }
}

/// Infer and render the type of `argument`. It is type checked wrapped in
/// `defs`, the assignments entered earlier in the session, so it can
/// refer to the variables in scope. `references` supplies the types of
/// any modules already fetched into the cache.
pub fn type_of(argument: String, defs, references) -> String {
  case string.trim(argument) {
    "" -> "usage: :type <expression>"
    argument ->
      case parser.block_from_string(argument) {
        Error(UnexpectEnd) -> "incomplete expression"
        Error(reason) -> parser.format_error(reason, argument)
        Ok(#(#(assignments, tail), _)) -> {
          let tail = option.unwrap(tail, #(tree.Vacant, #(0, 0)))
          let source =
            list.fold_right(
              list.append(defs, assignments),
              tail,
              fn(acc, assignment) {
                let #(label, value, at) = assignment
                #(tree.Let(label, value, acc), at)
              },
            )
          let context =
            infer.unpure()
            |> infer.with_references(references)
          let analysis = infer.check(context, source)
          case infer.all_errors(analysis) {
            [] ->
              type_debug.render_type(infer.type_(analysis))
              <> effect_summary(analysis)
            [#(_location, reason), ..] ->
              "type error: " <> type_debug.render_reason(reason)
          }
        }
      }
  }
}

// Effects performed by an expression, shown after the value type as
// `! <Effect, ...>`. The inference context is open (any effect is
// allowed), so a pure expression leaves an unbound effect variable,
// which renders as no effects.
fn effect_summary(analysis: infer.Analysis(_)) -> String {
  let #(_node, #(_result, _type, effect, _scope)) = analysis.tree
  case effect_labels(binding.resolve(effect, analysis.bindings)) {
    [] -> ""
    labels -> " ! <" <> string.join(labels, ", ") <> ">"
  }
}

fn effect_labels(effect) -> List(String) {
  case effect {
    t.EffectExtend(label, _, tail) -> [label, ..effect_labels(tail)]
    _ -> []
  }
}
