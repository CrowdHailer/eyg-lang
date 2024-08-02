import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error
import eyg/runtime/break
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
    loaded: Dict(String, Computed),
  )
}

pub fn init(origin) {
  Sync(origin, dict.new(), [], dict.new())
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
  let Sync(origin, running, pending, loaded) = sync
  let missing = missing(sync, refs)

  let #(tasks, running) = do_fetch_missing(missing, origin, running)
  let sync = Sync(origin, running, pending, loaded)
  #(sync, tasks)
}

pub fn fetch_all_missing(sync) {
  let Sync(origin, running, pending, loaded) = sync
  let missing =
    list.flat_map(pending, fn(pending) {
      let #(_ref, #(deps, _source)) = pending
      deps
    })
  let #(tasks, running) = do_fetch_missing(missing, origin, running)
  let sync = Sync(origin, running, pending, loaded)
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

pub fn task_finish(sync, ref, result) {
  let Sync(tasks: tasks, ..) = sync
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
}

pub fn install(sync, ref, expression) {
  let Sync(origin, running, pending, loaded) = sync
  let source = annotated.add_annotation(expression, [])

  case compute(source, loaded) {
    Ok(computed) -> {
      let loaded = dict.insert(loaded, ref, computed)
      let #(pending, loaded) = do_resolve(pending, loaded)
      Sync(origin, running, pending, loaded)
    }
    Error(return) -> {
      let pending = [#(ref, return), ..pending]
      Sync(origin, running, pending, loaded)
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
