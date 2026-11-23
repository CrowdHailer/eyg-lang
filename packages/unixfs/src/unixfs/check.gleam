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
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{Some}
import gleam/result
import gleam/set
import gleam/string
import touch_grass/file_system
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

// Links are already well-formed segments. Resolve import text from the importing
// file's directory, rejecting traversal above the virtual root.
// TODO touch grass should expose a Path (list of segments based API) or path resolution gets moved lower
fn resolve(path: Path, location: String) -> Result(Path, Problem) {
  let directory =
    path
    |> list.reverse
    |> list.drop(1)
    |> list.reverse
    |> string.join("/")
  use resolved <- result.map(
    file_system.resolve_path(Some("/" <> directory), location)
    |> result.replace_error(MissingModule),
  )
  string.split(resolved, "/") |> list.filter(fn(part) { part != "" })
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

/// What `changed` needs from an earlier check: for each file, a hash of its contents and,
/// for each module, its outcome and the modules it imports. It is only kept in memory.
pub opaque type Index {
  Index(hashes: Dict(Path, BitArray), modules: Dict(Path, Indexed))
}

type Indexed {
  Indexed(outcome: Result(binding.Poly, Problem), imports: List(Path))
}

/// An index of nothing, checking files from it checks every module.
pub fn empty() -> Index {
  Index(dict.new(), dict.new())
}

/// Check the files as `files` does, and index the outcome so later files can be checked with `changed`.
pub fn index(
  files: List(#(Path, BitArray)),
) -> infer.Step(#(Dict(Path, Result(binding.Poly, Problem)), Index)) {
  changed(empty(), files)
}

/// Check a later version of the files the index was made from.
/// The outcome of every module is the same as `files` gives.
/// Only the modules that changed or failed to type check, and the modules that import them, directly or not,
/// are checked again. Modules that failed to type check are checked again because a package they
/// referred to may now be available.
pub fn changed(
  index: Index,
  files: List(#(Path, BitArray)),
) -> infer.Step(#(Dict(Path, Result(binding.Poly, Problem)), Index)) {
  let hashes =
    list.map(files, fn(file) { #(file.0, hash(file.1)) }) |> dict.from_list
  // Files that were added, changed or removed.
  let changed =
    dict.keys(dict.merge(index.hashes, hashes))
    |> list.filter(fn(path) {
      dict.get(index.hashes, path) != dict.get(hashes, path)
    })
  let failed =
    dict.filter(index.modules, fn(_, indexed) {
      case indexed.outcome {
        Error(TypeErrors(_)) -> True
        _ -> False
      }
    })
    |> dict.keys
  // Any file can be imported, so every changed file leads to the modules that import it.
  let affected =
    importers(index.modules, set.from_list(list.append(changed, failed)))
  let kept =
    dict.filter(index.modules, fn(path, _) { !set.contains(affected, path) })
  let checked = dict.map_values(kept, fn(_, indexed) { indexed.outcome })
  use checked <- infer.bind(do_files(files, dict.from_list(files), checked))
  let contents = dict.from_list(files)
  let imports =
    dict.map_values(checked, fn(path, _) {
      case dict.get(kept, path) {
        Ok(indexed) -> indexed.imports
        Error(Nil) ->
          dict.get(contents, path)
          |> result.map(imported(path, _))
          |> result.unwrap([])
      }
    })
  // Only the modules reached from an entry file are kept, as `files` only checks those.
  let roots = dict.keys(checked) |> list.filter(is_entry_file) |> set.from_list
  let reached = reach(imports, roots)
  let checked =
    dict.filter(checked, fn(path, _) { set.contains(reached, path) })
  let modules =
    dict.map_values(checked, fn(path, outcome) {
      Indexed(outcome, dict.get(imports, path) |> result.unwrap([]))
    })
  infer.Done(#(checked, Index(hashes, modules)))
}

fn hash(bytes: BitArray) -> BitArray {
  crypto.hash(crypto.Sha256, bytes)
}

// The paths and every indexed module that imports them.
fn importers(modules: Dict(Path, Indexed), paths) {
  let more =
    dict.fold(modules, paths, fn(paths, path, indexed) {
      case list.any(indexed.imports, set.contains(paths, _)) {
        True -> set.insert(paths, path)
        False -> paths
      }
    })
  case set.size(more) == set.size(paths) {
    True -> paths
    False -> importers(modules, more)
  }
}

// The paths and every path they import, directly or not.
fn reach(imports: Dict(Path, List(Path)), paths) {
  let more =
    set.fold(paths, paths, fn(paths, path) {
      dict.get(imports, path)
      |> result.unwrap([])
      |> list.fold(paths, set.insert)
    })
  case set.size(more) == set.size(paths) {
    True -> paths
    False -> reach(imports, more)
  }
}

// The modules a source imports, nothing if it is not a valid module.
fn imported(path: Path, bytes: BitArray) -> List(Path) {
  case bit_array.to_string(bytes) {
    Ok(source) ->
      case parser.all_from_string(source) {
        Ok(source) ->
          ir.list_references(source)
          |> list.filter_map(fn(reference) {
            case reference {
              ir.Relative(location) ->
                resolve(path, location) |> result.replace_error(Nil)
              _ -> Error(Nil)
            }
          })
          |> list.unique
        Error(_) -> []
      }
    Error(Nil) -> []
  }
}
