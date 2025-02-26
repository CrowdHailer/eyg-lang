import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/expression as r
import eyg/interpreter/state.{type Value}
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/editable
import website/components/simple_debug
import website/sync/cache

pub type State(meta) {
  State(
    sync: cache.Cache,
    source: ir.Node(meta),
    // Value indicates if the app has ever run, 
    // a value of None means that initial editor was set up with empty program.
    // Values are parameterised to Nil because the fragments in the cache have nil metadata
    value: Option(Value(Nil)),
    // TODO make string an actual error
    type_errors: List(#(meta, String)),
    // update and render if we want to keep everything running
    ready_to_migrate: Bool,
  )
}

// Might should init when loading reference
// when writing you want to commit to the first state i.e. editing a number then record shouldn't require update function

// There are no events but there would be for a deploy example
// deploy example needs to push to netlify something to reload the page from state in local storage.
// upgrade logic for cookies

// print my own errors if the type ones don't work

// Stop rendering the app if type error
// if we need a set code function why not use it at the beginning
// the same could be true for sync
// pass in source with meta
// We don't trigger looking for refs from a run that is done by the snippet. A lot more runtimes than editors will exist

// Type safe server is easier because app needs a framework

// How do the calculators play out.

// JUST FIX THE RELOAD AS IS

pub fn init(sync, source) {
  let #(value, type_errors) = case type_check(sync, source, None) {
    Ok(#(_t, _upgrade)) -> {
      case run_init(sync, source) {
        Ok(value) -> #(Some(value), [])
        Error(_) -> {
          io.println("this should never error if the type checking has passed.")
          #(None, [])
        }
      }
    }
    Error(type_errors) -> #(None, type_errors)
  }
  State(sync, source, value, type_errors, False)
}

fn type_check(sync, source: ir.Node(List(Int)), value: Option(Value(Nil))) {
  let bindings = infer.new_state()
  let #(app_state_t, bindings) = case value {
    Some(v) -> {
      let #(poly, bindings) = analysis.value_to_type(v, bindings, Nil)
      binding.instantiate(poly, 1, bindings)
    }
    None -> binding.mono(1, bindings)
  }
  let types = cache.type_map(sync)
  do_check_against_state(bindings, types, source, app_state_t)
}

pub type Message(meta) {
  ParentUpdatedSource(source: ir.Node(meta))
  ParentUpdatedCache(cache: cache.Cache)
  UserClickedUpgrade
  UserClickedApp
}

pub fn update(state, message) {
  let State(sync:, source:, value:, ..) = state
  case message {
    ParentUpdatedSource(source) -> update_source(state, source)
    ParentUpdatedCache(cache) -> update_cache(state, cache)
    UserClickedUpgrade -> todo
    UserClickedApp ->
      case value {
        Some(value) -> {
          let args = [#(value, Nil), #(v.unit(), Nil)]
          case run_field(sync, source, "handle", args) {
            Ok(value) -> State(..state, value: Some(value))
            Error(_) -> todo as "handle was not ready"
          }
        }
        None -> {
          io.println("user clicked app but no value in state")
          state
        }
      }
  }
}

pub fn update_source(state, source) {
  let State(sync:, value:, ..) = state

  let state = State(..state, source:)
  case type_check(sync, source, value) {
    Ok(#(t, migrate)) ->
      State(..state, type_errors: [], ready_to_migrate: migrate)
    Error(type_errors) -> State(..state, type_errors:)
  }
}

pub fn update_cache(state, sync) {
  let State(source:, value:, ..) = state

  let state = State(..state, sync: sync)
  case type_check(sync, source, value) {
    Ok(#(_t, migrate)) ->
      State(..state, type_errors: [], ready_to_migrate: migrate)
    Error(type_errors) -> State(..state, type_errors:)
  }
}

pub fn render(state) {
  let State(value:, ready_to_migrate:, type_errors:, ..) = state
  h.div([], [
    h.p([], [element.text("App state")]),
    h.div([a.class("border-2 p-2")], [
      case value {
        Some(value) -> element.text(simple_debug.value_to_string(value))
        None -> element.text("has never started")
      },
    ]),
    h.p([], [element.text("Rendered app, click to send message")]),
    h.div([a.class("border-2 p-2")], [
      case type_errors, ready_to_migrate {
        [], True ->
          h.div([event.on_click(UserClickedUpgrade)], [
            element.text("click to upgrade"),
          ])
        [], False -> {
          let assert Some(value) = value
          let args = [#(value, Nil)]
          case run_field(state.sync, state.source, "render", args) {
            Ok(v.String(page)) -> render_app(page)
            _ -> todo as "Somenon string value"
            Error(_) -> todo as "handle was not ready"
          }
        }
        // snippet shows these
        _, _ ->
          h.div(
            [a.class("border-2 border-orange-3 px-2")],
            list.map(type_errors, fn(error) {
              let #(path, reason) = error
              h.div(
                [
                  // event.on_click(state.SnippetMessage(
                //   state.hot_reload_key,
                //   snippet.UserClickedPath(path),
                // )),
                ],
                [element.text(reason)],
              )
            }),
          )
        // element.none()
      },
    ]),
  ])
}

pub fn render_app(page) {
  h.div(
    [
      a.attribute("dangerous-unescaped-html", page),
      // TODO get closest
      event.on_click(UserClickedApp),
    ],
    [],
  )
}

// helpers

fn cache_run(sync, return: Result(Value(Nil), state.Debug(Nil))) {
  cache.run(return, sync, r.resume)
}

fn run_init(sync, source) {
  run_field(sync, source, "init", [])
}

fn run_field(sync, source: ir.Node(List(_)), field, args) {
  case cache_run(sync, r.execute_next(source |> ir.clear_annotation, [])) {
    Ok(value) -> {
      let select = v.Partial(v.Select(field), [])
      case r.call_next(select, [#(value, Nil), ..args]) {
        Ok(initial) -> Ok(initial)
        _ -> panic as "we should put the error for this somewhere: init"
      }
    }
    Error(_) -> panic as "we should put the error for this somewhere"
  }
}

fn handle_t(state, message) {
  t.Fun(state, t.Empty, t.Fun(message, t.Empty, state))
}

fn render_t(state) {
  t.Fun(state, t.Empty, t.String)
}

// TODO make private
pub fn check_against_state(editable, old_state, refs) {
  let b = infer.new_state()
  let #(old_state, b) = binding.instantiate(old_state, 1, b)
  let source = editable.to_annotated(editable, [])
  do_check_against_state(b, refs, source, old_state)
}

fn do_check_against_state(b, refs, source, old_state) {
  let level = 1
  // do infer allows returning top got value, which i don't need?
  let #(tree, b) =
    infer.infer(
      // source
      source,
      // env
      // [],
      // eff
      t.Empty,
      refs,
      level,
      b,
    )

  let paths = ir.get_annotation(source)
  let info = ir.get_annotation(tree)
  let assert Ok(info) = list.strict_zip(paths, info)
  let type_errors =
    list.filter_map(info, fn(info) {
      let #(path, #(r, _, _, _)) = info
      case r {
        Ok(_) -> Error(Nil)
        Error(reason) -> Ok(#(path, debug.reason(reason)))
      }
    })
  case type_errors {
    [] -> {
      let #(_, meta) = tree
      let #(_, program, _, _) = meta

      let #(rest, b) = binding.mono(level, b)
      let #(new_state, b) = binding.mono(level, b)

      // Needs to be open for handle etc
      let init_field = t.Record(t.do_rows([#("init", new_state)], rest))

      case unify.unify(init_field, program, level, b) {
        Ok(b) -> {
          // if has init check if init is old or new state type
          let #(migrate_field, upgrade, b) = case
            unify.unify(old_state, new_state, level, b)
          {
            Ok(b) -> {
              #([], False, b)
            }
            Error(_reason) -> {
              let migrate_field = #(
                "migrate",
                t.Fun(old_state, t.Empty, new_state),
              )
              #([migrate_field], True, b)
            }
          }
          let #(new_message, b) = binding.mono(level, b)
          let handle_field = #("handle", handle_t(new_state, new_message))
          let render_field = #("render", render_t(new_state))
          let #(remainder, b) = binding.mono(level, b)

          let expect =
            t.do_rows([handle_field, render_field, ..migrate_field], remainder)
          case unify.unify(expect, rest, level, b) {
            Ok(b) -> {
              let state = binding.resolve(new_state, b)
              let state = binding.gen(state, 1, b)
              case all_general(state) {
                True -> Ok(#(state, upgrade))
                False -> Error([#([], "Not all generalisable")])
              }
            }
            Error(reason) -> {
              Error([#([], debug.reason(reason))])
            }
          }
        }
        Error(reason) -> {
          Error([#([], debug.reason(reason))])
        }
      }
    }
    _ -> Error(type_errors)
  }
}

fn all_general(type_) {
  infer.ftv(type_)
  |> set.filter(fn(t) {
    let #(g, _) = t
    !g
  })
  |> set.is_empty
}
