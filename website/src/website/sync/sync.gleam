import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/interpreter/expression as runner
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/http.{type Scheme}
import gleam/http/request
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import midas/task as t
import plinth/javascript/console
import snag
import website/components/simple_debug
import website/sync/dump
import website/sync/fragment
import website/sync/supabase

// Enum type describing all possible remotes
pub type Origin {
  Origin(scheme: Scheme, host: String, port: Option(Int))
}

pub const test_origin = Origin(http.Https, "eyg.test", None)

pub type Computed {
  Computed(
    expression: ir.Node(Nil),
    type_: binding.Poly,
    value: Result(fragment.Value, String),
  )
}

pub type Pending(m) =
  List(#(String, #(List(String), ir.Node(m))))

pub type Run {
  Ongoing
  Failed(snag.Snag)
}

pub type Sync {
  Sync(
    origin: Origin,
    tasks: Dict(String, Run),
    pending: Pending(List(Int)),
    // loaded is blobs
    loaded: Dict(String, Computed),
    registry: Dict(String, String),
    packages: Dict(String, Dict(Int, supabase.Release)),
  )
}

pub type Message {
  HashSourceFetched(reference: String, value: Result(ir.Node(Nil), snag.Snag))
  DumpDownLoaded(Result(dump.Dump, snag.Snag))
}

// fromdump
// Could rename as set_remote
pub fn init(origin) {
  Sync(origin, dict.new(), [], dict.new(), dict.new(), dict.new())
}

pub fn missing(sync, refs) {
  let Sync(pending: pending, loaded: loaded, ..) = sync
  // walk_missing(store, refs, [])
  list.flat_map(refs, fn(r) {
    case dict.get(loaded, r) {
      Ok(_) -> []
      Error(Nil) ->
        case list.key_find(pending, r) {
          // Do need recursive lookup
          // TODO need to test this recursive lookup
          Ok(#(dep, _source)) -> missing(sync, dep)
          Error(Nil) -> [r]
        }
    }
  })
}

pub fn fetch_missing(sync, refs) {
  io.debug("this should be replaced with loading initial state")
  let Sync(origin: origin, tasks: running, ..) = sync
  let missing = missing(sync, refs)

  // these are midas tasks
  let #(tasks, running) = do_fetch_missing(missing, origin, running)
  let sync = Sync(..sync, origin: origin, tasks: running)
  #(sync, tasks)
}

pub fn fetch_all_missing(sync) {
  let Sync(origin: origin, tasks: running, pending: pending, ..) = sync
  let missing =
    list.flat_map(pending, fn(pending) {
      let #(_ref, #(deps, _source)) = pending
      deps
    })
  let #(tasks, running) = do_fetch_missing(missing, origin, running)
  let sync = Sync(..sync, origin: origin, tasks: running)
  #(sync, tasks)
}

fn do_fetch_missing(missing, origin, running) {
  list.fold(missing, #([], running), fn(acc, ref) {
    let #(tasks, running) = acc
    case dict.get(running, ref) {
      Error(Nil) | Ok(Failed(_)) -> {
        let task = fetch_via_http(origin, ref)
        let running = dict.insert(running, ref, Ongoing)
        #([#(ref, task), ..tasks], running)
      }
      Ok(Ongoing) -> #(tasks, running)
    }
  })
}

pub fn value(sync, ref) {
  let Sync(loaded: loaded, ..) = sync
  dict.get(loaded, ref)
}

pub fn values(sync) {
  let Sync(loaded: loaded, ..) = sync
  values_from_loaded(loaded)
}

pub fn named_values(sync) {
  let Sync(registry: registry, packages: packages, loaded: loaded, ..) = sync
  list.flat_map(dict.to_list(registry), fn(entry) {
    let #(name, package_id) = entry
    case dict.get(packages, package_id) {
      Error(Nil) -> []
      Ok(releases) -> {
        list.filter_map(dict.to_list(releases), fn(release) {
          let #(version, supabase.Release(hash: hash_ref, ..)) = release
          use Computed(value: value, ..) <- result.try(dict.get(
            loaded,
            hash_ref,
          ))
          use value <- result.try(
            value
            |> result.replace_error(Nil),
          )
          Ok(#(named_ref(name, version), value))
        })
      }
    }
  })
}

fn values_from_loaded(loaded) {
  dict.to_list(loaded)
  |> list.filter_map(fn(pair) {
    let #(ref, computed) = pair
    let Computed(value: value, ..) = computed
    case value {
      Ok(value) -> Ok(#(ref, value))
      Error(reason) -> Error(reason)
    }
  })
  |> dict.from_list
}

pub fn types(sync) {
  let Sync(loaded: loaded, ..) = sync
  dict.map_values(loaded, fn(_ref, computed) {
    let Computed(type_: type_, ..) = computed
    type_
  })
}

fn named_ref(name, version) {
  "@" <> name <> ":" <> int.to_string(version)
}

pub fn named_types(sync) {
  let Sync(registry: registry, packages: packages, loaded: loaded, ..) = sync
  list.flat_map(dict.to_list(registry), fn(entry) {
    let #(name, package_id) = entry
    case dict.get(packages, package_id) {
      Error(Nil) -> []
      Ok(releases) -> {
        list.filter_map(dict.to_list(releases), fn(release) {
          let #(version, supabase.Release(hash: hash_ref, ..)) = release
          use Computed(type_: type_, ..) <- result.try(dict.get(
            loaded,
            hash_ref,
          ))
          Ok(#(named_ref(name, version), type_))
        })
      }
    }
  })
}

pub fn do_resolve(pending, loaded) {
  let #(computed, pending) =
    result.partition(
      list.map(pending, fn(p) {
        let #(ref, #(_missing, source)) = p
        case compute(source, loaded) {
          Ok(status) -> Ok(#(ref, status))
          Error(reason) -> Error(#(ref, reason))
        }
      }),
    )
  case computed {
    // fixpoint
    [] -> #(pending, loaded)
    _ -> {
      let loaded =
        list.fold(computed, loaded, fn(acc, entry) {
          let #(ref, computed) = entry
          dict.insert(acc, ref, computed)
        })
      do_resolve(pending, loaded)
    }
  }
}

// fn foo() {
//   case todo {
//     Lookup(Release) -> {
//       // match release to index and find ref
//       todo
//     }
//     Lookup(Reference) -> {
//       // lookup reference
//       todo
//     }
//   }
//   todo
// }

fn compute(source, loaded) {
  let types =
    dict.map_values(loaded, fn(_ref, computed) {
      let Computed(type_: type_, ..) = computed
      type_
    })
  let values = values_from_loaded(loaded)
  // TODO with references
  let #(top_type, errors) = fragment.infer(source, types)
  case error.missing_references(errors) {
    [] -> {
      let executed = case runner.execute_next(source, []) {
        Ok(value) -> Ok(value)
        Error(#(reason, _, _, _)) -> {
          io.debug(reason)
          Error(simple_debug.reason_to_string(reason))
        }
      }
      case errors {
        [] -> []
        _ -> io.debug(errors)
      }
      Ok(Computed(ir.clear_annotation(source), top_type, executed))
    }
    missing -> Error(#(missing, source))
  }
}

pub fn task_finish(sync, message) {
  let Sync(tasks: tasks, ..) = sync
  case message {
    HashSourceFetched(ref, result) ->
      case result, dict.get(tasks, ref) {
        Ok(expression), _ -> {
          let tasks = dict.delete(tasks, ref)
          let sync = Sync(..sync, tasks: tasks)
          install(sync, ref, expression |> ir.map_annotation(fn(_) { [] }))
        }
        Error(reason), _ -> {
          let tasks = dict.insert(tasks, ref, Failed(reason))
          Sync(..sync, tasks: tasks)
        }
      }
    DumpDownLoaded(dump) -> {
      case dump {
        Ok(dump) -> load(sync, dump)
        Error(_reason) -> panic as "failed to load resources"
      }
    }
  }
}

pub fn install(sync, ref, source) {
  let Sync(loaded: loaded, pending: pending, ..) = sync

  case compute(source, loaded) {
    Ok(computed) -> {
      let loaded = dict.insert(loaded, ref, computed)
      let #(pending, loaded) = do_resolve(pending, loaded)
      Sync(..sync, pending: pending, loaded: loaded)
    }
    Error(return) -> {
      let pending = [#(ref, return), ..pending]
      Sync(..sync, pending: pending, loaded: loaded)
    }
  }
}

fn fetch_via_http(origin, ref) {
  let Origin(scheme, host, port) = origin
  let request =
    request.Request(
      http.Get,
      [],
      <<>>,
      scheme,
      host,
      port,
      "/references/" <> ref <> ".json",
      None,
    )
  send_fetch_request(request)
}

pub fn send_fetch_request(request) {
  use response <- t.do(t.fetch(request))

  use body <- t.try(case response.status {
    200 -> Ok(response.body)
    other -> Error(snag.new("Bad response status: " <> int.to_string(other)))
  })

  use source <- t.try(decode_bytes(body))
  // use _ <- t.do(t.log("fetched reference:" <> path))
  t.done(source)
}

// This probably belongs in remote or storage layer
// TODO make private when removed from intro/package
pub fn decode_bytes(bytes) {
  dag_json.from_block(bytes)
  |> result.replace_error(snag.new("Unable to decode source code."))
}

pub fn load(sync, dump: dump.Dump) {
  // let Dump(registry,packages, _raw) = dump
  let Sync(registry: registry, packages: packages, ..) = sync
  let registry = dict.merge(registry, dump.registry)
  let packages = dict.merge(packages, dump.packages)
  // Can work out value of blobs eagerly and stick them in the map.
  // use the checksum as lookup key
  let loaded =
    list.fold(
      dump.fragments,
      sync.loaded,
      fn(loaded, fragment: supabase.Fragment) {
        // List all references and then put them in the loaded map
        // This is bluring things a bit
        let expression = ir.map_annotation(fragment.code, fn(_) { [] })
        let named =
          ir.list_named_references(expression)
          |> list.map(fn(ref) {
            let #(name, release, _) = ref
            case dict.get(registry, name) {
              Ok(package_id) ->
                case dict.get(packages, package_id) {
                  Ok(releases) ->
                    case dict.get(releases, release) {
                      Ok(release) ->
                        case dict.get(loaded, release.hash) {
                          Ok(computed) -> #(
                            "@" <> name <> ":" <> int.to_string(release.version),
                            computed,
                          )
                          Error(Nil) -> panic as "computed should be done"
                        }
                      Error(Nil) -> panic as "release should be in history"
                    }
                  Error(Nil) ->
                    panic as { "package should be in history " <> name }
                }
              Error(Nil) -> panic as { "name should be in registry " <> name }
            }
          })
          |> dict.from_list
        case compute(expression, dict.merge(loaded, named)) {
          Ok(computed) -> dict.insert(loaded, fragment.hash, computed)
          Error(reason) -> {
            io.debug(reason)
            loaded
          }
        }
      },
    )

  Sync(..sync, registry: registry, packages: packages, loaded: loaded)
}

pub fn package_index(sync) {
  let Sync(registry: registry, packages: packages, loaded: loaded, ..) = sync
  dict.to_list(registry)
  |> list.filter_map(fn(entry) {
    let #(name, package_id) = entry
    use package <- result.try(dict.get(packages, package_id))

    case dict.size(package) {
      x if x > 0 -> {
        // We start on version 1
        let latest = x
        case dict.get(package, latest) {
          Ok(supabase.Release(hash: hash_ref, ..)) ->
            case dict.get(loaded, hash_ref) {
              Ok(Computed(type_: type_, ..)) ->
                Ok(#(name <> ":" <> int.to_string(latest), type_))
              Error(Nil) -> {
                console.warn(
                  "failed to load package ref "
                  <> name
                  <> ":"
                  <> int.to_string(latest),
                )
                Error(Nil)
              }
            }
          Error(Nil) -> {
            console.warn(
              "failed get latest for package ref "
              <> name
              <> ":"
              <> int.to_string(latest),
            )
            Error(Nil)
          }
        }
      }
      _ -> Error(Nil)
    }
  })
}
