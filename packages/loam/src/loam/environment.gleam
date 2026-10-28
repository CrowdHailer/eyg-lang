//// An immutable, portable execution environment. Forks share this persistent
//// filesystem and module store; changing a fork copies only its changed paths.

import eyg/hub/cache
import eyg/ir/tree as ir
import glasshouse/bundle
import glasshouse/data
import glasshouse/lock
import glasshouse/store
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import loam/execute
import loam/sandbox/fs
import loam/source
import multiformats/cid/v1
import ogre/origin

/// Bump when observable execution semantics change, not for archive/UI changes.
pub const runtime = "eyg-sandbox-3/shallow-answers/fuel-1000000"

pub type Environment {
  Environment(
    files: fs.Entry,
    cwd: String,
    clock: Int,
    seed: Int,
    variables: Dict(String, String),
    lock: lock.Lock,
    store: store.Store,
    hub: origin.Origin,
    programs: Dict(String, String),
    artifacts: List(String),
  )
}

pub fn new() -> Environment {
  Environment(
    fs.directory([]),
    "/workspace",
    0,
    1,
    dict.new(),
    lock.empty(),
    store.new(),
    origin.https("eyg.run"),
    dict.new(),
    [],
  )
}

pub fn seal(environment: Environment, sha256: store.Sha256) -> bundle.Bundle {
  let #(blocks, tree) = store_tree(environment.files, environment.store, sha256)
  seal_with_tree(environment, blocks, tree, sha256)
}

/// Reuse unchanged subtrees by CID; only changed files and their ancestors are
/// encoded again. Persistent filesystem equality short-circuits shared values.
pub fn seal_fork(
  environment: Environment,
  original: Environment,
  input: bundle.Bundle,
  sha256: store.Sha256,
) -> bundle.Bundle {
  let assert Ok(descriptor) = store.get_node(input.store, input.root)
  let assert Ok(tree) =
    data.field(descriptor, "tree") |> result.try(data.reference)
  let #(blocks, tree) =
    store_changed(
      environment.files,
      original.files,
      tree,
      store.merge(input.store, environment.store),
      sha256,
    )
  seal_with_tree(environment, blocks, tree, sha256)
}

fn store_changed(
  tree: fs.Entry,
  original: fs.Entry,
  root: String,
  blocks: store.Store,
  sha256: store.Sha256,
) -> #(store.Store, String) {
  case tree == original {
    True -> #(blocks, root)
    False ->
      case tree, original {
        fs.Directory(children:, ..), fs.Directory(children: old, ..) -> {
          let assert Ok(node) = store.get_node(blocks, root)
          let assert Ok(fields) = data.fields(node)
          let links = dict.from_list(fields)
          let #(blocks, fields) =
            dict.to_list(children)
            |> list.fold(#(blocks, []), fn(acc, child) {
              let #(blocks, fields) = acc
              let #(blocks, id) = case
                dict.get(old, child.0),
                dict.get(links, child.0)
              {
                Ok(previous), Ok(link) -> {
                  let assert Ok(id) = data.reference(link)
                  store_changed(child.1, previous, id, blocks, sha256)
                }
                _, _ -> store_tree(child.1, blocks, sha256)
              }
              #(blocks, [#(child.0, data.link(id)), ..fields])
            })
          store.put_node(blocks, data.record(fields), sha256)
        }
        _, _ -> store_tree(tree, blocks, sha256)
      }
  }
}

fn seal_with_tree(
  environment: Environment,
  blocks: store.Store,
  tree: String,
  sha256: store.Sha256,
) -> bundle.Bundle {
  let modules =
    lock.references(environment.lock)
    |> list.filter(store.has(blocks, _))
    |> list.map(fn(id) { #(id, data.link(id)) })
    |> data.record
  let artifact_fields = case environment.artifacts {
    [] -> []
    roots -> [
      #(
        "artifacts",
        roots
          |> list.unique
          |> list.map(fn(root) { #(root, data.link(root)) })
          |> data.record,
      ),
    ]
  }
  let descriptor =
    data.record(
      list.append(artifact_fields, [
        #("runtime", #(ir.String(runtime), Nil)),
        #("hub", #(ir.String(origin.to_string(environment.hub)), Nil)),
        #("cwd", #(ir.String(environment.cwd), Nil)),
        #("clock", #(ir.Integer(environment.clock), Nil)),
        #("seed", #(ir.Integer(environment.seed), Nil)),
        #(
          "variables",
          dict.to_list(environment.variables)
            |> list.map(fn(pair) { #(pair.0, #(ir.String(pair.1), Nil)) })
            |> data.record,
        ),
        #("tree", data.link(tree)),
        #(
          "lock",
          #(ir.String(json.to_string(lock.encode(environment.lock))), Nil),
        ),
        #("modules", modules),
        #(
          "programs",
          dict.to_list(environment.programs)
            |> list.map(fn(pair) { #(pair.0, data.link(pair.1)) })
            |> data.record,
        ),
      ]),
    )
  let #(blocks, root) = store.put_node(blocks, descriptor, sha256)
  bundle.new(root, blocks)
}

/// Load only literal data; an environment descriptor is never evaluated as EYG.
pub fn open(bundle: bundle.Bundle) -> Result(Environment, String) {
  use node <- result.try(store.get_node(bundle.store, bundle.root))
  use version <- result.try(
    data.field(node, "runtime") |> result.try(data.text),
  )
  use Nil <- result.try(case version == runtime {
    True -> Ok(Nil)
    False -> Error("unsupported sandbox runtime: " <> version)
  })
  use cwd <- result.try(data.field(node, "cwd") |> result.try(data.text))
  use hub <- result.try(data.field(node, "hub") |> result.try(data.text))
  use hub <- result.try(
    origin.from_string(hub) |> result.replace_error("invalid hub origin"),
  )
  use clock <- result.try(data.field(node, "clock") |> result.try(data.integer))
  use seed <- result.try(data.field(node, "seed") |> result.try(data.integer))
  use tree <- result.try(data.field(node, "tree") |> result.try(data.reference))
  use files <- result.try(load_tree(tree, bundle.store, 0))
  use variables <- result.try(
    data.field(node, "variables") |> result.try(data.fields),
  )
  use variables <- result.try(
    list.try_map(variables, fn(pair) {
      result.map(data.text(pair.1), fn(text) { #(pair.0, text) })
    }),
  )
  use locked <- result.try(data.field(node, "lock") |> result.try(data.text))
  use locked <- result.try(
    json.parse(locked, lock.decoder())
    |> result.replace_error("invalid environment lock"),
  )
  use programs <- result.try(
    data.field(node, "programs") |> result.try(data.fields),
  )
  use programs <- result.try(
    list.try_map(programs, fn(pair) {
      use id <- result.map(data.reference(pair.1))
      #(pair.0, id)
    }),
  )
  use _ <- result.try(
    fs.read_directory(files, cwd)
    |> result.replace_error("environment working directory is missing"),
  )
  use artifacts <- result.try(case data.field(node, "artifacts") {
    Error(_) -> Ok([])
    Ok(artifacts) -> {
      use fields <- result.try(data.fields(artifacts))
      list.try_map(fields, fn(pair) { data.reference(pair.1) })
    }
  })
  Ok(Environment(
    files,
    cwd,
    clock,
    seed,
    dict.from_list(variables),
    locked,
    bundle.store,
    hub,
    dict.from_list(programs),
    artifacts,
  ))
}

pub fn store_tree(
  tree: fs.Entry,
  blocks: store.Store,
  sha256: store.Sha256,
) -> #(store.Store, String) {
  case tree {
    fs.File(contents:, ..) -> store.put_binary(blocks, contents, sha256)
    fs.Directory(children:, ..) -> {
      let #(blocks, fields) =
        dict.to_list(children)
        |> list.fold(#(blocks, []), fn(acc, child) {
          let #(blocks, fields) = acc
          let #(blocks, id) = store_tree(child.1, blocks, sha256)
          #(blocks, [#(child.0, data.link(id)), ..fields])
        })
      store.put_node(blocks, data.record(fields), sha256)
    }
  }
}

fn load_tree(id, blocks, depth) {
  use Nil <- result.try(case depth > 128 {
    True -> Error("filesystem nesting limit exceeded")
    False -> Ok(Nil)
  })
  use node <- result.try(store.get_node(blocks, id))
  case node {
    #(ir.Binary(bytes), _) -> {
      let assert fs.File(permissions:, ..) = fs.file("")
      Ok(fs.File(bytes, permissions))
    }
    _ -> {
      use fields <- result.try(data.fields(node))
      use children <- result.try(
        list.try_map(fields, fn(field) {
          let #(name, reference) = field
          use Nil <- result.try(
            case
              name == ""
              || name == "."
              || name == ".."
              || string.contains(name, "/")
              || string.contains(name, "\u{0}")
            {
              True -> Error("invalid tree entry: " <> name)
              False -> Ok(Nil)
            },
          )
          use id <- result.try(data.reference(reference))
          use child <- result.map(load_tree(id, blocks, depth + 1))
          #(name, child)
        }),
      )
      Ok(fs.directory(children))
    }
  }
}

pub fn tree(bundle: bundle.Bundle) -> Result(fs.Entry, String) {
  load_tree(bundle.root, bundle.store, 0)
}

pub fn contents(tree: fs.Entry) -> Dict(String, BitArray) {
  dict.from_list(list_contents(tree, ""))
}

fn list_contents(tree: fs.Entry, path: String) -> List(#(String, BitArray)) {
  case tree {
    fs.File(contents:, ..) -> [#(path, contents)]
    fs.Directory(children:, ..) ->
      dict.to_list(children)
      |> list.flat_map(fn(child) {
        list_contents(child.1, path <> "/" <> child.0)
      })
  }
}

/// Preload the pinned module closure once, before forking agents. The state and
/// its cache are persistent values shared by forks, not fetched per agent.
pub fn execution_state(environment: Environment, origin) -> execute.State {
  let packages =
    dict.to_list(environment.lock.packages)
    |> list.filter_map(fn(entry) {
      let #(name, lock.Release(version:, module:)) = entry
      use #(cid, _) <- result.map(
        v1.from_string(module) |> result.replace_error(Nil),
      )
      #(
        name,
        cache.Entry(version:, module: cid, cursor: 0, sequence: version, cid:),
      )
    })
  let releases =
    list.append(
      list.map(packages, fn(pair) {
        #(#(pair.0, pair.1.version), pair.1.module)
      }),
      dict.to_list(environment.lock.versions)
        |> list.filter_map(fn(pair) {
          use #(cid, _) <- result.map(
            v1.from_string(pair.1) |> result.replace_error(Nil),
          )
          #(pair.0, cid)
        }),
    )
  let cache =
    cache.Cache(
      ..cache.empty(),
      packages: dict.from_list(packages),
      releases: dict.from_list(releases),
    )
  let programs = dict.values(environment.programs)
  let modules =
    store.reachable(
      environment.store,
      list.append(programs, lock.references(environment.lock)),
    )
    |> list.filter(fn(id) { !list.contains(programs, id) })
  let cache =
    list.fold(modules, cache, fn(cache, id) {
      case store.get_node(environment.store, id), v1.from_string(id) {
        Ok(node), Ok(#(cid, _)) -> {
          let #(cache, _) =
            cache.update(
              cache,
              cache.FetchModuleCompleted(cid, Ok(node)),
              fn(_) { source.Location(source.Content(cid), source.Json) },
            )
          cache
        }
        _, _ -> cache
      }
    })
  execute.State(origin, cache, option.None)
}
