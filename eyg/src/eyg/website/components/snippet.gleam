import drafting/view/page as d_view
import drafting/view/picker
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/runtime/break
import eyg/runtime/interpreter/runner
import eyg/runtime/value
import eyg/shell/buffer
import eyg/sync/sync
import eyg/website/run
import eygir/annotated
import gleam/javascript/promise
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/editable
import morph/lustre/render
import morph/projection
import plinth/browser/document
import plinth/browser/element as dom_element
import plinth/browser/window

type ExternalBlocking =
  fn(run.Value) -> Result(promise.Promise(run.Value), run.Reason)

type EffectSpec =
  #(binding.Mono, binding.Mono, ExternalBlocking)

pub type Snippet {
  Editing(buffer.Buffer, run.Run, List(#(String, EffectSpec)), sync.Sync)
  Normal(editable.Expression, run.Run, List(#(String, EffectSpec)), sync.Sync)
}

pub fn init(src, effects, cache) {
  Normal(src, run.start(src, effects, cache), effects, cache)
}

pub fn set_references(state: Snippet, cache) {
  case state {
    Editing(buf, run, eff, _cache) ->
      Editing(buf, run.start(projection.rebuild(buf.0), eff, cache), eff, cache)
    Normal(src, run, eff, _cache) ->
      Normal(src, run.start(src, eff, cache), eff, cache)
  }
}

pub fn references(state: Snippet) {
  case state {
    Normal(src, _, _, _) ->
      editable.to_annotated(src, []) |> annotated.list_references()
    Editing(buffer, _, _, _) -> buffer.references(buffer)
  }
}

pub type Message {
  UserFocusedOnCode
  UserClickRunEffects
  MessageFromBuffer(buffer.Message)
  RuntimeRepliedFromExternalEffect(run.Value)
}

fn effect_types(effects: List(#(String, EffectSpec))) {
  listx.value_map(effects, fn(details) { #(details.0, details.1) })
}

pub fn update(state, message) {
  case message {
    UserFocusedOnCode ->
      case state {
        Editing(_, _, _, _) -> #(state, None)
        Normal(src, run, effects, references) -> {
          let src = editable.open_all(src)
          let proj = projection.focus_at(src, [])
          let buffer = buffer.from(proj)
          #(Editing(buffer, run, effects, references), None)
        }
      }
    MessageFromBuffer(message) ->
      case state {
        Normal(_, _, _, _) -> panic as "should never happen here"
        Editing(buffer, run, effects, cache) -> {
          let buffer =
            buffer.update(
              buffer,
              message,
              analysis.with_references(sync.types(cache)),
              effect_types(effects),
            )
          let run = case buffer.1 {
            buffer.Command(_) ->
              run.start(projection.rebuild(buffer.0), effects, cache)
            _ -> run
          }
          #(
            Editing(buffer, run, effects, cache),
            Some(fn(_) {
              window.request_animation_frame(fn(_) {
                case document.query_selector("[autofocus]") {
                  Ok(el) -> dom_element.focus(el)
                  Error(Nil) -> Nil
                }
              })
              Nil
            }),
          )
        }
      }
    UserClickRunEffects -> {
      let #(src, run.Run(status, effect_log), effects, cache) = case state {
        Normal(src, run, effects, cache) -> #(src, run, effects, cache)
        Editing(#(p, _), run, effects, cache) -> #(
          projection.rebuild(p),
          run,
          effects,
          cache,
        )
      }
      case status {
        run.Handling(_label, lift, env, k, blocking) -> {
          case blocking(lift) {
            Ok(promise) -> {
              let run = run.Run(status, effect_log)
              let state = Normal(src, run, effects, cache)

              #(
                state,
                Some(fn(d) {
                  promise.map(promise, fn(value) {
                    d(RuntimeRepliedFromExternalEffect(value))
                  })
                  Nil
                }),
              )
            }
            Error(reason) -> {
              let run = run.Run(run.Failed(#(reason, Nil, env, k)), effect_log)
              let state = Normal(src, run, effects, cache)
              #(state, None)
            }
          }
        }
        _ -> #(state, None)
      }
    }
    RuntimeRepliedFromExternalEffect(reply) -> {
      let assert Normal(src, run, effects, cache) = state
      let assert run.Run(run.Handling(label, lift, env, k, _), effect_log) = run

      let effect_log = [#(label, #(lift, reply)), ..effect_log]
      let status = case runner.resume(reply, env, k) {
        Ok(value) -> run.Done(value)
        Error(debug) -> run.handle_extrinsic_effects(debug, effects)
      }
      let run = run.Run(status, effect_log)
      let state = Normal(src, run, effects, cache)
      case status {
        run.Done(_) | run.Failed(_) -> #(state, None)

        run.Handling(_label, lift, env, k, blocking) ->
          case blocking(lift) {
            Ok(promise) -> {
              let run = run.Run(status, effect_log)
              let state = Normal(src, run, effects, cache)

              #(
                state,
                Some(fn(d) {
                  promise.map(promise, fn(value) {
                    d(RuntimeRepliedFromExternalEffect(value))
                  })
                  Nil
                }),
              )
            }
            Error(reason) -> {
              let run = run.Run(run.Failed(#(reason, Nil, env, k)), effect_log)
              let state = Normal(src, run, effects, cache)
              #(state, None)
            }
          }
      }
    }
  }
}

pub fn finish_editing(state: Snippet) {
  case state {
    Editing(#(proj, _mode), _run, effects, cache) ->
      init(projection.rebuild(proj), effects, cache)
    _ -> state
  }
}

pub fn render(state: Snippet) {
  h.div([a.class("bg-white neo-shadow font-mono mt-4 mb-6")], case state {
    Editing(#(proj, mode), run, effects, cache) ->
      case mode {
        buffer.Command(_) -> {
          let eff =
            effect_types(effects)
            |> list.fold(t.Empty, fn(acc, new) {
              let #(label, #(lift, reply)) = new
              t.EffectExtend(label, #(lift, reply), acc)
            })
          let a =
            analysis.analyse(
              proj,
              analysis.with_references(sync.types(cache)),
              eff,
            )
          let errors = analysis.type_errors(a)
          [
            render_projection(proj, True),
            case errors {
              [] -> render_run(run.status)
              _ ->
                h.div(
                  [a.class("border-2 border-orange-3 px-2")],
                  list.map(errors, fn(error) {
                    let #(path, reason) = error
                    h.div(
                      [event.on_click(MessageFromBuffer(buffer.JumpTo(path)))],
                      [element.text(debug.reason(reason))],
                    )
                  }),
                )
            },
          ]
        }
        buffer.Pick(picker, _rebuild) -> [
          render_projection(proj, False),
          pallet(picker.render(picker, buffer.UpdatePicker)),
        ]

        buffer.EditText(value, _rebuild) -> [
          render_projection(proj, False),
          pallet(d_view.string_input(value)),
        ]

        buffer.EditInteger(value, _rebuild) -> [
          render_projection(proj, False),
          pallet(d_view.integer_input(value)),
        ]
      }

    Normal(src, run, _effects, _) -> [
      h.div(
        [
          a.class(
            "border-l-4 py-1 px-2 border-white outline-none focus:border-black",
          ),
          a.attribute("tabindex", "0"),
          event.on_focus(UserFocusedOnCode),
        ],
        render.statements(src),
      ),
      render_run(run.status),
    ]
  })
}

fn pallet(items) {
  items
  |> element.map(MessageFromBuffer)
}

fn render_projection(proj, autofocus) {
  h.div(
    [
      a.class(
        "border-l-4 py-1 px-2 border-white outline-none focus:border-black",
      ),
      ..case autofocus {
        True -> [
          a.attribute("tabindex", "0"),
          a.attribute("autofocus", "true"),
          // a.autofocus(True),
          event.on_keydown(fn(key) { MessageFromBuffer(buffer.KeyDown(key)) }),
        ]
        False -> []
      }
    ],
    [render.projection(proj, False)],
  )
}

fn render_run(run) {
  case run {
    run.Done(value) ->
      h.pre([a.class("border-2 border-green-3 px-2 overflow-auto")], [
        element.text(value.debug(value)),
      ])
    run.Handling(label, _meta, _env, _stack, _blocking) ->
      h.pre(
        [
          a.class("border-2 border-blue-3 px-2"),
          event.on_click(UserClickRunEffects),
        ],
        [
          element.text("Will run "),
          element.text(label),
          element.text(" effect. click to continue."),
        ],
      )
    run.Failed(#(reason, _, _, _)) ->
      h.pre([a.class("border-2 border-orange-3 px-2")], [
        element.text(break.reason_to_string(reason)),
      ])
  }
}
