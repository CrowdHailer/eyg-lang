//// Local EYG modules as a hub stores them.
////
//// Relative imports are replaced by the content id of the module they import,
//// and package references can be pinned to releases, as `eyg share` does. A
//// module and everything it imports can then be served by a hub fixture and
//// loaded by content id.

import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import eyg/parser
import filepath
import gleam/bit_array
import gleam/crypto
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import midas/continuation
import multiformats/cid/v1
import simplifile

/// A module and every module it imports, stored as dag-json blocks by content id.
pub type Loaded {
  Loaded(cid: v1.Cid, blocks: Dict(String, BitArray))
}

/// The release a package reference is pinned to, by package name and an
/// optional version, `Error` leaves the reference unpinned.
pub type Resolve =
  fn(String, Option(Int)) -> Result(ir.Release, Nil)

type Loader {
  Loader(read: fn(String) -> Result(String, String), resolve: Resolve)
}

/// Load the module at a path on disk, package references are not pinned.
pub fn load(path: String) -> Result(Loaded, String) {
  load_pinned(path, unpinned)
}

/// Load the module at a path on disk, pinning package references.
pub fn load_pinned(path: String, resolve: Resolve) -> Result(Loaded, String) {
  load_with(expand(path), Loader(disk, resolve))
}

/// Load a module from files held in memory, such as a workspace. Paths are
/// relative to the root of the files.
pub fn load_from(
  files: List(#(String, BitArray)),
  path: String,
) -> Result(Loaded, String) {
  let read = fn(path) {
    let path = case path {
      "/" <> path -> path
      path -> path
    }
    case list.key_find(files, path) {
      Ok(contents) ->
        bit_array.to_string(contents)
        |> result.replace_error(path <> " is not text")
      Error(Nil) -> Error("there is no file at " <> path)
    }
  }
  load_with("/" <> expand(path), Loader(read, unpinned))
}

/// Load a module from source, relative imports resolve from `directory` on disk.
pub fn from_source(code: String, directory: String) -> Result(Loaded, String) {
  use source <- result.try(parse(code, "source"))
  use #(cid, blocks, _paths) <- result.map(store(
    source,
    expand(directory),
    [],
    dict.new(),
    dict.new(),
    Loader(disk, unpinned),
  ))
  Loaded(cid:, blocks:)
}

/// The content id of a module tree.
pub fn cid(source: ir.Node(a)) -> v1.Cid {
  cid.from_tree(source, sha256)(fn(cid) { cid })
}

/// The packages a loaded module and its imports reference by name or version.
pub fn packages(loaded: Loaded) -> List(String) {
  dict.values(loaded.blocks)
  |> list.flat_map(fn(block) {
    case json.parse_bits(block, dag_json.decoder(Nil)) {
      Ok(source) ->
        ir.list_references(source)
        |> list.filter_map(fn(reference) {
          case reference {
            ir.Package(package:) | ir.Version(package:, ..) -> Ok(package)
            _ -> Error(Nil)
          }
        })
      Error(_) -> []
    }
  })
  |> list.unique
}

fn unpinned(_package, _version) {
  Error(Nil)
}

fn load_with(path, loader) {
  use #(cid, blocks, _paths) <- result.map(do_load(
    path,
    [],
    dict.new(),
    dict.new(),
    loader,
  ))
  Loaded(cid:, blocks:)
}

fn disk(path) {
  simplifile.read(path)
  |> result.map_error(fn(reason) {
    "unable to read " <> path <> ": " <> simplifile.describe_error(reason)
  })
}

fn do_load(path, visited, blocks, paths, loader: Loader) {
  case list.contains(visited, path) {
    True -> Error("import cycle through " <> path)
    False -> {
      use code <- result.try(loader.read(path))
      use source <- result.try(parse(code, path))
      let directory = filepath.directory_name(path)
      store(source, directory, [path, ..visited], blocks, paths, loader)
    }
  }
}

fn store(source, directory, visited, blocks, paths, loader: Loader) {
  let locations =
    ir.list_references(source)
    |> list.filter_map(fn(reference) {
      case reference {
        ir.Relative(location:) -> Ok(location)
        _ -> Error(Nil)
      }
    })
    |> list.unique
  use #(mapping, blocks, paths) <- result.try(
    list.try_fold(locations, #(dict.new(), blocks, paths), fn(acc, location) {
      let #(mapping, blocks, paths) = acc
      let path = resolve(directory, location)
      case dict.get(paths, path) {
        Ok(cid) -> Ok(#(dict.insert(mapping, location, cid), blocks, paths))
        Error(Nil) -> {
          use #(cid, blocks, paths) <- result.map(do_load(
            path,
            visited,
            blocks,
            paths,
            loader,
          ))
          let paths = dict.insert(paths, path, cid)
          #(dict.insert(mapping, location, cid), blocks, paths)
        }
      }
    }),
  )
  let source = replace_relative(source, mapping) |> pin(loader.resolve)
  let block = dag_json.to_block(source)
  let cid = cid.from_block(block, sha256)(fn(cid) { cid })
  Ok(#(cid, dict.insert(blocks, v1.to_string(cid), block), paths))
}

fn replace_relative(source, mapping) {
  ir.rewrite_with(source, Nil, fn(acc, node) {
    let #(exp, meta) = node
    case exp {
      ir.Reference(ir.Relative(location:)) ->
        case dict.get(mapping, location) {
          Ok(cid) ->
            continuation.return(#(acc, #(ir.Reference(ir.Content(cid)), meta)))
          Error(Nil) -> continuation.return(#(acc, #(exp, meta)))
        }
      _ -> continuation.return(#(acc, #(exp, meta)))
    }
  })(fn(result) { result.1 })
}

/// Pin the package references a resolver knows, others are left as they are.
fn pin(source, resolve: Resolve) {
  ir.rewrite_with(source, Nil, fn(acc, node) {
    let #(exp, meta) = node
    let pinned = case exp {
      ir.Reference(ir.Package(package:)) -> resolve(package, option.None)
      ir.Reference(ir.Version(package:, version:)) ->
        resolve(package, option.Some(version))
      _ -> Error(Nil)
    }
    case pinned {
      Ok(release) ->
        continuation.return(#(acc, #(ir.Reference(ir.Pinned(release)), meta)))
      Error(Nil) -> continuation.return(#(acc, #(exp, meta)))
    }
  })(fn(result) { result.1 })
}

/// Modules are dag-json or EYG source, a shebang line is ignored.
fn parse(code, path) -> Result(ir.Node(Nil), String) {
  case json.parse(code, dag_json.decoder(Nil)) {
    Ok(source) -> Ok(source)
    Error(_) ->
      case parser.all_from_string(strip_shebang(code)) {
        Ok(source) -> Ok(ir.clear_annotation(source))
        Error(reason) ->
          Error("unable to parse " <> path <> ": " <> string.inspect(reason))
      }
  }
}

fn strip_shebang(code) {
  case string.starts_with(code, "#!") {
    True ->
      case string.split_once(code, "\n") {
        Ok(#(_, rest)) -> rest
        Error(Nil) -> ""
      }
    False -> code
  }
}

fn resolve(directory, location) {
  case filepath.is_absolute(location) {
    True -> expand(location)
    False -> expand(filepath.join(directory, location))
  }
}

fn expand(path) {
  filepath.expand(path) |> result.unwrap(path)
}

fn sha256(bytes) {
  continuation.return(crypto.hash(crypto.Sha256, bytes))
}
