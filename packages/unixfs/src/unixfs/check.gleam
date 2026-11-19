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
