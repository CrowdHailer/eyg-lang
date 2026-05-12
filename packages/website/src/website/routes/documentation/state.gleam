import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/hub/publisher
import eyg/hub/release
import eyg/hub/schema
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
import spotless/oauth_2_1/token
import website/command
import website/config
import website/harness/browser
import website/harness/harness
import website/manipulation as m
import website/routes/documentation/examples
import website/run

pub type State {
  State(
    mode: Mode,
    examples: Dict(String, buffer.Buffer),
    context: run.Context(Message),
  )
}

pub type Rebuild(t) =
  fn(t, infer.Context) -> buffer.Buffer

pub type Mode {
  Navigating(id: String, failure: Option(command.Failure))
  Manipulating(id: String, input: m.UserInput)
  ReadingFromClipboard(id: String, rebuild: Rebuild(e.Expression))
  Running(id: String, status: run.Run(state.Value(Meta)))
  UnFocused
}

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
  SpotlessConnectCompleted(harness.Service, Result(token.Response, String))
  ModuleLookupCompleted(v1.Cid, Result(ir.Node(Nil), String))
  PullPackagesCompleted(Result(List(schema.ArchivedEntry), String))
}

pub fn get_example(state: State, id) {
  let assert Ok(snippet) = dict.get(state.examples, id)
  snippet
}

pub fn set_example(state: State, id, snippet) {
  State(..state, examples: dict.insert(state.examples, id, snippet))
}

fn continue(state, id, gen) {
  let State(context:, ..) = state
  let buffer = gen(infer_context(context))
  let state = set_example(state, id, buffer)
  let missing_references = infer.missing_references(buffer.analysis)
  let context = run.fetch_all(missing_references, context)
  let #(context, effects) = run.flush(context)
  let state = State(..state, mode: Navigating(id:, failure: None), context:)
  #(state, effects)
}

// snippet failure goes at top level
pub fn init(config) {
  let config.Config(origin:) = config
  let #(examples, context) = init_collection(examples.all(), context(origin))
  let #(context, effects) = run.flush(context)
  let state = State(UnFocused, examples, context)
  #(state, effects)
}

pub fn init_collection(sources, context) {
  let examples =
    list.map(sources, fn(example) {
      let #(key, editable) = example
      let editable = e.open_all(editable)
      let buffer = buffer(editable, context)
      #(key, buffer)
    })
  let missing_references =
    list.flat_map(examples, fn(example) {
      let #(_key, buffer) = example
      infer.missing_references(buffer.analysis)
    })
  let examples = dict.from_list(examples)
  let context = run.fetch_all(missing_references, context)
  #(examples, context)
}

pub fn context(hub_origin) {
  run.empty(
    hub_origin,
    EffectHandled,
    SpotlessConnectCompleted,
    ModuleLookupCompleted,
    PullPackagesCompleted,
  )
  |> run.pull()
}

fn buffer(editable, context) {
  let projection = navigation.first(editable)
  // keep evaluation on example, if it runs don't print type errors. but show them in the code
  buffer.from_projection(projection, infer_context(context))
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
            input.Confirmed(value) -> continue(state, id, rebuild(value, _))
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
            input.Confirmed(value) -> continue(state, id, rebuild(value, _))
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
            picker.Decided(label) -> continue(state, id, rebuild(label, _))
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
                Ok(#(cid, _)) -> continue(state, id, rebuild(cid, _))
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
              case cache.package(state.context.cache, text) {
                Ok(#(v, m)) -> continue(state, id, rebuild(#(text, v, m), _))
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
                  continue(state, id, rebuild(e.from_annotated(expression), _))
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
        Running(id:, status: run.Handling(task_id:, env:, k:))
          if tid == task_id
        -> {
          let #(mode, context, effects) =
            expression.resume(value, env, k)
            |> run.loop(state.context, expression.resume)
          let mode = Running(id, mode)
          #(State(..state, mode:, context:), effects)
        }
        _ -> #(state, [])
      }
    SpotlessConnectCompleted(service, result) -> {
      let #(context, effects) =
        run.connect_completed(state.context, service, result)
      #(State(..state, context:), effects)
    }
    ModuleLookupCompleted(cid, result) -> {
      let #(context, done) =
        run.get_module_completed(state.context, cid, result)
      let examples = reanalyse_examples(state.examples, done, context)
      let state = State(..state, examples:)
      // use the completed cid not the looked up cid as dependencies might have resolved
      let #(context, effects) = run.flush(context)
      case state.mode {
        Running(id, run.Pending(cache.Content(module), env:, k:)) -> {
          case list.key_find(done, module) {
            Ok(Ok(value)) -> {
              let #(run, context, inner_effects) =
                expression.resume(value, env, k)
                |> run.loop(context, expression.resume)
              let mode = Running(id, run)
              #(
                State(..state, context:, mode:),
                list.append(effects, inner_effects),
              )
            }
            // If the module is a bad one the running state stays the same. it's up for the view to render the status
            Ok(Error(_)) -> #(State(..state, context:), effects)
            Error(Nil) -> #(State(..state, context:), effects)
          }
        }
        _ -> #(State(..state, context:), effects)
      }
    }
    PullPackagesCompleted(result) -> {
      let cache = state.context.cache
      let cache = case result {
        Ok(entries) -> {
          list.fold(entries, cache, fn(cache, entry) {
            let assert Ok(payload) =
              json.parse(entry.payload, publisher.decoder())

            let publisher.Release(package:, version:, module:) = payload.content
            let release = release.Release(package:, version:, module:)
            let #(cache, _done) = cache.pulled(cache, entry.cursor, release)
            cache
          })
        }
        Error(_reason) -> {
          cache.Cache(..cache, cursor_status: cache.Pulled)
        }
      }
      let context = run.Context(..state.context, cache:)
      let #(context, effects) = run.flush(context)
      #(State(..state, context:), effects)
    }
  }
}

fn infer_context(context: run.Context(_)) {
  harness.infer_context(run.module_types(context))
}

pub fn reanalyse_examples(
  examples: dict.Dict(String, buffer.Buffer),
  _done: List(#(v1.Cid, Result(a, b))),
  context: run.Context(_),
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
      True -> buffer.reanalyse(buffer, infer_context(context))
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
    _, "@" -> edit(state, m.choose_release(state.context.cache))
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
    Running(id: _, status: _), _ -> #(state, [])
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
      browser.WriteToClipboard(text:, resume: fn(_) { Ignore }),
    ])
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn paste(state: State) {
  use id, buffer <- is_editing(state)
  case buffer.set_expression(buffer) {
    Ok(rebuild) -> {
      let state = State(..state, mode: ReadingFromClipboard(id:, rebuild:))
      #(state, [browser.ReadFromClipboard(ClipboardReadCompleted)])
    }
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn confirm(state: State) {
  use id, buffer <- is_editing(state)
  let #(mode, context, effects) =
    expression.execute(buffer.source(buffer), [])
    |> run.loop(state.context, expression.resume)
  let mode = Running(id, mode)
  #(State(..state, mode:, context:), effects)
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
