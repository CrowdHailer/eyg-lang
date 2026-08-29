import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import morph/buffer
import morph/editable as e
import morph/input
import morph/picker
import multiformats/cid/v1
import ogre/origin
import pal/platform/browser as platform
import pal/system
import spotless/oauth_2_1/token
import touch_grass/harness/browser as harness
import touch_grass/interface
import website/command
import website/config
import website/manipulation as m
import website/routes/documentation/state as doc
import website/routes/home/examples

pub type Meta =
  List(Int)

pub type State {
  State(
    mode: doc.Mode,
    examples: Dict(String, buffer.Buffer),
    origin: origin.Origin,
    cache: cache.Cache(Meta),
    counter: Int,
    // spotless_origin: origin.Origin,
    tokens: Dict(harness.Service, String),
  )
}

pub fn init(config) {
  let config.Config(origin:) = config
  let #(examples, cache) = doc.init_collection(examples.all(), cache.ready())
  let #(cache, effects) = flush_cache(cache, origin)
  let state =
    State(
      mode: doc.UnFocused,
      examples:,
      origin:,
      cache:,
      counter: 0,
      // spotless_origin: origin.https("spotless.run"),
      tokens: dict.new(),
    )
  #(state, effects)
}

// Dont abstact as is useful because it uses the specific page State
pub fn get_example(state: State, id) {
  let assert Ok(buffer) = dict.get(state.examples, id)
  buffer
}

pub fn set_example(state: State, id, buffer) {
  State(..state, examples: dict.insert(state.examples, id, buffer))
}

fn continue(
  state: State,
  id: String,
  gen: fn(infer.Context, dict.Dict(v1.Cid, binding.Poly)) -> buffer.Buffer,
) -> #(State, List(system.Effect(Message))) {
  let State(cache:, origin:, ..) = state
  let buffer =
    gen(
      infer.pure() |> infer.with_effects(interface.types(harness.effects())),
      cache.types(state.cache),
    )
  let state = set_example(state, id, buffer)
  let cache = cache.prepare(cache, buffer.source(buffer))
  let #(cache, effects) = flush_cache(cache, origin)
  let state = State(..state, mode: doc.Navigating(id:, failure: None), cache:)
  #(state, effects)
}

pub type Message {
  UserClickedCode(id: String, path: List(Int))
  UserPressedKey(key: String)
  InputMessage(input.Message)
  PickerMessage(picker.Message)

  ClipboardReadCompleted(Result(String, String))
  Ignore
  EffectHandled(task_id: Int, value: state.Value(Meta))
  SpotlessConnectCompleted(task_id: Int, result: Result(token.Response, String))
  CacheMessage(cache.ActionCompleted)
}

pub fn update(state: State, message) {
  let State(mode:, ..) = state
  case message, mode {
    UserClickedCode(id:, path:), _ -> {
      let buffer = get_example(state, id)
      let buffer = buffer.focus_at(buffer, path) |> result.unwrap(buffer)
      let state = set_example(state, id, buffer)
      let state = State(..state, mode: doc.Navigating(id:, failure: None))
      #(state, [])
    }
    UserPressedKey(key:), doc.Navigating(id, _)
    | UserPressedKey(key:), doc.Running(id, doc.Successful(_))
    | UserPressedKey(key:), doc.Running(id, doc.Aborted(_))
    | UserPressedKey(key:), doc.Running(id, doc.Exception(_))
    ->
      // don't wrap this up in shared behaviour taking (context, buffer) as the top level key commands will change
      user_pressed_key(state, id, key)
    UserPressedKey(_), _ -> #(state, [])
    InputMessage(message), doc.Manipulating(id, m.EnterInteger(value, rebuild))
    ->
      case input.update_number(value, message) {
        input.Continue(new) -> {
          let mode = doc.Manipulating(id, m.EnterInteger(new, rebuild))
          let state = State(..state, mode:)
          #(state, [])
        }
        input.Confirmed(value) ->
          continue(state, id, fn(context, refs) {
            rebuild(value, context, refs)
          })
        input.Cancelled -> {
          let state = State(..state, mode: doc.Navigating(id:, failure: None))
          #(state, [])
        }
      }
    InputMessage(message), doc.Manipulating(id, m.EnterText(value, rebuild)) ->
      case input.update_text(value, message) {
        input.Continue(new) -> {
          let mode = doc.Manipulating(id, m.EnterText(new, rebuild))
          let state = State(..state, mode:)
          #(state, [])
        }
        input.Confirmed(value) ->
          continue(state, id, fn(context, refs) {
            rebuild(value, context, refs)
          })
        input.Cancelled -> {
          let state = State(..state, mode: doc.Navigating(id:, failure: None))
          #(state, [])
        }
      }

    InputMessage(_), _ -> #(state, [])
    PickerMessage(message), doc.Manipulating(id, m.PickSingle(_picker, rebuild))
    ->
      case message {
        picker.Updated(picker:) -> {
          let mode = doc.Manipulating(id, m.PickSingle(picker, rebuild))
          #(State(..state, mode:), [])
        }
        picker.Decided(label) ->
          continue(state, id, fn(context, refs) {
            rebuild(label, context, refs)
          })
        picker.Dismissed -> #(
          State(..state, mode: doc.Navigating(id:, failure: None)),
          [],
        )
      }
    PickerMessage(message), doc.Manipulating(id, m.PickCid(_picker, rebuild)) ->
      case message {
        picker.Updated(picker:) -> {
          let mode = doc.Manipulating(id, m.PickCid(picker, rebuild))
          #(State(..state, mode:), [])
        }
        picker.Decided(text) -> {
          case v1.from_string(text) {
            Ok(#(cid, _)) ->
              continue(state, id, fn(context, refs) {
                rebuild(cid, context, refs)
              })
            Error(_) -> {
              echo "need error message for bad cid"
              #(state, [])
            }
          }
        }
        picker.Dismissed -> #(
          State(..state, mode: doc.Navigating(id:, failure: None)),
          [],
        )
      }
    PickerMessage(message),
      doc.Manipulating(id, m.PickRelease(_picker, rebuild))
    ->
      case message {
        picker.Updated(picker:) -> {
          let mode = doc.Manipulating(id, m.PickRelease(picker, rebuild))
          #(State(..state, mode:), [])
        }
        picker.Decided(text) -> {
          case cache.package(state.cache, text) {
            Ok(cache.Entry(version:, module:, ..)) ->
              continue(state, id, fn(context, refs) {
                rebuild(ir.Release(text, version, module), context, refs)
              })
            Error(_) -> {
              echo "need error message for bad cid"
              #(state, [])
            }
          }
        }
        picker.Dismissed -> #(
          State(..state, mode: doc.Navigating(id:, failure: None)),
          [],
        )
      }
    PickerMessage(_), _ -> #(state, [])
    ClipboardReadCompleted(return), doc.ReadingFromClipboard(id, rebuild) ->
      case return {
        Ok(text) ->
          case json.parse(text, dag_json.decoder(Nil)) {
            Ok(expression) ->
              continue(state, id, fn(context, refs) {
                rebuild(e.from_annotated(expression), context, refs)
              })
            Error(_) -> action_failed(state, id, "paste")
          }
        Error(_) -> action_failed(state, id, "paste")
      }
    ClipboardReadCompleted(_), _ -> #(state, [])
    Ignore, _ -> #(state, [])
    EffectHandled(task_id: tid, value:),
      doc.Running(id:, run: doc.Handling(task_id:, work: doc.Effect, env:, k:))
      if tid == task_id
    -> {
      let #(run, counter, effect) =
        expression.resume(value, env, k)
        |> loop(state)
      let mode = doc.Running(id, run)
      #(State(..state, mode:, counter:), case effect {
        Some(effect) -> [effect]
        None -> []
      })
    }
    EffectHandled(_, _), _ -> #(state, [])
    SpotlessConnectCompleted(task_id: tid, result:), mode ->
      case mode {
        doc.Running(
          id:,
          run: doc.Handling(
            task_id:,
            work: doc.Connect(service:, operation:),
            env:,
            k:,
          ),
        )
          if tid == task_id
        ->
          case result {
            Ok(token) -> {
              let request =
                doc.service_request(
                  service,
                  operation,
                  token.access_token,
                  state.origin,
                )
              let effect = platform.fetch(request)
              // TODO manage the 400 error case
              let effect = system.map(effect, EffectHandled(task_id, _))
              let run = doc.Handling(task_id, doc.Effect, env, k)

              let mode = doc.Running(id, run)
              #(State(..state, mode:), [effect])
            }
            Error(reason) -> {
              let run = doc.Aborted("failed to authorize: " <> reason)
              let mode = doc.Running(id, run)
              #(State(..state, mode:), [])
            }
          }
        _ -> #(state, [])
      }
    CacheMessage(message), _ -> {
      let #(cache, done) = cache.update(state.cache, message, fn(_) { [] })
      let examples = doc.reanalyse_examples(state.examples, done, cache)
      let #(cache, effects) = flush_cache(cache, state.origin)
      let state = State(..state, examples:, cache:)
      case state.mode {
        doc.Running(id, run) -> {
          let #(run, counter, effect) = restart(run, state)
          let mode = doc.Running(id, run)
          let state = State(..state, counter:, mode:)
          let effects = case effect {
            Some(effect) -> [effect, ..effects]
            None -> effects
          }
          #(state, effects)
        }
        _ -> #(state, effects)
      }
    }
  }
}

fn user_pressed_key(state, id, key) {
  case key {
    "Escape" -> #(State(..state, mode: doc.UnFocused), [])
    "ArrowRight" -> navigate(state, "move right", buffer.next)
    "ArrowLeft" -> navigate(state, "move left", buffer.previous)
    "ArrowUp" -> navigate(state, "move up", buffer.up)
    "ArrowDown" -> navigate(state, "move down", buffer.down)
    // "Q" -> link_filesystem(state)  Not supported in documentation
    // "q" -> choose_module(state) Not supported in documentation
    "w" -> edit(state, m.call_with())
    "E" -> edit(state, m.assign_before())
    "e" -> edit(state, m.assign())
    "R" -> edit(state, m.create_empty_record())
    "r" -> edit(state, m.create_record())
    "t" -> edit(state, m.insert_tag())
    "y" -> copy(state)
    "Y" -> paste(state)
    // // TODO mode is authenticating
    // // you won't see much on the front page
    // "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
    //   OpenPopup("/sign"),
    // ])
    "i" -> edit(state, m.insert())
    "o" -> edit(state, m.overwrite())
    "p" -> edit(state, m.perform())
    "a" -> navigate(state, "increase selection", buffer.increase)
    "s" -> edit(state, m.insert_string())
    "d" -> edit(state, m.delete())
    "f" -> edit(state, m.insert_function())
    "g" -> edit(state, m.select_field())
    "h" -> edit(state, m.insert_handle())
    "j" -> edit(state, m.insert_builtin())
    "k" -> navigate(state, "toggle", buffer.toggle_open)
    "L" -> edit(state, m.create_empty_list())
    "l" -> edit(state, m.create_list())
    "@" -> edit(state, m.choose_release(state.cache))
    "#" -> edit(state, m.insert_reference())
    "Z" -> edit(state, m.redo())
    "z" -> edit(state, m.undo())
    "x" -> edit(state, m.spread())
    "c" -> edit(state, m.call_function())
    "C" -> edit(state, m.call_once())
    "b" -> edit(state, m.insert_binary())
    "n" -> edit(state, m.insert_integer())
    "m" -> edit(state, m.insert_case())
    "v" -> edit(state, m.insert_variable())
    "<" -> edit(state, m.insert_before())
    ">" -> edit(state, m.insert_after())
    "Enter" -> confirm(state)
    " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    _ -> {
      let mode = doc.Navigating(id, Some(command.NoKeyBinding(key)))
      #(State(..state, mode:), [])
    }
  }
}

fn navigate(state: State, name, func) {
  use id, buffer <- is_editing(state)

  case func(buffer) {
    Ok(buffer) -> {
      let state = set_example(state, id, buffer)
      let state = State(..state, mode: doc.Navigating(id:, failure: None))
      #(state, [])
    }
    Error(_reason) -> action_failed(state, id, name)
  }
}

// can't 1 for 1 map over a working state for the buffer because of the gen -> buffer step in resolved
fn edit(state, manipulation) {
  use id, buffer <- is_editing(state)
  let m.Operation(name:, apply:) = manipulation
  case apply(buffer) {
    Ok(m.Resolved(gen)) -> continue(state, id, gen)
    Ok(m.UserInput(input)) -> {
      #(State(..state, mode: doc.Manipulating(id, input)), [])
    }
    Error(Nil) -> action_failed(state, id, name)
  }
}

/// don't do key press under a mode switch
fn copy(state: State) {
  use id, buffer <- is_editing(state)
  case buffer.copy_source(buffer) {
    Ok(text) -> #(state, [
      system.WriteToClipboard(text:, resume: fn(_) { system.Done(Ignore) }),
    ])
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn paste(state: State) {
  use id, buffer <- is_editing(state)
  case buffer.set_expression(buffer) {
    Ok(rebuild) -> {
      let state = State(..state, mode: doc.ReadingFromClipboard(id:, rebuild:))
      #(state, [
        system.ReadFromClipboard(fn(result) {
          system.Done(ClipboardReadCompleted(result))
        }),
      ])
    }
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn confirm(state: State) {
  use id, buffer <- is_editing(state)
  let source = buffer.source(buffer)
  let cache = cache.prepare(state.cache, source)
  let #(run, counter, effect) =
    expression.execute(source, [])
    |> loop(state)
  let mode = doc.Running(id, run)
  let effects = case effect {
    Some(effect) -> [effect]
    None -> []
  }
  #(State(..state, cache:, mode:, counter:), effects)
}

/// is_editing or concluded
fn is_editing(state: State, then) {
  case state.mode {
    doc.Navigating(id:, failure: _) -> then(id, get_example(state, id))
    doc.Running(id:, ..) -> then(id, get_example(state, id))
    _ -> #(state, [])
  }
}

fn action_failed(state, id, name) {
  let state =
    State(
      ..state,
      mode: doc.Navigating(id:, failure: Some(command.ActionFailed(name))),
    )
  #(state, [])
}

fn flush_cache(cache, origin) {
  let #(cache, effects) = cache.flush(cache)
  let effects =
    list.map(effects, fn(effect) {
      cache.compute(effect, origin, system.fetch)(fn(return) {
        system.Done(CacheMessage(return))
      })
    })
  #(cache, effects)
}

pub fn loop(
  return: Result(state.Value(Meta), state.Debug(Meta)),
  state: State,
) -> #(doc.Run, Int, Option(system.Effect(Message))) {
  case return {
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      case platform.cast(label, lift) {
        Ok(effect) -> {
          case platform.extrinsic(effect) {
            platform.Work(system.Done(value)) -> loop(Ok(value), state)
            platform.Work(effect) -> {
              let counter = state.counter
              let effect = system.map(effect, EffectHandled(counter, _))
              let run = doc.Handling(counter, doc.Effect, env, k)
              #(run, counter + 1, Some(effect))
            }
            platform.Abort(reason) -> #(
              doc.Aborted(reason),
              state.counter,
              None,
            )
            platform.Spotless(service:, operation:) ->
              // This could be called vault.proxy as a stateful entity it would take an ID or something.
              case dict.get(state.tokens, service) {
                Ok(token) -> {
                  let request =
                    doc.service_request(service, operation, token, state.origin)
                  let effect = platform.fetch(request)
                  // TODO manage the 400 error case
                  let counter = state.counter
                  let effect = system.map(effect, EffectHandled(counter, _))
                  let run = doc.Handling(counter, doc.Effect, env, k)
                  #(run, counter + 1, Some(effect))
                }
                // No memory of connecting because there's only one
                // Connecting/Proxying is a state in run 
                Error(Nil) -> {
                  let work = doc.Connect(service:, operation:)
                  let run = doc.Handling(state.counter, work, env, k)
                  let effect =
                    system.Spotless(
                      service:,
                      origin: state.origin,
                      resume: fn(result) {
                        system.Done(SpotlessConnectCompleted(
                          state.counter,
                          result,
                        ))
                      },
                    )
                  #(run, state.counter + 1, Some(effect))
                }
              }
          }
        }
        Error(reason) -> #(doc.Exception(reason), state.counter, None)
      }
    }
    Error(#(break.UndefinedReference(ir.Content(cid)), _, env, k)) ->
      case cache.get_module(state.cache, cid) {
        Ok(cache.Module(value:, ..)) ->
          loop(expression.resume(value, env, k), state)
        // All dependencies are marked as blocked the view shows error vs running status
        Error(_) -> {
          let run = doc.Blocked(cache.Content(cid), env, k)
          #(run, state.counter, None)
        }
      }
    Error(#(break.UndefinedReference(ir.Pinned(release)), _, env, k)) -> {
      case cache.release_code(state.cache, release) {
        Ok(cache.Module(value:, ..)) ->
          loop(expression.resume(value, env, k), state)
        _ -> {
          let run = doc.Blocked(cache.Pinned(release), env, k)
          #(run, state.counter, None)
        }
      }
    }
    Ok(value) -> #(doc.Successful(value), state.counter, None)
    Error(#(reason, _, _, _)) -> #(doc.Exception(reason), state.counter, None)
  }
}

pub fn restart(
  run: doc.Run,
  state: State,
) -> #(doc.Run, Int, Option(system.Effect(Message))) {
  case run {
    doc.Blocked(dep:, env:, k:) -> {
      let reason = cache.dep_to_reason(dep)
      let return = Error(#(reason, [], env, k))
      loop(return, state)
    }
    _ -> #(run, state.counter, None)
  }
}
