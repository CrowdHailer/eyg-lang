//// Perform type inference over a whole filesystem.
//// This asserts that all imports resolve and the file contents are consistent with their usage.
////
//// The expected use for this checking is to combine `load_files` and the `files` check function.
//// Note that all files are loaded into memory.
//// This allows us to separate loading files from running the check and separates handling of effects.
//// 
//// A future implementation could load all files references.
//// Starting from a list of links in a directory would ensure we had a cid for all files.
//// The lazy_files loop would use midas continuations with injected effect functions for getting blob content and pulling from the hub.
//// The lazy version might not make sense as it would exist to improve memory performance.
//// In which case dropping the midas abstraction and building a concrete version for the BEAM that understood the processes, ets tables backing caches might be simpler.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/hub/cache
import eyg/ir/tree as ir
import eyg/parser
import eyg/parser/parser.{type Reason} as _
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string
import unixfs
import unixfs/mfs

pub type Path =
  List(String)

pub type Problem {
  MissingModule
  NotUtf8
  InvalidSource(Reason, String)
  CircularImport(List(Path))
  TypeErrors(List(#(#(Int, Int), error.Reason)))
}

type Checker {
  Checker(
    files: Dict(Path, BitArray),
    checked: Dict(Path, Result(binding.Poly, Problem)),
  )
}

/// From an entry point load all files and type check them with the given cache.
/// 
/// This function does not pull new values into the cache.
pub fn entry(
  entry: mfs.Entry,
  cache: cache.Cache(meta),
) -> mfs.Effect(Dict(Path, Result(binding.Poly, Problem))) {
  use remaining <- mfs.then(load_files(entry))

  mfs.Done(cache_loop(files(remaining), cache))
}

fn cache_loop(step, cache) {
  case step {
    infer.Done(value) -> value
    infer.Lookup(reference:, resume:) -> {
      let type_ =
        cache.get_reference(cache, reference)
        |> result.map(fn(module) { module.type_ })
      cache_loop(resume(type_), cache)
    }
  }
}

/// Check the type of a set of already loaded files
/// The caller of this function needs to loop through all package lookups.
pub fn files(
  files: List(#(List(String), BitArray)),
) -> infer.Step(Dict(List(String), Result(binding.Poly, Problem))) {
  do_files(files, dict.from_list(files), dict.new())
}

fn do_files(remaining, all_files, checked) {
  case remaining {
    [] -> infer.Done(checked)
    [#(path, _content), ..remaining] ->
      case is_entry_file(path) {
        False -> do_files(remaining, all_files, checked)
        True -> {
          use #(_, checker) <- infer.bind(
            check_module(Checker(all_files, checked), path, []),
          )
          do_files(remaining, all_files, checker.checked)
        }
      }
  }
}

fn is_entry_file(path) {
  case list.last(path) {
    Ok(name) -> string.ends_with(name, ".eyg")
    Error(Nil) -> True
  }
}

/// Load all files from an entry starting point.
/// This could be moved to the unixfs module.
pub fn load_files(
  entry: mfs.Entry,
) -> mfs.Effect(List(#(List(String), BitArray))) {
  do_load_files(entry, [])
}

fn do_load_files(entry, reversed) {
  case entry {
    mfs.File(contents:) -> mfs.Done([#(list.reverse(reversed), contents)])
    mfs.Directory(links:) -> {
      use files <- mfs.then(
        mfs.each(links, fn(link) {
          let unixfs.Link(cid:, name:, size: _) = link
          use entry <- mfs.Get(cid)
          do_load_files(entry, [name, ..reversed])
        }),
      )
      mfs.Done(list.flatten(files))
    }
  }
}

fn check_module(
  checker: Checker,
  path: Path,
  importing: List(Path),
) -> infer.Step(#(Result(binding.Poly, Problem), Checker)) {
  case dict.get(checker.checked, path) {
    Ok(type_) -> infer.Done(#(type_, checker))
    Error(Nil) -> {
      case cycle_check(importing, path) {
        Ok(Nil) -> {
          use #(outcome, checker) <- infer.bind(
            case dict.get(checker.files, path) {
              Ok(source) -> {
                case bit_array.to_string(source) {
                  Ok(source) ->
                    case parser.all_from_string(source) {
                      Error(reason) ->
                        infer.Done(#(
                          Error(InvalidSource(reason, source)),
                          checker,
                        ))
                      Ok(source) -> {
                        infer.check(infer.pure(), source)
                        |> loop(checker, path, [path, ..importing])
                      }
                    }
                  Error(Nil) -> infer.Done(#(Error(NotUtf8), checker))
                }
              }

              Error(Nil) -> infer.Done(#(Error(MissingModule), checker))
            },
          )
          infer.Done(#(
            outcome,
            Checker(
              ..checker,
              checked: dict.insert(checker.checked, path, outcome),
            ),
          ))
        }
        Error(cycle) -> infer.Done(#(Error(CircularImport(cycle)), checker))
      }
    }
  }
}

fn loop(step, checker, path, importing) {
  case step {
    infer.Done(analysis) -> {
      let outcome = case infer.all_errors(analysis) {
        [] -> Ok(infer.poly_type(analysis))
        errors -> Error(TypeErrors(errors))
      }
      infer.Done(#(outcome, checker))
    }
    infer.Lookup(ir.Relative(location), resume) -> {
      use #(type_, checker) <- infer.bind(case resolve(path, location) {
        Ok(target) -> check_module(checker, target, importing)
        Error(problem) -> infer.Done(#(Error(problem), checker))
      })
      let type_ = result.replace_error(type_, Nil)
      loop(resume(type_), checker, path, importing)
    }
    infer.Lookup(reference, resume) -> {
      infer.Lookup(reference, fn(type_) {
        loop(resume(type_), checker, path, importing)
      })
    }
  }
}

// Links are already well-formed segments. Only import text needs normalising.
// Parent components at the virtual root stay at the root.
fn resolve(path: Path, location: String) -> Result(Path, Problem) {
  case location == "" || string.contains(location, "\u{0}") {
    True -> Error(MissingModule)
    False -> {
      let reversed = case string.starts_with(location, "/") {
        True -> []
        False -> list.drop(list.reverse(path), 1)
      }
      string.split(location, "/")
      |> list.fold(reversed, fn(parts, part) {
        case part {
          "" | "." -> parts
          ".." -> list.drop(parts, 1)
          _ -> [part, ..parts]
        }
      })
      |> list.reverse
      |> Ok
    }
  }
}

fn cycle_check(visited, path) {
  do_cycle_check(visited, path, [])
}

fn do_cycle_check(visited, path, acc) {
  case visited {
    [] -> Ok(Nil)
    [parent, ..] if parent == path -> Error([path, ..acc])
    [parent, ..rest] -> do_cycle_check(rest, path, [parent, ..acc])
  }
}
