//// The reload component allows no effects

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/binding/unify
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/expression
import eyg/interpreter/expression as r
import eyg/interpreter/state.{type Value}
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/editable as e
import website/components/runner
import website/components/simple_debug
import website/components/snippet.{type Snippet, Snippet}
import website/sync/cache

// maybe it should be called example or sample
pub type Reload(meta) {
  Reload(
    cache: cache.Cache,
    snippet: Snippet,
    // derived values
    return: runner.Return(state.Value(Nil), Nil),
    // A value indicates if the app has ever run, 
    // No value only occurs when the editor was set up with an invalid empty program.
    // Values are parameterised to Nil because the fragments in the cache have Nil metadata
    // 
    // Init is not automatically called if the starting value is Nil because users might edit via a valid program
    value: Option(Value(Nil)),
    // update and render if we want to keep everything running
    ready_to_migrate: Bool,
  )
}

pub fn init(source, cache) {
  let snippet =
    e.from_annotated(source)
    |> e.open_all
    |> snippet.init()

  let return = execute_snippet(snippet)

  let state =
    Reload(cache:, snippet:, return:, value: None, ready_to_migrate: False)
    |> do_analysis
  case type_errors(state) {
    Some([]) -> update_app(state)
    Some(_) -> state
    None -> panic as "the analysis should always occur"
  }
}

pub fn finish_editing(state) {
  let Reload(snippet:, ..) = state
  let snippet = snippet.finish_editing(snippet)
  Reload(..state, snippet:)
}

pub fn update_cache(state, cache) {
  let Reload(snippet:, ..) = state
  let return = execute_snippet(snippet)
  let state =
    Reload(..state, cache:, return:)
    |> do_analysis
  #(state, Nothing)
}

pub type Message(meta) {
  SnippetMessage(snippet.Message)
  ParentUpdatedSource(source: ir.Node(meta))
  ParentUpdatedCache(cache: cache.Cache)
  UserClickedMigrate
  UserClickedApp
}

pub type Action {
  Nothing
  Failed(snippet.Failure)
  ReturnToCode
  FocusOnInput
  ReadFromClipboard
  WriteToClipboard(text: String)
}

pub fn update(state, message) {
  case message {
    SnippetMessage(message) -> {
      let Reload(snippet:, ..) = state
      let #(snippet, action) = snippet.update(snippet, message)
      let state = Reload(..state, snippet:)
      case action {
        snippet.Nothing -> #(state, Nothing)
        snippet.NewCode -> {
          let return = execute_snippet(snippet)
          let state = Reload(..state, return:)
          let state = do_analysis(state)

          #(state, Nothing)
        }
        snippet.Confirm -> {
          let Reload(ready_to_migrate:, ..) = state
          case ready_to_migrate {
            True -> #(update_app(state), Nothing)
            False -> #(state, Nothing)
          }
        }
        snippet.Failed(failure) -> #(state, Failed(failure))
        snippet.ReturnToCode -> #(state, ReturnToCode)
        snippet.FocusOnInput -> #(state, FocusOnInput)
        snippet.ToggleHelp -> #(state, Nothing)
        snippet.MoveAbove -> #(state, Nothing)
        snippet.MoveBelow -> #(state, Nothing)
        snippet.ReadFromClipboard -> #(state, ReadFromClipboard)
        snippet.WriteToClipboard(text) -> #(state, WriteToClipboard(text))
      }
    }
    ParentUpdatedSource(source) -> {
      let snippet =
        e.from_annotated(source)
        |> e.open_all
        |> snippet.init()
      let return = execute_snippet(snippet)
      let state = do_analysis(Reload(..state, snippet:, return:))
      #(state, Nothing)
    }
    ParentUpdatedCache(cache) -> update_cache(state, cache)
    UserClickedMigrate -> #(update_app(state), Nothing)
    UserClickedApp -> {
      let Reload(value:, ..) = state
      let state = case value {
        Some(value) -> {
          let args = [#(value, Nil), #(v.unit(), Nil)]
          case run_field(state, "handle", args) {
            Ok(value) -> Reload(..state, value: Some(value))
            Error(_) -> {
              io.println("user clicked app but the handle function failed")
              state
            }
          }
        }
        None -> {
          io.println("user clicked app but no value in state")
          state
        }
      }
      #(state, Nothing)
    }
  }
}

fn execute_snippet(snippet) {
  let Snippet(editable:, ..) = snippet
  let source = editable |> e.to_annotated([]) |> ir.clear_annotation
  expression.execute(source, [])
}

pub fn update_app(state) {
  let Reload(value:, ..) = state
  let result = case value {
    Some(value) -> run_field(state, "migrate", [#(value, Nil)])
    None -> run_field(state, "init", [])
  }
  let state = case result {
    Ok(value) -> Reload(..state, value: Some(value), ready_to_migrate: False)
    Error(_) -> {
      io.println("user clicked migrate which failed")
      state
    }
  }
  state
}

pub fn render(state) {
  let Reload(snippet:, value:, ready_to_migrate:, ..) = state

  h.div([], [
    snippet.render_embedded_with_top_menu(snippet, [])
      |> element.map(SnippetMessage),
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
        case type_errors(state), ready_to_migrate {
          Some([]), True ->
            h.div([event.on_click(UserClickedMigrate)], [
              element.text("click to upgrade"),
            ])
          Some([]), False -> {
            let assert Some(value) = value
            case run_field(state, "render", [#(value, Nil)]) {
              Ok(v.String(page)) -> render_app(page)
              Ok(_) -> element.text("app render did not return a string")
              Error(_) ->
                element.text("app render failed, this should not happen")
            }
          }
          // snippet shows these
          type_errors, _ ->
            h.div(
              [a.class("border-2 border-orange-3 px-2")],
              list.map(option.unwrap(type_errors, []), fn(error) {
                let #(_path, reason) = error
                h.div(
                  [
                    // event.on_click(state.SnippetMessage(
                  //   state.hot_reload_key,
                  //   snippet.UserClickedPath(path),
                  // )),
                  ],
                  [element.text(debug.reason(reason))],
                )
              }),
            )
          // element.none()
        },
      ]),
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

fn run_field(state, field, args) {
  let Reload(cache:, return:, ..) = state
  case cache.run(return, cache, expression.resume) {
    Ok(value) -> {
      let select = v.Partial(v.Select(field), [])
      case r.call(select, [#(value, Nil), ..args]) {
        Ok(initial) -> Ok(initial)
        Error(debug) -> Error(debug)
      }
    }
    Error(reason) -> Error(reason)
  }
}

// Type checking ------------------------------

fn handle_t(state, message) {
  t.Fun(state, t.Empty, t.Fun(message, t.Empty, state))
}

fn render_t(state) {
  t.Fun(state, t.Empty, t.String)
}

fn do_analysis(state) {
  let Reload(cache:, snippet:, value:, ..) = state
  let source = snippet.editable |> e.to_annotated([])
  let #(analysis, ready_to_migrate) = type_check(cache, source, value)
  let snippet = Snippet(..snippet, analysis: Some(analysis))
  Reload(..state, snippet:, ready_to_migrate:)
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

fn do_check_against_state(b, refs, source, old) {
  let level = 1
  let context = analysis.Context(b, [], [], refs, [])
  let #(tree, b) = infer.infer(source, t.Empty, refs, level, b)

  let #(inner, meta) = tree
  let #(original_err, program, _, _) = meta

  let #(rest, b) = binding.mono(level, b)
  let #(new, b) = binding.mono(level, b)

  // Needs to be open for handle etc
  let init_field = t.Record(t.do_rows([#("init", new)], rest))

  let #(meta, b, migrate) = case unify.unify(init_field, program, level, b) {
    Ok(b) -> {
      // if has init check if init is old or new state type
      let #(migrate_field, upgrade, b) = case unify.unify(old, new, level, b) {
        Ok(b) -> #([], False, b)
        Error(_reason) -> {
          let migrate_field = #("migrate", t.Fun(old, t.Empty, new))
          #([migrate_field], True, b)
        }
      }
      let #(new_message, b) = binding.mono(level, b)
      let handle_field = #("handle", handle_t(new, new_message))
      let render_field = #("render", render_t(new))
      let #(remainder, b) = binding.mono(level, b)

      let expect =
        t.do_rows([handle_field, render_field, ..migrate_field], remainder)
      case unify.unify(expect, rest, level, b) {
        Ok(b) -> #(
          #(
            case original_err {
              Ok(_) -> Ok(Nil)
              // keep original error because if it did error then calculation proceeds with permissive type
              Error(reason) -> Error(reason)
            },
            program,
            t.Empty,
            [],
          ),
          b,
          upgrade,
        )
        Error(reason) -> #(#(Error(reason), program, t.Empty, []), b, False)
      }
    }
    Error(reason) -> {
      #(#(Error(reason), program, t.Empty, []), b, False)
    }
  }
  let tree: ir.Node(_) = #(inner, meta)
  let paths = ir.get_annotation(source)
  let info = ir.get_annotation(tree)
  let assert Ok(inferred) = list.strict_zip(paths, info)
  #(analysis.Analysis(bindings: b, inferred: inferred, context:), migrate)
}

pub fn type_errors(state) {
  let Reload(snippet:, ..) = state
  case snippet.analysis {
    Some(analysis) -> Some(analysis.type_errors(analysis))
    None -> None
  }
}
