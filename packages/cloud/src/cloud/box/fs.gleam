//// Check a UnixFS snapshot, loading published dependencies from the hub on demand.

import cloud/beam/execute
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/parser
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1
import simplifile.{type FileError}
import unixfs/check as checker
import unixfs/mfs

/// Returns a description of every invalid module, so no errors is a valid file system.
pub fn check(
  root: v1.Cid,
  state: execute.State,
) -> mfs.Effect(Result(#(List(String), execute.State), FileError)) {
  use entry <- mfs.Get(root)
  use files <- mfs.then(checker.load_files(entry))
  let #(results, state) = loop(checker.files(files), state)
  let errors =
    results
    |> dict.to_list
    |> list.filter_map(fn(entry) {
      let #(path, outcome) = entry
      case outcome {
        Ok(_) -> Error(Nil)
        Error(problem) -> Ok(render_path(path) <> ": " <> describe(problem))
      }
    })
    |> list.sort(string.compare)
  mfs.Done(Ok(#(errors, state)))
}

fn loop(step, state) {
  case step {
    infer.Done(results) -> #(results, state)
    infer.Lookup(reference, resume) -> {
      let #(type_, state) = execute.lookup_type(reference, state)
      loop(resume(result.replace_error(type_, Nil)), state)
    }
  }
}

fn render_path(path) {
  "/" <> string.join(path, "/")
}

fn describe(problem) {
  case problem {
    checker.MissingModule -> simplifile.describe_error(simplifile.Enoent)
    checker.NotUtf8 -> "is not text"
    checker.InvalidSource(reason, source) -> parser.format_error(reason, source)
    checker.CircularImport(paths) ->
      "circular import: " <> string.join(list.map(paths, render_path), " -> ")
    checker.TypeErrors(errors) ->
      errors
      |> list.map(fn(error) { debug.render_reason(error.1) })
      |> string.join("\n")
  }
}
