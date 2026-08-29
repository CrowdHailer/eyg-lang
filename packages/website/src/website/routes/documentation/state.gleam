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
import morph/navigation
import morph/picker
import multiformats/cid/v1
import ogre/operation
import ogre/origin
import pal/platform/browser as platform
import pal/system
import spotless/oauth_2_1/token
import touch_grass/harness/browser as harness
import touch_grass/interface
import website/command
import website/config
import website/manipulation as m
import website/routes/documentation/examples

pub type State {
  State(
    mode: Mode,
    examples: Dict(String, buffer.Buffer),
    // hub and current page origin.
    origin: origin.Origin,
    cache: cache.Cache(Meta),
    counter: Int,
    // spotless_origin: origin.Origin,
    tokens: Dict(harness.Service, String),
  )
}

pub type Rebuild(t) =
  fn(t, infer.Context, dict.Dict(v1.Cid, binding.Poly)) -> buffer.Buffer

pub type Mode {
  Navigating(id: String, failure: Option(command.Failure))
  Manipulating(id: String, input: m.UserInput)
  ReadingFromClipboard(id: String, rebuild: Rebuild(e.Expression))
  Running(id: String, run: Run)
  UnFocused
}

pub type Run {
  Successful(state.Value(Meta))
  Exception(state.Reason(Meta))
  Aborted(String)
  Handling(task_id: Int, work: Work, env: state.Env(Meta), k: state.Stack(Meta))
  Blocked(dep: cache.Dependency, env: state.Env(Meta), k: state.Stack(Meta))
}

pub type Work {
  Effect
  Connect(service: harness.Service, operation: operation.Operation(BitArray))
}

pub type Return =
  Result(state.Value(Meta), state.Debug(Meta))

pub type Meta =
  List(Int)

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

pub fn get_example(state: State, id) {
  let assert Ok(snippet) = dict.get(state.examples, id)
  snippet
}

pub fn set_example(state: State, id, snippet) {
  State(..state, examples: dict.insert(state.examples, id, snippet))
}

fn continue(
  state: State,
  id: String,
  gen: fn(infer.Context, dict.Dict(v1.Cid, binding.Poly)) -> buffer.Buffer,
) -> #(State, List(system.Effect(Message))) {
  let State(cache:, ..) = state
  let buffer =
    gen(
      infer.pure() |> infer.with_effects(interface.types(harness.effects())),
      cache.types(state.cache),
    )
  let state = set_example(state, id, buffer)
  let cache = cache.prepare(cache, buffer.source(buffer))
  let #(cache, effects) = flush_cache(cache, state.origin)
  let state = State(..state, mode: Navigating(id:, failure: None), cache:)
  #(state, effects)
}

// snippet failure goes at top level
pub fn init(config: config.Config) -> #(State, List(system.Effect(Message))) {
  let config.Config(origin:) = config
  let #(examples, cache) = init_collection(examples.all(), cache.ready())
  let #(cache, effects) = flush_cache(cache, origin)
  let state =
    State(
      mode: UnFocused,
      examples:,
      origin:,
      cache:,
      counter: 0,
      // spotless_origin: origin.https("spotless.run"),
      tokens: dict.new(),
    )
  #(state, effects)
}

pub fn flush_cache(cache, origin) {
  let #(cache, effects) = cache.flush(cache)
  let effects =
    list.map(effects, fn(effect) {
      cache.compute(effect, origin, system.fetch)(fn(return) {
        system.Done(CacheMessage(return))
      })
    })
  #(cache, effects)
}

pub fn init_collection(
  sources: List(#(a, e.Expression)),
  cache: cache.Cache(Meta),
) -> #(Dict(a, buffer.Buffer), cache.Cache(Meta)) {
  let examples =
    list.map(sources, fn(example) {
      let #(key, editable) = example
      let editable = e.open_all(editable)
      let buffer = buffer(editable, cache)
      #(key, buffer)
    })
  let missing_references =
    list.flat_map(examples, fn(example) {
      let #(_key, buffer) = example
      infer.missing_references(buffer.analysis)
    })
  let missing_cids =
    list.filter_map(missing_references, fn(ref) {
      case ref {
        ir.Content(cid) -> Ok(cid)
        _ -> Error(Nil)
      }
    })
  let examples = dict.from_list(examples)

  let cache = cache.fetch_all(cache, missing_cids)
  #(examples, cache)
}

fn buffer(editable: e.Expression, cache: cache.Cache(Meta)) -> buffer.Buffer {
  let projection = navigation.first(editable)
  // keep evaluation on example, if it runs don't print type errors. but show them in the code
  buffer.from_projection(
    projection,
    infer.pure() |> infer.with_effects(interface.types(harness.effects())),
    cache.types(cache),
  )
}

pub fn update(state: State, message) {
  case message {
    UserClickedCode(id:, path:) -> {
      let buffer = get_example(state, id)
      let buffer = buffer.focus_at(buffer, path) |> result.unwrap(buffer)
      let state = set_example(state, id, buffer)
      let state = State(..state, mode: Navigating(id:, failure: None))
      #(state, [])
    }
    UserPressedKey(key:) -> user_pressed_key(state, key)
    InputMessage(message) -> {
      let State(mode:, ..) = state
      case mode {
        Manipulating(id, m.EnterInteger(value, rebuild)) ->
          case input.update_number(value, message) {
            input.Continue(new) -> {
              let mode = Manipulating(id, m.EnterInteger(new, rebuild))
              let state = State(..state, mode:)
              #(state, [])
            }
            input.Confirmed(value) ->
              continue(state, id, fn(context, refs) {
                rebuild(value, context, refs)
              })
            input.Cancelled -> {
              let state = State(..state, mode: Navigating(id:, failure: None))
              #(state, [])
            }
          }
        Manipulating(id, m.EnterText(value, rebuild)) ->
          case input.update_text(value, message) {
            input.Continue(new) -> {
              let mode = Manipulating(id, m.EnterText(new, rebuild))
              let state = State(..state, mode:)
              #(state, [])
            }
            input.Confirmed(value) ->
              continue(state, id, fn(context, refs) {
                rebuild(value, context, refs)
              })
            input.Cancelled -> {
              let state = State(..state, mode: Navigating(id:, failure: None))
              #(state, [])
            }
          }
        _ -> #(state, [])
      }
    }
    PickerMessage(message) -> {
      let State(mode:, ..) = state
      case mode {
        Manipulating(id, m.PickSingle(_picker, rebuild)) ->
          case message {
            picker.Updated(picker:) -> {
              let mode = Manipulating(id, m.PickSingle(picker, rebuild))
              #(State(..state, mode:), [])
            }
            picker.Decided(label) ->
              continue(state, id, fn(context, refs) {
                rebuild(label, context, refs)
              })
            picker.Dismissed -> #(
              State(..state, mode: Navigating(id:, failure: None)),
              [],
            )
          }
        Manipulating(id, m.PickCid(_picker, rebuild)) ->
          case message {
            picker.Updated(picker:) -> {
              let mode = Manipulating(id, m.PickCid(picker, rebuild))
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
              State(..state, mode: Navigating(id:, failure: None)),
              [],
            )
          }

        Manipulating(id, m.PickRelease(_picker, rebuild)) ->
          case message {
            picker.Updated(picker:) -> {
              let mode = Manipulating(id, m.PickRelease(picker, rebuild))
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
              State(..state, mode: Navigating(id:, failure: None)),
              [],
            )
          }
        _ -> #(state, [])
      }
    }

    ClipboardReadCompleted(return) -> {
      case state.mode {
        ReadingFromClipboard(id, rebuild) ->
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
        _ -> #(state, [])
      }
    }

    Ignore -> #(state, [])
    EffectHandled(task_id: tid, value:) ->
      case state.mode {
        Running(id:, run: Handling(task_id:, work: Effect, env:, k:))
          if tid == task_id
        -> {
          let #(run, counter, effect) =
            expression.resume(value, env, k)
            |> loop(state)
          let mode = Running(id, run)
          #(State(..state, mode:, counter:), case effect {
            Some(effect) -> [effect]
            None -> []
          })
        }
        _ -> #(state, [])
      }
    SpotlessConnectCompleted(task_id: tid, result:) ->
      case state.mode {
        Running(
          id:,
          run: Handling(task_id:, work: Connect(service:, operation:), env:, k:),
        )
          if tid == task_id
        -> {
          case result {
            Ok(token) -> {
              let request =
                service_request(
                  service,
                  operation,
                  token.access_token,
                  state.origin,
                )
              let effect = platform.fetch(request)
              // TODO manage the 400 error case
              let effect = system.map(effect, EffectHandled(task_id, _))
              let run = Handling(task_id, Effect, env, k)

              let mode = Running(id, run)
              #(State(..state, mode:), [effect])
            }
            Error(reason) -> {
              let run = Aborted("failed to authorize: " <> reason)
              let mode = Running(id, run)
              #(State(..state, mode:), [])
            }
          }
        }
        _ -> #(state, [])
      }
    CacheMessage(message) -> {
      let #(cache, done) = cache.update(state.cache, message, fn(_) { [] })
      let examples = reanalyse_examples(state.examples, done, cache)
      let #(cache, effects) = flush_cache(cache, state.origin)
      let state = State(..state, examples:, cache:)
      case state.mode {
        Running(id, run) -> {
          let #(run, counter, effect) = restart(run, state)
          let mode = Running(id, run)
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

pub fn reanalyse_examples(
  examples: dict.Dict(String, buffer.Buffer),
  _done: List(#(v1.Cid, Result(a, b))),
  cache: cache.Cache(Meta),
) -> Dict(String, buffer.Buffer) {
  // reanalyse everything
  // filtering for just cid's doesn't catch the missing releases that should be reevaluated
  // let ok =
  //   list.filter_map(done, fn(result) {
  //     let #(cid, result) = result
  //     case result {
  //       Ok(_value) -> Ok(cid)
  //       Error(_) -> Error(Nil)
  //     }
  //   })

  dict.map_values(examples, fn(_k, buffer) {
    let update = !list.is_empty(infer.all_errors(buffer.analysis))
    // list.any(ok, list.contains(infer.missing_references(buffer.analysis), _))
    case update {
      True ->
        buffer.reanalyse(
          buffer,
          infer.pure()
            |> infer.with_effects(interface.types(harness.effects())),
          cache.types(cache),
        )
      False -> buffer
    }
  })
}

fn user_pressed_key(state, key) {
  let State(mode:, ..) = state
  case mode, key {
    _, "Escape" -> #(State(..state, mode: UnFocused), [])
    _, "ArrowRight" -> navigate(state, "move right", buffer.next)
    _, "ArrowLeft" -> navigate(state, "move left", buffer.previous)
    _, "ArrowUp" -> navigate(state, "move up", buffer.up)
    _, "ArrowDown" -> navigate(state, "move down", buffer.down)
    // _, "Q" -> link_filesystem(state)  Not supported in documentation
    // _, "q" -> choose_module(state) Not supported in documentation
    _, "w" -> edit(state, m.call_with())
    _, "E" -> edit(state, m.assign_before())
    _, "e" -> edit(state, m.assign())
    _, "R" -> edit(state, m.create_empty_record())
    _, "r" -> edit(state, m.create_record())
    _, "t" -> edit(state, m.insert_tag())
    _, "y" -> copy(state)
    _, "Y" -> paste(state)

    // // you won't see much on the front page
    // "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
    //   OpenPopup("/sign"),
    // ])
    _, "i" -> edit(state, m.insert())
    _, "o" -> edit(state, m.overwrite())
    _, "p" -> edit(state, m.perform())
    _, "a" -> navigate(state, "increase selection", buffer.increase)
    _, "s" -> edit(state, m.insert_string())
    _, "d" -> edit(state, m.delete())
    _, "f" -> edit(state, m.insert_function())
    _, "g" -> edit(state, m.select_field())
    _, "h" -> edit(state, m.insert_handle())
    _, "j" -> edit(state, m.insert_builtin())
    _, "k" -> navigate(state, "toggle", buffer.toggle_open)
    _, "L" -> edit(state, m.create_empty_list())
    _, "l" -> edit(state, m.create_list())
    _, "@" -> edit(state, m.choose_release(state.cache))
    _, "#" -> edit(state, m.insert_reference())
    _, "Z" -> edit(state, m.redo())
    _, "z" -> edit(state, m.undo())
    _, "x" -> edit(state, m.spread())
    _, "c" -> edit(state, m.call_function())
    _, "C" -> edit(state, m.call_once())
    _, "b" -> edit(state, m.insert_binary())
    _, "n" -> edit(state, m.insert_integer())
    _, "m" -> edit(state, m.insert_case())
    _, "v" -> edit(state, m.insert_variable())
    _, "<" -> edit(state, m.insert_before())
    _, ">" -> edit(state, m.insert_after())
    _, "Enter" -> confirm(state)
    _, " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    Navigating(id, _error), _ -> {
      let mode = Navigating(id, Some(command.NoKeyBinding(key)))
      #(State(..state, mode:), [])
    }
    UnFocused, _ -> #(state, [])
    ReadingFromClipboard(id: _, rebuild: _), _ -> #(state, [])
    Running(..), _ -> #(state, [])
    Manipulating(id: _, input: _), _ -> #(state, [])
  }
}

fn navigate(state: State, name, func) {
  use id, buffer <- is_editing(state)

  case func(buffer) {
    Ok(buffer) -> {
      let state = set_example(state, id, buffer)
      let state = State(..state, mode: Navigating(id:, failure: None))
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
      #(State(..state, mode: Manipulating(id, input)), [])
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
      let state = State(..state, mode: ReadingFromClipboard(id:, rebuild:))
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
  let mode = Running(id, run)
  let effects = case effect {
    Some(effect) -> [effect]
    None -> []
  }
  #(State(..state, cache:, mode:, counter:), effects)
}

fn is_editing(state: State, then) {
  case state.mode {
    Navigating(id:, failure: _) -> then(id, get_example(state, id))
    _ -> #(state, [])
  }
}

fn action_failed(state, id, name) {
  let state =
    State(
      ..state,
      mode: Navigating(id:, failure: Some(command.ActionFailed(name))),
    )
  #(state, [])
}

// This loop assumes values have been looked for.
// Used on the homepage as well.
pub fn loop(
  return: Result(state.Value(Meta), state.Debug(Meta)),
  state: State,
) -> #(Run, Int, Option(system.Effect(Message))) {
  case return {
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      case platform.cast(label, lift) {
        Ok(effect) -> {
          case platform.extrinsic(effect) {
            platform.Work(system.Done(value)) -> loop(Ok(value), state)
            platform.Work(effect) -> {
              let counter = state.counter
              let effect = system.map(effect, EffectHandled(counter, _))
              let run = Handling(counter, Effect, env, k)
              #(run, counter + 1, Some(effect))
            }
            platform.Abort(reason) -> #(Aborted(reason), state.counter, None)
            platform.Spotless(service:, operation:) ->
              // This could be called vault.proxy as a stateful entity it would take an ID or something.
              case dict.get(state.tokens, service) {
                Ok(token) -> {
                  let request =
                    service_request(service, operation, token, state.origin)
                  let effect = platform.fetch(request)
                  // TODO manage the 400 error case
                  let counter = state.counter
                  let effect = system.map(effect, EffectHandled(counter, _))
                  let run = Handling(counter, Effect, env, k)
                  #(run, counter + 1, Some(effect))
                }
                // No memory of connecting because there's only one
                // Connecting/Proxying is a state in run 
                Error(Nil) -> {
                  let work = Connect(service:, operation:)
                  let run = Handling(state.counter, work, env, k)
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
        Error(reason) -> #(Exception(reason), state.counter, None)
      }
    }
    Error(#(break.UndefinedReference(ir.Content(cid)), _, env, k)) ->
      case cache.get_module(state.cache, cid) {
        Ok(cache.Module(value:, ..)) ->
          loop(expression.resume(value, env, k), state)
        // All dependencies are marked as blocked the view shows error vs running status
        Error(_) -> {
          let run = Blocked(cache.Content(cid), env, k)
          #(run, state.counter, None)
        }
      }
    Error(#(break.UndefinedReference(ir.Pinned(release)), _, env, k)) -> {
      case cache.release_code(state.cache, release) {
        Ok(cache.Module(value:, ..)) ->
          loop(expression.resume(value, env, k), state)
        _ -> {
          let run = Blocked(cache.Pinned(release), env, k)
          #(run, state.counter, None)
        }
      }
    }
    Ok(value) -> #(Successful(value), state.counter, None)
    Error(#(reason, _, _, _)) -> #(Exception(reason), state.counter, None)
  }
}

pub fn restart(
  run: Run,
  state: State,
) -> #(Run, Int, Option(system.Effect(Message))) {
  case run {
    Blocked(dep:, env:, k:) -> {
      let reason = cache.dep_to_reason(dep)
      let return = Error(#(reason, [], env, k))
      loop(return, state)
    }
    _ -> #(run, state.counter, None)
  }
}

// TODO move to vault
pub fn service_request(service, operation, token, hub_origin) {
  case service {
    harness.DNSimple ->
      operation
      |> operation.prefix_path("/proxy/dnsimple")
      |> operation.set_header("authorization", "Bearer " <> token)
      |> operation.to_request(hub_origin)
    harness.GitHub ->
      operation
      |> operation.set_header("authorization", "Bearer " <> token)
      |> operation.to_request(origin.https("api.github.com"))

    harness.Vimeo ->
      operation
      |> operation.set_header("authorization", "Bearer " <> token)
      |> operation.to_request(origin.https("api.vimeo.com"))
  }
}
