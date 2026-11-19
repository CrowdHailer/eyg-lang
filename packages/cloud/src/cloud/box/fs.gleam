//// Type check every EYG module in a file system.
//// Imports are resolved against the same file system.
//// 
//// Each module is checked only once.
//// Import cycles are guarded against.

import cloud/beam/execute
import cloud/file_system
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/ir/tree as ir
import eyg/parser
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1
import simplifile.{type FileError}
import touch_grass/file_system/read_directory
import unixfs/mfs

type Checker {
  Checker(
    state: execute.State,
    checked: Dict(String, Result(binding.Poly, Nil)),
    errors: List(String),
  )
}

/// Returns a description of every invalid module, so no errors is a valid file system.
pub fn check(
  root: v1.Cid,
  state: execute.State,
) -> mfs.Effect(Result(#(List(String), execute.State), FileError)) {
  use paths <- mfs.then(modules(root, ""))
  use paths <- mfs.try(paths)
  use checker <- mfs.then(
    fold(paths, Checker(state, dict.new(), []), fn(checker, path) {
      use #(_, checker) <- mfs.then(check_module(checker, root, path, []))
      mfs.Done(Ok(checker))
    }),
  )
  use checker <- mfs.try(checker)
  mfs.Done(Ok(#(list.reverse(checker.errors), checker.state)))
}

fn fold(items, acc, with) {
  case items {
    [] -> mfs.Done(Ok(acc))
    [item, ..rest] -> {
      use acc <- mfs.then(with(acc, item))
      use acc <- mfs.try(acc)
      fold(rest, acc, with)
    }
  }
}

fn modules(root, directory) -> mfs.Effect(Result(List(String), FileError)) {
  use entries <- mfs.then(file_system.read_directory(root, directory <> "/"))
  use entries <- mfs.try(entries)
  fold(entries, [], fn(found, entry) {
    let path = directory <> "/" <> entry.0
    case entry.1 {
      read_directory.Directory -> {
        use nested <- mfs.then(modules(root, path))
        use nested <- mfs.try(nested)
        mfs.Done(Ok(list.append(found, nested)))
      }
      read_directory.File(_) ->
        mfs.Done(
          Ok(case string.ends_with(path, ".eyg") {
            True -> list.append(found, [path])
            False -> found
          }),
        )
    }
  })
}

// `importing` is the sequence of modules that lead to this one.
fn check_module(checker: Checker, root, path, importing) {
  case dict.get(checker.checked, path) {
    Ok(type_) -> mfs.Done(#(type_, checker))
    Error(Nil) -> {
      use #(outcome, checker) <- mfs.then(case list.contains(importing, path) {
        True -> mfs.Done(#(Error("imports itself"), checker))
        False -> {
          use bytes <- mfs.then(file_system.read(root, path))
          let bytes = result.map_error(bytes, simplifile.describe_error)
          case result.try(bytes, parse) {
            Error(reason) -> mfs.Done(#(Error(reason), checker))
            Ok(source) ->
              infer.check(infer.pure(), source)
              |> loop(checker, root, path, [path, ..importing])
          }
        }
      })
      let #(type_, errors) = case outcome {
        Ok(type_) -> #(Ok(type_), checker.errors)
        Error(reason) -> #(Error(Nil), [
          path <> ": " <> reason,
          ..checker.errors
        ])
      }
      let checked = dict.insert(checker.checked, path, type_)
      mfs.Done(#(type_, Checker(..checker, checked:, errors:)))
    }
  }
}

fn parse(bytes) {
  use code <- result.try(
    bit_array.to_string(bytes) |> result.replace_error("is not text"),
  )
  parser.all_from_string(code)
  |> result.map_error(parser.format_error(_, code))
}

fn loop(step, checker: Checker, root, path, importing) {
  case step {
    infer.Done(analysis) ->
      mfs.Done(case infer.all_errors(analysis) {
        [] -> #(Ok(infer.poly_type(analysis)), checker)
        errors -> #(
          errors
            |> list.map(fn(error) { debug.render_reason(error.1) })
            |> string.join("\n")
            |> Error,
          checker,
        )
      })
    infer.Lookup(ir.Relative(location), resume) -> {
      let target = case location {
        "/" <> _ -> location
        _ -> path <> "/../" <> location
      }
      use #(type_, checker) <- mfs.then(case file_system.resolve_path(target) {
        Ok(target) -> check_module(checker, root, target, importing)
        Error(_) -> mfs.Done(#(Error(Nil), checker))
      })
      loop(resume(type_), checker, root, path, importing)
    }
    infer.Lookup(reference, resume) -> {
      let #(type_, state) = execute.lookup_type(reference, checker.state)
      let type_ = result.replace_error(type_, Nil)
      loop(resume(type_), Checker(..checker, state:), root, path, importing)
    }
  }
}
