import drafting/view/page as d_view
import drafting/view/picker
import eyg/analysis/type_/binding
import eyg/runtime/break
import eyg/runtime/interpreter/runner
import eyg/runtime/value
import eyg/shell/buffer
import eyg/website/run
import gleam/javascript/promise
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
  Editing(buffer.Buffer, run.Run, List(#(String, EffectSpec)))
  Normal(editable.Expression, run.Run, List(#(String, EffectSpec)))
}

pub fn init(src, effects) {
  Normal(src, run.start(src, effects), effects)
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
        Editing(_, _, _) -> #(state, None)
        Normal(src, run, effects) -> {
          let src = editable.open_all(src)
          let proj = projection.focus_at(src, [])
          let buffer = buffer.from(proj)
          #(Editing(buffer, run, effects), None)
        }
      }
    MessageFromBuffer(message) ->
      case state {
        Normal(_, _, _) -> panic as "should never happen here"
        Editing(buffer, run, effects) -> {
          let buffer =
            buffer.update(
              buffer,
              message,
              analysis.empty_environment(),
              effect_types(effects),
            )
          let run = case buffer.1 {
            buffer.Command(_) ->
              run.start(projection.rebuild(buffer.0), effects)
            _ -> run
          }
          #(
            Editing(buffer, run, effects),
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
      let #(src, run.Run(status, effect_log), effects) = case state {
        Normal(src, run, effects) -> #(src, run, effects)
        Editing(#(p, _), run, effects) -> #(projection.rebuild(p), run, effects)
      }
      case status {
        run.Handling(_label, lift, env, k, blocking) -> {
          case blocking(lift) {
            Ok(promise) -> {
              let run = run.Run(status, effect_log)
              let state = Normal(src, run, effects)

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
              let state = Normal(src, run, effects)
              #(state, None)
            }
          }
        }
        _ -> #(state, None)
      }
    }
    RuntimeRepliedFromExternalEffect(reply) -> {
      let assert Normal(src, run, effects) = state
      let assert run.Run(run.Handling(label, lift, env, k, _), effect_log) = run

      let effect_log = [#(label, #(lift, reply)), ..effect_log]
      let status = case runner.real_resume(reply, env, k) {
        Ok(value) -> run.Done(value)
        Error(debug) -> run.handle_extrinsic_effects(debug, effects)
      }
      let run = run.Run(status, effect_log)
      let state = Normal(src, run, effects)
      case status {
        run.Done(_) | run.Failed(_) -> #(state, None)

        run.Handling(_label, lift, env, k, blocking) ->
          case blocking(lift) {
            Ok(promise) -> {
              let run = run.Run(status, effect_log)
              let state = Normal(src, run, effects)

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
              let state = Normal(src, run, effects)
              #(state, None)
            }
          }
      }
    }
  }
}

pub fn finish_editing(state: Snippet) {
  case state {
    Editing(#(proj, _mode), _run, effects) ->
      init(projection.rebuild(proj), effects)
    _ -> state
  }
}

pub fn render(state: Snippet) {
  h.div([a.class("bg-white neo-shadow font-mono mt-4 mb-6")], case state {
    Editing(#(proj, mode), run, _effects) ->
      case mode {
        buffer.Command(_) -> {
          [render_projection(proj, True), render_run(run.status)]
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

    Normal(src, run, _effects) -> [
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
      h.pre([a.class("border-2 border-green-3 px-2")], [
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
