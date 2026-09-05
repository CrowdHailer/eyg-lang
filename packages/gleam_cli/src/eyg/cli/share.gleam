import eyg/cli/check
import eyg/cli/internal/client
import eyg/cli/internal/config
import eyg/cli/internal/execute
import eyg/cli/internal/source
import eyg/cli/system
import eyg/hub/cache
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import filepath
import gleam/crypto
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import midas/continuation.{type Continuation as K, return, then}
import multiformats/cid/v1

pub fn execute(
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  use code <- system.then(source.read_input(input))
  use code <- system.try(code)
  use source <- system.try(source.parse_input(code, input))
  let path = case source.1.origin {
    source.Disk(path:) -> path
    // empty path results in resolution against current working directory.
    source.Pipe -> ""
    source.Inline -> ""
    source.Repl -> ""
    source.Content(..) -> ""
    source.Release(..) -> ""
  }
  let dir = filepath.directory_name(path)
  use bundle <- system.then(load(dir, path, source, cache.empty()))
  let bundle =
    result.map_error(bundle, fn(reference) {
      "unknown reference: " <> ir.reference_to_string(reference)
    })
  use bundle <- system.try(bundle)
  let #(#(root, _), _) = bundle
  use shared <- system.then(client.share_bundle(bundle, config.client))
  use shared <- system.try(shared)
  case shared == root {
    True -> {
      use Nil <- system.then(system.stdout(v1.to_string(shared)))
      system.Done(Ok(0))
    }
    False -> system.Done(Error("hub returned the wrong shared module ID"))
  }
}

fn halt(reason) {
  fn(_) { system.Done(Error(reason)) }
}

fn read_file(path) {
  system.ReadFile(path, _)
}

fn hash_sha256(bytes) {
  return(crypto.hash(crypto.Sha256, bytes))
}

// continuation based below

pub fn load(directory, path, source, cache) {
  do_load(directory, source, cache, [path], dict.new(), [])(fn(out) {
    let #(module, _loaded, dependencies) = out
    system.Done(Ok(#(module, dependencies)))
  })
}

/// Can't pass in halt as a parameter and have it's return type generic
/// Instead halt needs to return Never and use the polymorphic never.
pub type Never {
  Never(Never)
}

pub fn never(_: Never) -> a {
  panic as "will never be called."
}

fn do_load(
  directory: String,
  source: ir.Node(source.Location),
  cache: cache.Cache(c),
  visited: List(String),
  loaded: dict.Dict(String, v1.Cid),
  acc: List(#(v1.Cid, BitArray)),
) -> K(system.Effect(_), _) {
  use #(_replaced, source) <- then(pin_k(source, cache, halt))
  use #(#(loaded, acc), source) <- then(
    ir.rewrite_with(source, #(loaded, acc), fn(state, node) {
      let #(loaded, acc) = state
      let #(exp, meta) = node
      case exp {
        ir.Reference(ir.Relative(location:)) -> {
          case execute.resolve_relative(directory, location) {
            Ok(path) ->
              case dict.get(loaded, path) {
                Ok(cid) ->
                  return(#(
                    #(loaded, acc),
                    #(ir.Reference(ir.Content(cid)), meta),
                  ))
                Error(Nil) ->
                  case check.cycle_check(visited, path) {
                    Ok(Nil) -> {
                      use code <- then(read_file(path))
                      case code {
                        Ok(code) ->
                          case source.parse_input(code, source.File(location)) {
                            Ok(dependency) -> {
                              use #(#(cid, block), loaded, acc) <- then(do_load(
                                filepath.directory_name(path),
                                dependency,
                                cache,
                                [path, ..visited],
                                loaded,
                                acc,
                              ))
                              let loaded = dict.insert(loaded, path, cid)
                              let acc = case list.key_find(acc, cid) {
                                Ok(_) -> acc
                                Error(_) -> [#(cid, block), ..acc]
                              }
                              return(#(
                                #(loaded, acc),
                                #(ir.Reference(ir.Content(cid)), meta),
                              ))
                            }
                            Error(_) -> halt(ir.Relative(path))
                          }
                        Error(_) -> halt(ir.Relative(path))
                      }
                    }
                    Error(_) -> halt(ir.Relative(path))
                  }
              }
            Error(_) -> halt(ir.Relative(location:))
          }
        }
        _ -> return(#(#(loaded, acc), #(exp, meta)))
      }
    }),
  )
  let block = dag_json.to_block(source)
  use cid <- then(cid.from_block(block, hash_sha256))
  return(#(#(cid, block), loaded, acc))
}

// fn pin(source, cache) -> system.Effect(Result(_, _)) {
//   pin_k(source, cache, fn(reason) { fn(_) { system.Done(Error(reason)) } })(
//     fn(value) { system.Done(Ok(value)) },
//   )
// }

// try pin could return list of meta, result(new, failure)
fn pin_k(
  source: ir.Node(a),
  cache: cache.Cache(_),
  halt: fn(ir.Reference) -> K(t, _),
) -> K(t, #(List(#(a, ir.Release)), #(ir.Expression(a), a))) {
  ir.pin(source, fn(package, version) {
    case version {
      Some(version) ->
        case cache.unbound_release(cache, package, version) {
          Ok(module) ->
            ir.Release(package:, version:, module:)
            |> continuation.return()
          Error(Nil) -> halt(ir.Version(package:, version:))
        }
      None -> {
        case cache.package(cache, package) {
          Ok(cache.Entry(version:, module:, ..)) ->
            ir.Release(package:, version:, module:)
            |> continuation.return()
          Error(Nil) -> halt(ir.Package(package))
        }
      }
    }
  })
}
