import drafting/view/page as d_view
import drafting/view/picker
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/runtime/break
import eyg/runtime/interpreter/block
import eyg/runtime/interpreter/runner
import eyg/shell/buffer
import eyg/sync/sync
import eyg/website/components/output
import eyg/website/run
import eygir/annotated
import eygir/decode
import eygir/encode
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/editable
import morph/lustre/render
import morph/projection
import plinth/browser/clipboard
import plinth/browser/document
import plinth/browser/element as dom_element
import plinth/browser/event as pevent
import plinth/browser/window

type ExternalBlocking =
  fn(run.Value) -> Result(promise.Promise(run.Value), run.Reason)

type EffectSpec =
  #(binding.Mono, binding.Mono, ExternalBlocking)

pub type Status {
  Idle(editable.Expression)
  Editing(buffer.Buffer)
}

pub type Snippet {
  Snippet(
    status: Status,
    run: run.Run,
    effects: List(#(String, EffectSpec)),
    cache: sync.Sync,
  )
}

pub fn init(src, effects, cache) {
  Snippet(Idle(src), run.start(src, effects, cache), effects, cache)
}

pub fn run(state) {
  let Snippet(run: run, ..) = state
  run
}

pub fn source(state) {
  let Snippet(status: status, ..) = state

  case status {
    Editing(buf) -> projection.rebuild(buf.0)
    Idle(exp) -> exp
  }
}

// This uses some none because otherwise it feels back to front. I.e. should I return OK if there is
// a key error
pub fn key_error(state) {
  let Snippet(status: status, ..) = state

  case status {
    Editing(#(_, buffer.Command(Some(buffer.NoKeyBinding(k))))) -> Some(k)
    _ -> None
  }
}

pub fn set_references(state, cache) {
  let run = run.start(source(state), state.effects, cache)
  Snippet(..state, run: run, cache: cache)
}

pub fn references(state) {
  let Snippet(status: status, ..) = state

  case status {
    Idle(src) -> editable.to_annotated(src, []) |> annotated.list_references()
    Editing(buffer) -> buffer.references(buffer)
  }
}

pub type Message {
  UserFocusedOnCode
  UserClickRunEffects
  MessageFromBuffer(buffer.Message)
  RuntimeRepliedFromExternalEffect(run.Value)
  ClipboardReadCompleted(Result(String, String))
}

fn effect_types(effects: List(#(String, EffectSpec))) {
  listx.value_map(effects, fn(details) { #(details.0, details.1) })
}

pub fn update(state, message) {
  let Snippet(status: status, run: run, effects: effects, cache: cache) = state
  case message {
    UserFocusedOnCode ->
      case status {
        Editing(_) -> #(state, None)
        Idle(src) -> {
          let src = editable.open_all(src)
          let proj = projection.focus_at(src, [])
          let buffer = buffer.from(proj)
          let status = Editing(buffer)
          #(Snippet(..state, status: status), None)
        }
      }
    MessageFromBuffer(message) ->
      case status {
        Idle(_) -> panic as "should never happen here"
        Editing(buffer) -> {
          let buffer =
            buffer.update(
              buffer,
              message,
              analysis.with_references(sync.types(cache)),
              effect_types(effects),
            )
          let run = case buffer.1 {
            buffer.Command(None) ->
              run.start(projection.rebuild(buffer.0), effects, cache)
            _ -> run
          }
          case buffer.1 {
            buffer.Command(Some(buffer.NoKeyBinding("y"))) -> {
              case buffer.0 {
                #(projection.Exp(expression), _) -> {
                  let eff =
                    Some(fn(_d) {
                      clipboard.write_text(
                        encode.to_json(editable.to_expression(expression)),
                      )
                      // TODO better copy error
                      |> promise.map(io.debug)
                      Nil
                    })
                  let status = Editing(buffer)
                  #(Snippet(status, run, effects, cache), eff)
                }
                _ -> {
                  todo as "need to wire up faiing copy"
                  // #(proj, Command(Some(ActionFailed("copy"))))
                }
              }
            }
            buffer.Command(Some(buffer.NoKeyBinding("Y"))) -> {
              let eff =
                Some(fn(d) {
                  use return <- promisex.aside(clipboard.read_text())
                  d(ClipboardReadCompleted(return))
                })
              let status = Editing(buffer)
              #(Snippet(status, run, effects, cache), eff)
            }
            buffer.Command(Some(buffer.NoKeyBinding("Enter"))) -> {
              case run.status {
                run.Done(_, _) | run.Failed(_) -> #(
                  Snippet(Editing(buffer), run, effects, cache),
                  None,
                )
                _ -> {
                  let status = Editing(buffer)
                  let state = Snippet(status, run, effects, cache)
                  run_effects(state)
                }
              }
            }

            _ -> {
              let eff =
                Some(fn(_) {
                  window.request_animation_frame(fn(_) {
                    case document.query_selector("[autofocus]") {
                      Ok(el) -> {
                        dom_element.focus(el)
                        // This can only be done when we move to a new focus
                        // dom_element.set_selection_range(el, 0, -1)
                      }
                      Error(Nil) -> Nil
                    }
                  })
                  Nil
                })
              #(Snippet(Editing(buffer), run, effects, cache), eff)
            }
          }
        }
      }
    UserClickRunEffects -> run_effects(state)
    RuntimeRepliedFromExternalEffect(reply) -> {
      let assert Snippet(Idle(src), run, effects, cache) = state
      let assert run.Run(run.Handling(label, lift, env, k, _), effect_log) = run

      let effect_log = [#(label, #(lift, reply)), ..effect_log]
      let status = case block.resume(reply, env, k) {
        Ok(#(value, env)) -> run.Done(value, env)
        Error(debug) -> run.handle_extrinsic_effects(debug, effects)
      }
      let run = run.Run(status, effect_log)
      let state = Snippet(Idle(src), run, effects, cache)
      case status {
        run.Done(_, _) | run.Failed(_) -> #(state, None)

        run.Handling(_label, lift, env, k, blocking) ->
          case blocking(lift) {
            Ok(promise) -> {
              let run = run.Run(status, effect_log)
              let state = Snippet(Idle(src), run, effects, cache)

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
              let state = Snippet(Idle(src), run, effects, cache)
              #(state, None)
            }
          }
      }
    }
    ClipboardReadCompleted(return) -> {
      case return {
        Ok(text) ->
          case decode.from_json(text) {
            Ok(expression) -> {
              let assert Snippet(Editing(#(proj, mode)), _run, effects, cache) =
                state
              let assert #(projection.Exp(_), zoom) = proj
              let proj = #(
                projection.Exp(editable.from_expression(expression)),
                zoom,
              )
              let run = run.start(projection.rebuild(proj), effects, cache)
              let state = Snippet(Editing(#(proj, mode)), run, effects, cache)
              #(state, None)
            }
            Error(_) -> todo as "failed to paste"
          }

        Error(reason) -> panic as reason
      }
    }
  }
}

fn run_effects(state) {
  let Snippet(status: _status, run: run, effects: effects, cache: cache) = state
  let run.Run(status, effect_log) = run
  let src = source(state)
  case status {
    run.Handling(_label, lift, env, k, blocking) -> {
      case blocking(lift) {
        Ok(promise) -> {
          let run = run.Run(status, effect_log)
          let state = Snippet(Idle(src), run, effects, cache)

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
          let state = Snippet(Idle(src), run, effects, cache)
          #(state, None)
        }
      }
    }
    _ -> #(state, None)
  }
}

pub fn finish_editing(state: Snippet) {
  let Snippet(status: status, effects: effects, cache: cache, ..) = state
  case status {
    Editing(#(proj, _mode)) -> init(projection.rebuild(proj), effects, cache)
    _ -> state
  }
}

pub fn render(state: Snippet) {
  h.div(
    [
      a.class(
        "bg-white neo-shadow font-mono mt-2 mb-6 border border-black flex flex-col",
      ),
      // a.style([#("min-height", "18ch")]),
    ],
    bare_render(state),
  )
}

pub fn render_sticky(state: Snippet) {
  h.div(
    [
      a.class(
        "bg-white neo-shadow font-mono mt-2 sticky bottom-6 mb-6 border border-black flex flex-col",
      ),
    ],
    bare_render(state),
  )
}

pub fn render_editor(state: Snippet) {
  h.div(
    [
      a.class(
        "bg-white neo-shadow font-mono mt-2 mb-6 border border-black flex flex-col",
      ),
      a.style([
        #("min-height", "15em"),
        #("height", "100%"),
        #("max-height", "95%"),
      ]),
    ],
    bare_render(state),
  )
}

pub fn bare_render(state) {
  let Snippet(status, run, effects, cache) = state
  case status {
    Editing(#(proj, mode)) ->
      case mode {
        buffer.Command(e) -> {
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
            case e {
              Some(failure) ->
                h.div([a.class("border-2 border-orange-4 px-2")], [
                  element.text(fail_message(failure)),
                ])
              None ->
                case errors {
                  [] -> render_run(run.status)
                  _ ->
                    h.div(
                      [a.class("border-2 border-orange-3 px-2")],
                      list.map(errors, fn(error) {
                        let #(path, reason) = error
                        h.div(
                          [
                            event.on_click(
                              MessageFromBuffer(buffer.JumpTo(path)),
                            ),
                          ],
                          [element.text(debug.reason(reason))],
                        )
                      }),
                    )
                }
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

    Idle(src) -> [
      h.div(
        [
          a.class("p-2 outline-none my-auto"),
          a.attribute("tabindex", "0"),
          event.on_focus(UserFocusedOnCode),
        ],
        render.statements(src),
      ),
      render_run(run.status),
    ]
  }
}

fn pallet(items) {
  items
  |> element.map(MessageFromBuffer)
}

fn render_projection(proj, autofocus) {
  h.div(
    [
      a.class("p-2 outline-none my-auto"),
      ..case autofocus {
        True -> [
          a.attribute("tabindex", "0"),
          a.attribute("autofocus", "true"),
          // a.autofocus(True),
          event.on("keydown", fn(event) {
            let assert Ok(event) = pevent.cast_keyboard_event(event)
            let key = pevent.key(event)
            let shift = pevent.shift_key(event)
            let ctrl = pevent.ctrl_key(event)
            let alt = pevent.alt_key(event)
            case key {
              "Alt" | "Ctrl" | "Shift" | "Tab" -> Error([])
              k if shift -> {
                pevent.prevent_default(event)
                Ok(MessageFromBuffer(buffer.KeyDown(string.uppercase(k))))
              }
              _ if ctrl || alt -> Error([])
              k -> {
                pevent.prevent_default(event)
                Ok(MessageFromBuffer(buffer.KeyDown(k)))
              }
            }
          }),
        ]
        False -> []
      }
    ],
    [render.projection(proj, False)],
  )
}

fn render_run(run) {
  case run {
    run.Done(value, _) ->
      h.pre([a.class("border-2 border-green-3 px-2 overflow-auto")], [
        case value {
          Some(value) -> output.render(value)
          None -> element.text("no value")
        },
        // element.text(value.debug(value)),
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

pub fn fail_message(reason) {
  case reason {
    buffer.NoKeyBinding(key) ->
      string.concat(["No action bound for key '", key, "'"])
    buffer.ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
  }
}
