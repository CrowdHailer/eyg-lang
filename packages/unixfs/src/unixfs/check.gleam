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
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import multiformats/cid/v1
import unixfs
import unixfs/mfs

/// A path relative to the entry being checked. The entry itself is `[]`.
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

/// Load a snapshot and check every `.eyg` file, checking imports on demand.
/// A file entry is checked as a single module at `[]`.
/// Published imports use the supplied cache's modules and release mappings.
/// Storage failures are handled by the MFS runner.
pub fn entry(
  entry: mfs.Entry,
  cache: cache.Cache(meta),
) -> mfs.Effect(Dict(Path, Result(binding.Poly, Problem))) {
  use files <- mfs.then(load_files(entry, []))
  let state = Checker(dict.from_list(files), dict.new())
  let checker =
    list.fold(files, state, fn(checker, file) {
      let #(path, _) = file
      let check = case list.last(path) {
        Ok(name) -> string.ends_with(name, ".eyg")
        Error(Nil) -> True
      }
      case check {
        True -> check_module(checker, path, [], cache).1
        False -> checker
      }
    })

  mfs.Done(checker.checked)
}

fn load_files(entry, reversed) {
  case entry {
    mfs.File(contents:) -> mfs.Done([#(list.reverse(reversed), contents)])
    mfs.Directory(links:) -> {
      use files <- mfs.then(
        mfs.each(links, fn(link) {
          let unixfs.Link(cid:, name:, size: _) = link
          use entry <- mfs.Get(cid)
          load_files(entry, [name, ..reversed])
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
  cache: cache.Cache(meta),
) -> #(Result(binding.Poly, Problem), Checker) {
  case dict.get(checker.checked, path) {
    Ok(type_) -> #(type_, checker)
    Error(Nil) -> {
      case cycle_check(importing, path) {
        Ok(Nil) -> {
          let #(outcome, checker) = case dict.get(checker.files, path) {
            Ok(source) -> {
              case bit_array.to_string(source) {
                Ok(source) ->
                  case parser.all_from_string(source) {
                    Error(reason) -> #(
                      Error(InvalidSource(reason, source)),
                      checker,
                    )
                    Ok(source) ->
                      infer.check(infer.pure(), source)
                      |> loop(checker, path, [path, ..importing], cache)
                  }
                Error(Nil) -> #(Error(NotUtf8), checker)
              }
            }

            Error(Nil) -> #(Error(MissingModule), checker)
          }
          #(
            outcome,
            Checker(
              ..checker,
              checked: dict.insert(checker.checked, path, outcome),
            ),
          )
        }
        Error(cycle) -> #(Error(CircularImport(cycle)), checker)
      }
    }
  }
}

fn loop(step, checker, path, importing, cache) {
  case step {
    infer.Done(analysis) -> {
      let outcome = case infer.all_errors(analysis) {
        [] -> Ok(infer.poly_type(analysis))
        errors -> Error(TypeErrors(errors))
      }
      #(outcome, checker)
    }
    infer.Lookup(ir.Relative(location), resume) -> {
      let #(type_, checker) = case resolve(path, location) {
        Ok(target) -> check_module(checker, target, importing, cache)
        Error(problem) -> #(Error(problem), checker)
      }
      let type_ = result.replace_error(type_, Nil)
      loop(resume(type_), checker, path, importing, cache)
    }
    infer.Lookup(reference, resume) -> {
      let type_ =
        cache.get_reference(cache, reference)
        |> result.map(fn(module) { module.type_ })
      loop(resume(type_), checker, path, importing, cache)
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

/// What `change` needs from an earlier check: the root that was checked and, for each module,
/// its outcome and the modules it imports. It is only kept in memory.
pub opaque type Index {
  Index(root: Option(v1.Cid), modules: Dict(Path, Indexed))
}

type Indexed {
  Indexed(outcome: Result(binding.Poly, Problem), imports: List(Path))
}

/// An index of nothing, checking a change from it checks every module.
pub fn empty() -> Index {
  Index(None, dict.new())
}

/// Check every module, as `entry` does, and index the outcome so that a later change can be checked with `change`.
pub fn index(
  entry: mfs.Entry,
  cache: cache.Cache(meta),
) -> mfs.Effect(#(Dict(Path, Result(binding.Poly, Problem)), Index)) {
  change(empty(), entry, cache)
}

/// Check a later version of the files the index was made from.
/// The outcome of every module is the same as `entry` gives,
/// only the modules that changed or failed to type check, and the modules that import them, directly or not, are checked again.
/// Modules that failed to type check are checked again because the cache may now have the references they were missing.
/// A file that is checked again is read again, other files are not read.
pub fn change(
  index: Index,
  entry: mfs.Entry,
  cache: cache.Cache(meta),
) -> mfs.Effect(#(Dict(Path, Result(binding.Poly, Problem)), Index)) {
  let root = mfs.identify(entry).cid
  use changed <- mfs.then(case index.root {
    None -> mfs.files(root)
    Some(previous) -> mfs.diff(previous, root)
  })
  // A module that failed to type check may have been missing references that are now in the cache.
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
  let modules =
    set.to_list(affected)
    |> list.filter(fn(path) {
      is_module(path) || dict.has_key(index.modules, path)
    })
  use #(files, imports) <- mfs.then(load(
    entry,
    modules,
    affected,
    index.modules,
    dict.new(),
    dict.new(),
  ))
  // Modules that are not affected keep their outcome, the checker uses it for modules that import them.
  let kept =
    dict.filter(index.modules, fn(path, _) { !set.contains(affected, path) })
  let checker =
    Checker(files, dict.map_values(kept, fn(_, indexed) { indexed.outcome }))
  let checker =
    dict.keys(files)
    |> list.sort(compare_paths)
    |> list.fold(checker, fn(checker, path) {
      case is_module(path) {
        True -> check_module(checker, path, [], cache).1
        False -> checker
      }
    })
  // Only the modules reached from a .eyg file are kept, as `entry` only checks those.
  let imports =
    dict.merge(
      dict.map_values(kept, fn(_, indexed) { indexed.imports }),
      imports,
    )
  let roots =
    dict.keys(checker.checked) |> list.filter(is_module) |> set.from_list
  let reached = reach(imports, roots)
  let checked =
    dict.filter(checker.checked, fn(path, _) { set.contains(reached, path) })
  let modules =
    dict.map_values(checked, fn(path, outcome) {
      Indexed(outcome, dict.get(imports, path) |> result.unwrap([]))
    })
  mfs.Done(#(checked, Index(Some(root), modules)))
}

// A .eyg file, or the entry when it is a single file.
fn is_module(path: Path) -> Bool {
  case list.last(path) {
    Ok(name) -> string.ends_with(name, ".eyg")
    Error(Nil) -> True
  }
}

fn compare_paths(a: Path, b: Path) {
  string.compare(string.join(a, "/"), string.join(b, "/"))
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

// Read each module to check and the modules it imports that are not kept from the index, with the imports of each.
// A module that cannot be read is left out, checking a module that imports it finds it missing.
fn load(entry, queue, affected, indexed, files, imports) {
  case queue {
    [] -> mfs.Done(#(files, imports))
    [path, ..queue] -> {
      let kept = dict.has_key(indexed, path) && !set.contains(affected, path)
      case kept || dict.has_key(files, path) {
        True -> load(entry, queue, affected, indexed, files, imports)
        False -> {
          use read <- mfs.then(read_file(entry, path))
          case read {
            Error(Nil) -> load(entry, queue, affected, indexed, files, imports)
            Ok(bytes) -> {
              let found = imported(path, bytes)
              load(
                entry,
                list.append(queue, found),
                affected,
                indexed,
                dict.insert(files, path, bytes),
                dict.insert(imports, path, found),
              )
            }
          }
        }
      }
    }
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

// The contents of the file at the path in the entry.
fn read_file(
  entry: mfs.Entry,
  path: Path,
) -> mfs.Effect(Result(BitArray, Nil)) {
  case entry, path {
    mfs.File(contents:), [] -> mfs.Done(Ok(contents))
    mfs.Directory(links:), [name, ..rest] ->
      case list.find(links, fn(link) { link.name == name }) {
        Ok(link) -> {
          use entry <- mfs.Get(link.cid)
          read_file(entry, rest)
        }
        Error(Nil) -> mfs.Done(Error(Nil))
      }
    _, _ -> mfs.Done(Error(Nil))
  }
}
