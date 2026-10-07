//// Capture runtime context values without losing their source-relative imports.

import eyg/interpreter/capture
import eyg/interpreter/value
import eyg/ir/tree as ir
import filepath
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import loam/source
import loam/system

pub fn program(
  value: value.Value(source.Location, c),
  meta: source.Location,
  cwd: String,
) -> Result(ir.Node(source.Location), String) {
  case capturable(value) {
    False -> Error("it holds a continuation, which cannot be type checked")
    True -> {
      let code = capture.capture(value, meta)
      let anchored =
        ir.rewrite_pure(code, fn(node) {
          let #(expression, error) = case node.0 {
            ir.Reference(ir.Relative(path)) ->
              case resolve(path, node.1, cwd) {
                Ok(path) -> #(ir.Reference(ir.Relative(path)), None)
                Error(reason) -> #(node.0, Some(reason))
              }
            expression -> #(expression, None)
          }
          #(expression, #(node.1, error))
        })
      let errors =
        ir.get_annotation(anchored)
        |> list.filter_map(fn(meta) { option.to_result(meta.1, Nil) })
      case errors {
        [] -> Ok(ir.map_annotation(anchored, fn(meta) { meta.0 }))
        _ -> Error(string.join(list.unique(errors), "\n"))
      }
    }
  }
}

fn resolve(path, meta: source.Location, cwd) {
  let root = case filepath.is_absolute(path), meta.origin {
    True, _ | False, source.Inline | False, source.Repl | False, source.Pipe ->
      Ok(cwd)
    False, source.Disk(path) -> Ok(filepath.directory_name(path))
    False, _ -> Error("context import has no filesystem origin: " <> path)
  }
  use root <- result.try(root)
  system.resolve_relative(root, path)
  |> result.replace_error("cannot resolve context import: " <> path)
}

fn capturable(value) {
  case value {
    value.Table(facts, rules) ->
      list.all(dict.values(facts), fn(rows) {
        list.all(dict.keys(rows), capturable)
      })
      && list.all(rules, capturable)
    value.LinkedList(items) -> list.all(items, capturable)
    value.Record(fields) -> dict.values(fields) |> list.all(capturable)
    value.Tagged(_, inner) -> capturable(inner)
    value.Closure(parameter, body, env) ->
      list.all(ir.free_variables(body, [parameter]), fn(name) {
        case list.key_find(env, name) {
          Ok(value) -> capturable(value)
          Error(_) -> True
        }
      })
    value.Partial(value.Resume(_), _) -> False
    value.Partial(_, args) -> list.all(args, capturable)
    value.Binary(_) | value.Integer(_) | value.String(_) -> True
  }
}
