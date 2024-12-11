import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/runtime/break
import eyg/sync/dump
import eyg/sync/fragment
import eygir/annotated
import eygir/decode
import eygir/expression
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/http.{type Scheme}
import gleam/http/request
import gleam/int
import gleam/io
import gleam/list
import gleam/option.{type Option, None}
import gleam/result
import midas/task as t
import snag

// Enum type describing all possible remotes
pub type Origin {
  Origin(scheme: Scheme, host: String, port: Option(Int))
}

pub const test_origin = Origin(http.Https, "eyg.test", None)

pub type Source =
  annotated.Node(List(Int))

pub type Computed {
  Computed(
    expression: expression.Expression,
    type_: binding.Poly,
    value: Result(fragment.Value, String),
  )
}

pub type Pending =
  List(#(String, #(List(String), Source)))

pub type Run {
  Ongoing
  Failed(snag.Snag)
}

pub type Sync {
  Sync(
    origin: Origin,
    tasks: Dict(String, Run),
    pending: Pending,
    // loaded is blobs
    loaded: Dict(String, Computed),
    registry: Dict(String, String),
    packages: Dict(String, Dict(Int, String)),
  )
}

pub type Message {
  HashSourceFetched(
    reference: String,
    value: Result(expression.Expression, snag.Snag),
  )
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
          let #(version, hash_ref) = release
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
          let #(version, hash_ref) = release
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

pub fn do_resolve(pending: Pending, loaded) -> #(Pending, _) {
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

fn compute(source, loaded) {
  let types =
    dict.map_values(loaded, fn(_ref, computed) {
      let Computed(type_: type_, ..) = computed
      type_
    })
  let values = values_from_loaded(loaded)
  let #(top_type, errors) = fragment.infer(source, types)
  case error.missing_references(errors) {
    [] -> {
      let executed = case fragment.eval(source, values) {
        Ok(value) -> Ok(value)
        Error(#(reason, _, _, _)) -> {
          io.debug(reason)
          Error(break.reason_to_string(reason))
        }
      }
      case errors {
        [] -> []
        _ -> io.debug(errors)
      }
      Ok(Computed(annotated.drop_annotation(source), top_type, executed))
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
          install(sync, ref, expression)
        }
        Error(reason), _ -> {
          let tasks = dict.insert(tasks, ref, Failed(reason))
          Sync(..sync, tasks: tasks)
        }
      }
    DumpDownLoaded(dump) -> {
      case dump {
        Ok(dump) -> load(sync, dump)
        Error(reason) -> panic as "failed to load resources"
      }
    }
  }
}

pub fn install(sync, ref, expression) {
  let Sync(loaded: loaded, pending: pending, ..) = sync
  let source = annotated.add_annotation(expression, [])

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

pub fn fetch_via_http(origin, ref) {
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
  use body <- result.try(
    bit_array.to_string(bytes)
    |> result.replace_error(snag.new("Not utf8 formatted.")),
  )

  use source <- result.try(
    decode.from_json(body)
    |> result.replace_error(snag.new("Unable to decode source code.")),
  )
  Ok(source)
}

pub fn load(sync, dump: dump.Dump) {
  // let Dump(registry,packages, _raw) = dump
  let Sync(registry: registry, packages: packages, ..) = sync
  let registry = dict.merge(registry, dump.registry)
  let packages = dict.merge(packages, dump.packages)
  // Can work out value of blobs eagerly and stick them in the map.
  // use the checksum as lookup key
  // TODO do topological ordering
  let loaded =
    dict.map_values(dump.fragments, fn(_key, expression) {
      let expression = annotated.add_annotation(expression, [])
      let assert Ok(computed) = compute(expression, sync.loaded)
      computed
    })
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
        let latest = x - 1
        let assert Ok(hash_ref) = dict.get(package, latest)
        let assert Ok(Computed(type_: type_, ..)) = dict.get(loaded, hash_ref)
        Ok(#(named_ref(name, x - 1), type_))
      }
      _ -> Error(Nil)
    }
  })
}
