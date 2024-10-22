import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/runtime/break
import eyg/runtime/interpreter/block
import eyg/runtime/interpreter/state as istate
import eyg/runtime/value as v
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
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import lustre/event
import morph/analysis
import morph/buffer
import morph/editable
import morph/input
import morph/lustre/render
import morph/navigation
import morph/picker
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
  Idle
  Editing(buffer.Mode)
}

type Path =
  Nil

type Value =
  v.Value(Path, #(List(#(istate.Kontinue(Path), Path)), istate.Env(Path)))

type Scope =
  List(#(String, Value))

pub type Snippet {
  Snippet(
    status: Status,
    source: #(
      projection.Projection,
      editable.Expression,
      Option(analysis.Analysis),
    ),
    run: run.Run,
    scope: Scope,
    effects: List(#(String, EffectSpec)),
    cache: sync.Sync,
  )
}

pub fn init(src, scope, effects, cache) {
  let src = editable.open_all(src)
  let proj = navigation.first(src)
  Snippet(
    Idle,
    #(proj, src, None),
    run.start(src, scope, effects, cache),
    scope,
    effects,
    cache,
  )
}

pub fn run(state) {
  let Snippet(run: run, ..) = state
  run
}

pub fn source(state) {
  let Snippet(source: #(_, source, _), ..) = state
  source
}

pub fn action_error(state) {
  let Snippet(status: status, ..) = state

  case status {
    Editing(buffer.Command(err)) -> err
    _ -> None
  }
}

pub fn set_references(state, cache) {
  let run = run.start(source(state), state.scope, state.effects, cache)
  Snippet(..state, run: run, cache: cache)
}

pub fn references(state) {
  editable.to_annotated(source(state), []) |> annotated.list_references()
}

pub type Message {
  UserFocusedOnCode
  UserClickRunEffects
  MessageFromBuffer(buffer.Message)
  MessageFromInput(input.Message)
  MessageFromPicker(picker.Message)
  RuntimeRepliedFromExternalEffect(run.Value)
  ClipboardReadCompleted(Result(String, String))
}

fn effect_types(effects: List(#(String, EffectSpec))) {
  listx.value_map(effects, fn(details) { #(details.0, details.1) })
}

pub fn update(state, message) {
  let Snippet(
    status: status,
    source: #(proj, editable, analysis) as source,
    run: run,
    scope: scope,
    effects: effects,
    cache: cache,
  ) = state
  case message, status {
    UserFocusedOnCode, Idle -> #(
      Snippet(..state, status: Editing(buffer.Command(None))),
      None,
    )
    // Throw away input or pick state
    UserFocusedOnCode, Editing(_) -> #(
      Snippet(..state, status: Editing(buffer.Command(None))),
      None,
    )
    MessageFromBuffer(buffer.KeyDown("y")), Editing(buffer.Command(_)) -> {
      case proj {
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
          #(state, eff)
        }
        _ -> {
          let status = buffer.Command(Some(buffer.ActionFailed("copy")))
          let state = Snippet(..state, status: Editing(status))
          #(state, None)
        }
      }
    }
    MessageFromBuffer(buffer.KeyDown("Y")), Editing(buffer.Command(_)) -> {
      let eff =
        Some(fn(d) {
          use return <- promisex.aside(clipboard.read_text())
          d(ClipboardReadCompleted(return))
        })
      #(state, eff)
    }

    MessageFromBuffer(buffer.KeyDown("Enter")), Editing(buffer.Command(_)) -> {
      case run.status {
        run.Done(_, _) | run.Failed(_) -> {
          let status =
            Editing(buffer.Command(Some(buffer.ActionFailed("Execute"))))
          let state = Snippet(..state, status: status)
          #(state, None)
        }
        _ -> run_effects(state)
      }
    }
    MessageFromBuffer(buffer.KeyDown(key)), Editing(buffer.Command(_)) -> {
      let #(proj, mode) =
        buffer.handle_command(
          key,
          proj,
          analysis.within_environment(scope, sync.types(cache)),
          effect_types(effects),
        )
      let editable = projection.rebuild(proj)
      let source = #(proj, editable, None)
      let run = case mode {
        buffer.Command(None) -> run.start(editable, scope, effects, cache)
        _ -> run
      }
      let eff = case mode {
        buffer.Command(_) -> None
        _ ->
          Some(fn(_) {
            window.request_animation_frame(fn(_) {
              case document.query_selector("[autofocus]") {
                Ok(el) -> {
                  dom_element.focus(el)
                  // This can only be done when we move to a new focus
                  // error is something specifically to do with numbers
                  dom_element.set_selection_range(el, 0, -1)
                }
                Error(Nil) -> Nil
              }
            })
            Nil
          })
      }
      let state =
        Snippet(..state, status: Editing(mode), source: source, run: run)
      #(state, eff)
    }
    MessageFromBuffer(buffer.KeyDown(_)), _ ->
      panic as "should never get a buffer message"
    MessageFromBuffer(buffer.JumpTo(path)), _ -> {
      let proj = projection.focus_at(editable, path)
      let source = #(proj, editable, analysis)
      let state =
        Snippet(..state, status: Editing(buffer.Command(None)), source: source)
      #(state, None)
    }
    MessageFromInput(message), Editing(buffer.EditText(value, rebuild)) -> {
      let result = input.update_text(value, message)
      let #(source, run, mode) = case result {
        input.Continue(value) -> #(source, run, buffer.EditText(value, rebuild))
        input.Confirmed(value) -> {
          let proj = rebuild(value)
          let editable = projection.rebuild(proj)
          let source = #(proj, editable, None)
          let run = run.start(editable, scope, effects, cache)
          #(source, run, buffer.Command(None))
        }
        input.Cancelled -> #(source, run, buffer.Command(None))
      }
      let state =
        Snippet(..state, status: Editing(mode), source: source, run: run)
      #(state, focus_away_from_input(mode))
    }
    MessageFromInput(message), Editing(buffer.EditInteger(value, rebuild)) -> {
      let result = input.update_number(value, message)
      let #(source, run, mode) = case result {
        input.Continue(value) -> #(
          source,
          run,
          buffer.EditInteger(value, rebuild),
        )
        input.Confirmed(value) -> {
          let proj = rebuild(value)
          let editable = projection.rebuild(proj)
          let source = #(proj, editable, None)
          let run = run.start(editable, scope, effects, cache)

          #(source, run, buffer.Command(None))
        }
        input.Cancelled -> #(source, run, buffer.Command(None))
      }
      let state =
        Snippet(..state, status: Editing(mode), source: source, run: run)
      #(state, focus_away_from_input(mode))
    }
    MessageFromInput(_), _ -> panic as "shouldn't reach input message"
    MessageFromPicker(picker.Updated(picker)), Editing(buffer.Pick(_, rebuild)) -> {
      let state =
        Snippet(..state, status: Editing(buffer.Pick(picker, rebuild)))
      #(state, None)
    }
    MessageFromPicker(picker.Decided(value)), Editing(buffer.Pick(_, rebuild)) -> {
      let proj = rebuild(value)
      let editable = projection.rebuild(proj)
      let source = #(proj, editable, None)
      let run = run.start(editable, scope, effects, cache)
      let mode = buffer.Command(None)
      let state =
        Snippet(..state, status: Editing(mode), run: run, source: source)
      #(state, focus_away_from_input(mode))
    }
    MessageFromPicker(picker.Dismissed), Editing(buffer.Pick(_, _rebuild)) -> {
      let state = Snippet(..state, status: Editing(buffer.Command(None)))
      #(state, None)
    }
    MessageFromPicker(_), _ -> panic as "shouldn't reach picker message"
    UserClickRunEffects, _ -> run_effects(state)
    RuntimeRepliedFromExternalEffect(reply), Editing(buffer.Command(_)) -> {
      let assert run.Run(run.Handling(label, lift, env, k, _), effect_log) = run

      let effect_log = [#(label, #(lift, reply)), ..effect_log]
      let status = case block.resume(reply, env, k) {
        Ok(#(value, env)) -> run.Done(value, env)
        Error(debug) -> run.handle_extrinsic_effects(debug, effects)
      }
      let run = run.Run(status, effect_log)
      let state = Snippet(..state, run: run)
      case status {
        run.Done(_, _) | run.Failed(_) -> #(state, None)

        run.Handling(_label, lift, env, k, blocking) ->
          case blocking(lift) {
            Ok(promise) -> {
              let run = run.Run(status, effect_log)
              let state = Snippet(..state, run: run)

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
              let state = Snippet(..state, run: run)

              #(state, None)
            }
          }
      }
    }
    RuntimeRepliedFromExternalEffect(_), _ ->
      panic as "should never get a runtime message"
    ClipboardReadCompleted(return), _ -> {
      let assert Editing(buffer.Command(_)) = status
      case return {
        Ok(text) ->
          case decode.from_json(text) {
            Ok(expression) -> {
              let assert #(projection.Exp(_), zoom) = proj
              let proj = #(
                projection.Exp(editable.from_expression(expression)),
                zoom,
              )
              let editable = projection.rebuild(proj)
              let source = #(proj, editable, None)
              let run = run.start(editable, scope, effects, cache)
              let state = Snippet(..state, run: run, source: source)
              #(state, None)
            }
            Error(_) -> {
              let mode = buffer.Command(Some(buffer.ActionFailed("paste")))
              let status = Editing(mode)
              let state = Snippet(..state, status: status)
              #(state, None)
            }
          }

        Error(reason) -> panic as reason
      }
    }
  }
}

fn focus_away_from_input(mode) {
  case mode {
    buffer.Command(_) ->
      Some(fn(_) {
        window.request_animation_frame(fn(_) {
          case document.query_selector("[autofocus]") {
            Ok(el) -> {
              dom_element.focus(el)
            }
            Error(Nil) -> Nil
          }
        })
        Nil
      })
    _ -> None
  }
}

fn run_effects(state) {
  let Snippet(run: run, ..) = state
  let run.Run(status, effect_log) = run
  case status {
    run.Handling(_label, lift, env, k, blocking) -> {
      case blocking(lift) {
        Ok(promise) -> {
          let run = run.Run(status, effect_log)
          let state = Snippet(..state, run: run)

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
          let state = Snippet(..state, run: run)
          #(state, None)
        }
      }
    }
    _ -> #(state, None)
  }
}

pub fn finish_editing(state) {
  Snippet(..state, status: Idle)
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
  let Snippet(status, source, run, scope, effects, cache) = state
  let eff =
    effect_types(effects)
    |> list.fold(t.Empty, fn(acc, new) {
      let #(label, #(lift, reply)) = new
      t.EffectExtend(label, #(lift, reply), acc)
    })
  let a =
    analysis.do_analyse(
      source.1,
      analysis.within_environment(scope, sync.types(cache)),
      eff,
    )
  let proj = source.0
  let errors = analysis.type_errors(a)
  case status {
    Editing(mode) ->
      case mode {
        buffer.Command(e) -> {
          [
            render_projection(proj, True),
            case e {
              Some(failure) ->
                h.div([a.class("border-2 border-orange-4 px-2")], [
                  element.text(fail_message(failure)),
                ])
              None -> render_current(errors, run)
            },
          ]
        }
        buffer.Pick(picker, _rebuild) -> [
          render_projection(proj, False),
          picker.render(picker)
            |> element.map(MessageFromPicker),
        ]

        buffer.EditText(value, _rebuild) -> [
          render_projection(proj, False),
          input.render_text(value)
            |> element.map(MessageFromInput),
        ]

        buffer.EditInteger(value, _rebuild) -> [
          render_projection(proj, False),
          input.render_number(value)
            |> element.map(MessageFromInput),
        ]
      }

    Idle -> [
      h.div(
        [
          a.class("p-2 outline-none my-auto"),
          a.attribute("tabindex", "0"),
          event.on_focus(UserFocusedOnCode),
        ],
        render.statements(source.1),
      ),
      render_current(errors, run),
    ]
  }
}

fn render_current(errors, run: run.Run) {
  case errors {
    [] -> render_run(run.status)
    _ ->
      h.div(
        [a.class("border-2 border-orange-3 px-2")],
        list.map(errors, fn(error) {
          let #(path, reason) = error
          h.div([event.on_click(MessageFromBuffer(buffer.JumpTo(path)))], [
            element.text(debug.reason(reason)),
          ])
        }),
      )
  }
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
      h.pre(
        [
          a.class("border-2 border-green-3 px-2 overflow-auto"),
          a.style([#("max-height", "30vh")]),
        ],
        [
          case value {
            Some(value) -> output.render(value)
            None -> element.none()
          },
          // element.text(value.debug(value)),
        ],
      )
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
// fn handle_dragover(event) {
//   event.prevent_default(event)
//   event.stop_propagation(event)
//   Error([])
// }

// needs to handle dragover otherwise browser will open file
// https://stackoverflow.com/questions/43180248/firefox-ondrop-event-datatransfer-is-null-after-update-to-version-52
// fn handle_drop(event) {
//   event.prevent_default(event)
//   event.stop_propagation(event)
//   let files =
//     drag.data_transfer(dynamicx.unsafe_coerce(event))
//     |> drag.files
//     |> array.to_list()
//   case files {
//     [file] -> {
//       let work =
//         promise.map(file.text(file), fn(content) {
//           let assert Ok(source) = decode.from_json(content)
//           //  going via annotated is inefficient
//           let source = annotated.add_annotation(source, Nil)
//           let source = editable.from_annotated(source)
//           Ok(source)
//         })

//       Ok(state.Loading(work))
//     }
//     _ -> {
//       console.log(#(event, files))
//       Error([])
//     }
//   }
// }
