//// Pin a program before it runs.
////
//// Every relative import is read once and every package reference is resolved to a release.
//// The content addressed program, its imports and the hub modules it uses are added to the store.
//// Imports named `.env.eyg` hold secrets, only their CID is kept.

import eyg/hub/client
import eyg/ir/tree as ir
import filepath
import glasshouse/lock.{type Lock}
import glasshouse/recorder.{type Recorder}
import glasshouse/store
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/set
import gleam/string
import loam/execute
import loam/source
import loam/system
import multiformats/cid/v1

pub type Pinned {
  Pinned(
    /// CID of the program with every reference content addressed.
    program: String,
    lock: Lock,
    /// Parsed imports, with source locations, by the absolute path they were imported from.
    imports: Dict(String, ir.Node(source.Location)),
  )
}

/// Decide whether an import may be read, returning the path to read.
pub type Gate =
  fn(String, execute.State) ->
    system.Effect(#(Result(String, Nil), execute.State))

/// Read any import.
pub fn allow(path: String, state: execute.State) {
  system.Done(#(Ok(path), state))
}

type Pinning {
  Pinning(
    lock: Lock,
    imports: Dict(String, ir.Node(source.Location)),
    recorder: Recorder,
    fetched: set.Set(String),
    state: execute.State,
  )
}

/// Pin a program, relative imports in code without a file resolve from `cwd`.
pub fn pin(
  source: ir.Node(source.Location),
  cwd: String,
  state: execute.State,
  recorder: Recorder,
  gate: Gate,
) -> system.Effect(#(Result(Pinned, String), execute.State, Recorder)) {
  let directory = case { source.1 }.origin {
    source.Disk(path:) -> filepath.directory_name(path)
    _ -> cwd
  }
  let pinning =
    Pinning(
      lock: lock.empty(),
      imports: dict.new(),
      recorder:,
      state:,
      fetched: set.new(),
    )
  use result <- system.map(do_pin(
    source,
    directory,
    visited(source),
    gate,
    pinning,
  ))
  case result {
    Ok(#(program, pinning)) -> {
      let #(recorder, program) = recorder.store_node(pinning.recorder, program)
      let pinned =
        Pinned(program:, lock: pinning.lock, imports: pinning.imports)
      #(Ok(pinned), pinning.state, recorder)
    }
    Error(#(reason, pinning)) -> #(
      Error(reason),
      pinning.state,
      pinning.recorder,
    )
  }
}

fn visited(source: ir.Node(source.Location)) {
  case { source.1 }.origin {
    source.Disk(path:) -> [path]
    _ -> []
  }
}

/// Files that hold secrets by convention, they are never stored.
pub fn is_secret(path: String) -> Bool {
  string.ends_with(path, ".env.eyg")
}

type PinResult =
  Result(#(ir.Node(Nil), Pinning), #(String, Pinning))

fn do_pin(
  node: ir.Node(source.Location),
  directory: String,
  visited: List(String),
  gate: Gate,
  pinning: Pinning,
) -> system.Effect(PinResult) {
  let references = ir.list_references(node)
  use result <- system.map(
    system.fold(references, Ok(#(dict.new(), pinning)), fn(acc, reference) {
      case acc {
        Error(_) -> system.Done(acc)
        Ok(#(resolved, pinning)) -> {
          use result <- system.map(pin_reference(
            reference,
            directory,
            visited,
            gate,
            pinning,
          ))
          case result {
            Ok(#(cid, pinning)) ->
              Ok(#(
                dict.insert(resolved, key(reference, directory), cid),
                pinning,
              ))
            Error(failure) -> Error(failure)
          }
        }
      }
    }),
  )
  case result {
    Ok(#(resolved, pinning)) ->
      Ok(#(rewrite(node, directory, resolved), pinning))
    Error(failure) -> Error(failure)
  }
}

// References are keyed by what they resolve, relative paths by their absolute path.
fn key(reference: ir.Reference, directory: String) -> String {
  case reference {
    ir.Relative(location:) ->
      case system.resolve_relative(directory, location) {
        Ok(path) -> "file:" <> path
        Error(_) -> "invalid:" <> location
      }
    _ -> ir.reference_to_string(reference)
  }
}

// What a reference resolved to, a content reference or a pinned release.
type Resolved {
  Module(cid: v1.Cid)
  Release(release: ir.Release)
}

fn pin_reference(reference, directory, visited, gate, pinning) {
  case reference {
    ir.Relative(location:) ->
      case system.resolve_relative(directory, location) {
        Ok(path) -> pin_file(path, location, visited, gate, pinning)
        Error(_) ->
          system.Done(Error(#("invalid import path: " <> location, pinning)))
      }
    ir.Content(cid:) -> {
      use result <- system.map(fetch(cid, pinning))
      result.map(result, fn(pinning) { #(Module(cid), pinning) })
    }
    ir.Pinned(release:) -> {
      let ir.Release(package:, version:, module:) = release
      use #(found, state) <- system.then(execute.version_module(
        package,
        version,
        pinning.state,
      ))
      let pinning = Pinning(..pinning, state:)
      case found {
        Ok(cid) if cid == module -> {
          use result <- system.map(fetch(module, pinning))
          result.map(result, fn(pinning) { #(Release(release), pinning) })
        }
        Ok(_) ->
          system.Done(
            Error(#(
              "the hub has a different module for @"
                <> ir.release_to_string(release),
              pinning,
            )),
          )
        Error(Nil) ->
          system.Done(Error(#("unknown release @" <> package, pinning)))
      }
    }
    ir.Package(package:) -> {
      use #(found, state) <- system.then(execute.latest_release(
        package,
        pinning.state,
      ))
      let pinning = Pinning(..pinning, state:)
      case found {
        Ok(release) -> {
          use result <- system.map(fetch(release.module, pinning))
          use pinning <- result.map(result)
          let lock =
            lock.add_package(
              pinning.lock,
              package,
              lock.Release(
                version: release.version,
                module: v1.to_string(release.module),
              ),
            )
          #(Release(release), Pinning(..pinning, lock:))
        }
        Error(Nil) ->
          system.Done(Error(#("unknown package @" <> package, pinning)))
      }
    }
    ir.Version(package:, version:) -> {
      use #(found, state) <- system.then(execute.version_module(
        package,
        version,
        pinning.state,
      ))
      let pinning = Pinning(..pinning, state:)
      case found {
        Ok(module) -> {
          use result <- system.map(fetch(module, pinning))
          use pinning <- result.map(result)
          let lock =
            lock.add_version(
              pinning.lock,
              package,
              version,
              v1.to_string(module),
            )
          #(
            Release(ir.Release(package:, version:, module:)),
            Pinning(..pinning, lock:),
          )
        }
        Error(Nil) ->
          system.Done(
            Error(#(
              "unknown version @" <> package <> ":" <> int.to_string(version),
              pinning,
            )),
          )
      }
    }
  }
}

fn pin_file(path, location, visited, gate, pinning: Pinning) {
  case dict.get(pinning.lock.files, path) {
    Ok(lock.File(module:, ..)) -> {
      let assert Ok(#(cid, _)) = v1.from_string(module)
      system.Done(Ok(#(Module(cid), pinning)))
    }
    Error(Nil) ->
      case list.contains(visited, path) {
        True ->
          system.Done(
            Error(#(
              "import cycle: "
                <> string.join(list.reverse([path, ..visited]), " -> "),
              pinning,
            )),
          )
        False -> {
          use #(gated, state) <- system.then(gate(path, pinning.state))
          let pinning = Pinning(..pinning, state:)
          case gated {
            Error(Nil) ->
              system.Done(
                Error(#("import of " <> path <> " was denied", pinning)),
              )
            Ok(actual) -> {
              use code <- system.then(system.read_file(actual))
              case code {
                Error(_) ->
                  system.Done(
                    Error(#(
                      "failed to read module from location: " <> location,
                      pinning,
                    )),
                  )
                Ok(code) ->
                  case source.parse(code, source.Disk(actual)) {
                    Error(reason) ->
                      system.Done(
                        Error(#(
                          "failed to parse source from location: "
                            <> location
                            <> " "
                            <> string.replace(reason, "\n", " "),
                          pinning,
                        )),
                      )
                    Ok(parsed) -> {
                      use result <- system.map(do_pin(
                        parsed,
                        filepath.directory_name(actual),
                        [actual, ..visited],
                        gate,
                        pinning,
                      ))
                      use #(pinned, pinning) <- result.map(result)
                      let secret = is_secret(path) || is_secret(actual)
                      let #(recorder, module) = case secret {
                        True -> #(
                          pinning.recorder,
                          recorder.module_cid(pinning.recorder, pinned),
                        )
                        False -> recorder.store_node(pinning.recorder, pinned)
                      }
                      let #(recorder, source_cid) = case secret {
                        True -> #(recorder, "")
                        False -> recorder.store_binary(recorder, <<code:utf8>>)
                      }
                      let lock =
                        lock.add_file(
                          pinning.lock,
                          path,
                          lock.File(source: source_cid, module:),
                        )
                      let imports = dict.insert(pinning.imports, path, parsed)
                      let assert Ok(#(cid, _)) = v1.from_string(module)
                      #(
                        Module(cid),
                        Pinning(..pinning, lock:, imports:, recorder:),
                      )
                    }
                  }
              }
            }
          }
        }
      }
  }
}

/// Fetch a hub module and retain the immutable release metadata in its graph.
fn fetch(cid: v1.Cid, pinning: Pinning) {
  let id = v1.to_string(cid)
  case set.contains(pinning.fetched, id) {
    True -> system.Done(Ok(pinning))
    False -> {
      let pinning = Pinning(..pinning, fetched: set.insert(pinning.fetched, id))
      let loaded = case store.get_node(recorder.store(pinning.recorder), id) {
        Ok(module) -> system.Done(Ok(module))
        Error(_) ->
          client.fetch_module(
            cid,
            pinning.state.origin,
            fn(request) { system.Fetch(request, _) },
            fn(algorithm, bytes) { system.Hash(algorithm, bytes, _) },
          )(system.Done)
      }
      use loaded <- system.then(loaded)
      case loaded {
        Error(reason) ->
          system.Done(
            Error(#("failed to fetch module #" <> id <> ": " <> reason, pinning)),
          )
        Ok(module) -> {
          let #(recorder, _) = recorder.store_node(pinning.recorder, module)
          let references = ir.list_references(module)
          let releases =
            list.filter_map(references, fn(reference) {
              case reference {
                ir.Pinned(release) -> Ok(release)
                _ -> Error(Nil)
              }
            })
          let locked =
            list.try_fold(releases, pinning.lock, fn(locked, release) {
              let module = v1.to_string(release.module)
              case
                dict.get(locked.versions, #(release.package, release.version))
              {
                Ok(known) if known != module ->
                  Error("conflicting immutable package release in module graph")
                _ ->
                  Ok(lock.add_version(
                    locked,
                    release.package,
                    release.version,
                    module,
                  ))
              }
            })
          case locked {
            Error(reason) -> system.Done(Error(#(reason, pinning)))
            Ok(locked) -> {
              let pinning = Pinning(..pinning, recorder:, lock: locked)
              let dependencies =
                list.filter_map(references, fn(reference) {
                  case reference {
                    ir.Content(cid) -> Ok(cid)
                    ir.Pinned(release) -> Ok(release.module)
                    _ -> Error(Nil)
                  }
                })
              system.fold(dependencies, Ok(pinning), fn(acc, dependency) {
                case acc {
                  Ok(pinning) -> fetch(dependency, pinning)
                  Error(_) -> system.Done(acc)
                }
              })
            }
          }
        }
      }
    }
  }
}

/// Replace every reference with what it was pinned to.
fn rewrite(
  node: ir.Node(source.Location),
  directory: String,
  resolved: Dict(String, Resolved),
) -> ir.Node(Nil) {
  let #(exp, _) = node
  let exp = case exp {
    ir.Reference(reference) ->
      case dict.get(resolved, key(reference, directory)) {
        Ok(Module(cid)) -> ir.Reference(ir.Content(cid))
        Ok(Release(release)) -> ir.Reference(ir.Pinned(release))
        Error(Nil) -> ir.Reference(reference)
      }
    ir.Lambda(label, body) ->
      ir.Lambda(label, rewrite(body, directory, resolved))
    ir.Apply(function, argument) ->
      ir.Apply(
        rewrite(function, directory, resolved),
        rewrite(argument, directory, resolved),
      )
    ir.Let(label, definition, then) ->
      ir.Let(
        label,
        rewrite(definition, directory, resolved),
        rewrite(then, directory, resolved),
      )
    ir.Variable(label) -> ir.Variable(label)
    ir.Binary(value) -> ir.Binary(value)
    ir.Integer(value) -> ir.Integer(value)
    ir.String(value) -> ir.String(value)
    ir.Tail -> ir.Tail
    ir.Cons -> ir.Cons
    ir.Vacant -> ir.Vacant
    ir.Empty -> ir.Empty
    ir.Extend(label) -> ir.Extend(label)
    ir.Select(label) -> ir.Select(label)
    ir.Overwrite(label) -> ir.Overwrite(label)
    ir.Tag(label) -> ir.Tag(label)
    ir.Case(label) -> ir.Case(label)
    ir.NoCases -> ir.NoCases
    ir.Perform(label) -> ir.Perform(label)
    ir.Handle(label) -> ir.Handle(label)
    ir.Mask(label) -> ir.Mask(label)
    ir.Shallow(label) -> ir.Shallow(label)
    ir.Query(operation) -> ir.Query(operation)
    ir.Builtin(identifier) -> ir.Builtin(identifier)
  }
  #(exp, Nil)
}
