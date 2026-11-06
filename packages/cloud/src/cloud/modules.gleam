//// Modules imported from the session's file system.
////
//// A module is a file of EYG source, as text or dag-json. It is checked and
//// evaluated without effects, the same as an import in the CLI. Relative
//// paths are resolved from the directory of the importing file, or from the
//// root for the shell itself.

import cloud/fs
import cloud/store.{type Store}
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/result.{try}
import gleam/string
import multiformats/cid/v1.{type Cid}

/// Values are annotated with paths, as in the shell, though module code
/// carries no useful paths.
pub type Value =
  state.Value(List(Int))

/// Run type checking, answering relative references from the file system
/// and reporting every other reference as unavailable.
pub fn drive(step: infer.Step(a), store: Store, root: Cid) -> a {
  do_drive(step, store, root, "/", [])
}

fn do_drive(step: infer.Step(a), store, root, directory, visiting) -> a {
  case step {
    infer.Done(value) -> value
    infer.Lookup(reference:, resume:) -> {
      let answer = case reference {
        ir.Relative(location) ->
          load(store, root, directory, location, visiting)
          |> result.map(fn(module) { module.0 })
          |> result.replace_error(Nil)
        _ -> Error(Nil)
      }
      do_drive(resume(answer), store, root, directory, visiting)
    }
  }
}

/// The value of the module at `location`, relative to the root.
pub fn value(
  store: Store,
  root: Cid,
  location: String,
) -> Result(Value, String) {
  load(store, root, "/", location, [])
  |> result.map(fn(module) { module.1 })
}

fn load(store, root, directory, location, visiting) {
  let path = resolve(directory, location)
  use Nil <- try(case list.contains(visiting, path) {
    True -> Error("import cycle through " <> path)
    False -> Ok(Nil)
  })
  let visiting = [path, ..visiting]
  let here = parent(path)
  use bytes <- try(
    fs.read_file(store, root, path)
    |> result.map_error(fn(reason) { "can't import " <> path <> ": " <> reason }),
  )
  use code <- try(
    bit_array.to_string(bytes)
    |> result.replace_error("can't import " <> path <> ": not UTF-8 text"),
  )
  use source <- try(
    parse(code)
    |> result.map_error(fn(reason) { "can't import " <> path <> ": " <> reason }),
  )
  let analysis =
    infer.check(infer.pure(), source)
    |> do_drive(store, root, here, visiting)
  use Nil <- try(case infer.all_errors(analysis) {
    [] -> Ok(Nil)
    _ -> Error("can't import " <> path <> ": it has type errors")
  })
  use value <- try(evaluate(
    expression.execute(source, []),
    store,
    root,
    here,
    visiting,
  ))
  Ok(#(infer.poly_type(analysis), value))
}

fn evaluate(result, store, root, directory, visiting) {
  case result {
    Ok(value) -> Ok(value)
    Error(#(break.UndefinedReference(ir.Relative(location)), _, env, k)) -> {
      use #(_type, value) <- try(load(
        store,
        root,
        directory,
        location,
        visiting,
      ))
      evaluate(
        expression.resume(value, env, k),
        store,
        root,
        directory,
        visiting,
      )
    }
    Error(#(reason, _, _, _)) ->
      Error("module failed: " <> simple_debug.describe(reason))
  }
}

/// Parse a module as dag-json, or else as EYG text.
pub fn parse(code: String) -> Result(ir.Node(List(Int)), String) {
  let code = case code {
    "#!" <> rest ->
      case string.split_once(rest, "\n") {
        Ok(#(_, rest)) -> rest
        Error(Nil) -> ""
      }
    _ -> code
  }
  case json.parse(code, dag_json.decoder([])) {
    Ok(source) -> Ok(source)
    Error(_) ->
      case parser.all_from_string(code) {
        Ok(source) -> Ok(ir.map_annotation(source, fn(_) { [] }))
        Error(reason) -> Error(parser.format_error(reason, code))
      }
  }
}

fn resolve(directory, location) {
  let base = case string.starts_with(location, "/") {
    True -> ""
    False -> directory
  }
  "/" <> string.join(fs.segments(base <> "/" <> location), "/")
}

fn parent(path) {
  let segments = fs.segments(path)
  "/" <> string.join(list.take(segments, list.length(segments) - 1), "/")
}
