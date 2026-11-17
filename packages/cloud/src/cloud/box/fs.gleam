//// Type check the EYG modules in a file system, with `unixfs/check`.
//// Imports are resolved against the same file system,
//// published modules a module refers to are fetched from the hub.
//// The index of the file system lets a change be checked by checking only what it affects.

import cloud/beam/execute
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/error
import eyg/ir/tree as ir
import eyg/parser
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import multiformats/cid/v1
import unixfs/check
import unixfs/mfs

/// Check every module.
/// Returns a description of every invalid module, so no errors is a valid file system.
pub fn check(
  root: v1.Cid,
  state: execute.State,
) -> mfs.Effect(#(List(String), check.Index, execute.State)) {
  change(check.empty(), root, state)
}

/// Check a later root than the one the index was made from, only checking the modules the change affects.
pub fn change(
  index: check.Index,
  root: v1.Cid,
  state: execute.State,
) -> mfs.Effect(#(List(String), check.Index, execute.State)) {
  use entry <- mfs.Get(root)
  loop(index, entry, state, [])
}

// The cache only has the published modules that have been fetched,
// fetch the ones that are missing and check again, a module that failed is always checked again.
fn loop(index, entry, state: execute.State, fetched) {
  use #(checked, index) <- mfs.then(check.change(index, entry, state.cache))
  let missing =
    dict.values(checked)
    |> list.flat_map(fn(outcome) {
      case outcome {
        Error(check.TypeErrors(errors)) -> error.missing_references(errors)
        _ -> []
      }
    })
    |> list.unique
    |> list.filter(fn(reference) {
      case reference {
        ir.Relative(_) -> False
        _ -> !list.contains(fetched, reference)
      }
    })
  // Check again only if a missing module was found.
  let #(found, state) =
    list.fold(missing, #(False, state), fn(acc, reference) {
      let #(found, state) = acc
      let #(type_, state) = execute.lookup_type(reference, state)
      #(found || result.is_ok(type_), state)
    })
  case found {
    False -> {
      let errors =
        dict.to_list(checked)
        |> list.filter_map(fn(checked) {
          let #(path, outcome) = checked
          case outcome {
            Ok(_) -> Error(Nil)
            Error(problem) ->
              Ok("/" <> string.join(path, "/") <> ": " <> describe(problem))
          }
        })
        |> list.sort(string.compare)
      mfs.Done(#(errors, index, state))
    }
    True -> loop(index, entry, state, list.append(fetched, missing))
  }
}

fn describe(problem) {
  case problem {
    check.MissingModule -> "is missing"
    check.NotUtf8 -> "is not text"
    check.InvalidSource(reason, source) -> parser.format_error(reason, source)
    check.CircularImport(cycle) ->
      "imports itself through "
      <> list.map(cycle, fn(path) { "/" <> string.join(path, "/") })
      |> string.join(", ")
    check.TypeErrors(errors) ->
      list.map(errors, fn(error) { debug.render_reason(error.1) })
      |> string.join("\n")
  }
}
