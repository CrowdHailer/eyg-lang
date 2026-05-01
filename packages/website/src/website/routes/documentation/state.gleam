import eyg/analysis/inference/levels_j/contextual as infer
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict.{type Dict}
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import morph/editable as e
import morph/input
import morph/navigation
import morph/picker
import multiformats/cid/v1
import website/config
import website/harness/browser
import website/harness/harness
import website/manipulation
import website/routes/documentation/examples
import website/routes/workspace/buffer
import website/run

pub type State {
  State(
    mode: Mode,
    examples: Dict(String, Example),
    context: run.Context(Message),
  )
}

pub type Example {
  Example(buffer: buffer.Buffer)
}

pub type Rebuild(t) =
  fn(t, infer.Context) -> buffer.Buffer

// An edit status could be reused over the applications but viewing it would be separate
// Change Editing -> Focused/Navigating
// Manipulating is called editing, EditingStatus is there
pub type Mode {
  Editing(id: String, failure: Option(Failure))
  EditingInteger(id: String, value: Int, rebuild: Rebuild(Int))
  EditingText(id: String, value: String, rebuild: Rebuild(String))
  Picking(id: String, picker: picker.Picker, rebuild: Rebuild(String))
  ReadingFromClipboard(id: String, rebuild: Rebuild(e.Expression))
  Running(id: String, status: run.Run)
  UnFocused
}

pub type Meta =
  List(Int)

pub type Value =
  state.Value(Meta)

pub type Debug =
  state.Debug(Meta)

pub type Return =
  Result(Value, Debug)

pub type Failure {
  NoKeyBinding(key: String)
  ActionFailed(action: String)
  // RunFailed(istate.Debug(Path))
}

pub fn fail_message(reason) {
  case reason {
    NoKeyBinding(key) -> string.concat(["No action bound for key '", key, "'"])
    ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
    // RunFailed(#(reason, _, _, _)) -> simple_debug.reason_to_string(reason)
  }
}

pub type Message {
  UserClickedCode(id: String, path: List(Int))
  UserPressedKey(key: String)
  InputMessage(input.Message)
  PickerMessage(picker.Message)

  ClipboardReadCompleted(Result(String, String))
  Ignore
  EffectHandled(task_id: Int, value: Value)
  SpotlessConnectCompleted(harness.Service, Result(String, String))
  ModuleLookupCompleted(v1.Cid, Result(ir.Node(Nil), String))
}

pub fn get_example(state: State, id) {
  let assert Ok(snippet) = dict.get(state.examples, id)
  snippet
}

pub fn set_example(state: State, id, snippet) {
  State(..state, examples: dict.insert(state.examples, id, snippet))
}

// snippet failure goes at top level
pub fn init(config) {
  let config.Config(origin:) = config
  let context =
    run.empty(EffectHandled, SpotlessConnectCompleted, ModuleLookupCompleted)

  let examples =
    list.map(examples.all(), fn(example) {
      let #(key, editable) = example
      let projection = navigation.first(editable)
      // keep evaluation on example, if it runs don't print type errors. but show them in the code
      let example = Example(buffer.from_projection(projection, infer.pure()))
      #(key, example)
    })
  let examples = dict.from_list(examples)

  let state = State(UnFocused, examples, context)
  #(state, [])
}

pub fn update(state: State, message) {
  case message {
    UserClickedCode(id:, path:) -> {
      let Example(buffer:) = get_example(state, id)
      let buffer = buffer.focus_at(buffer, path) |> result.unwrap(buffer)
      let state = set_example(state, id, Example(buffer:))
      let state = State(..state, mode: Editing(id:, failure: None))
      #(state, [])
    }
    UserPressedKey(key:) -> user_pressed_key(state, key)
    InputMessage(message) -> {
      let State(mode:, ..) = state
      case mode, message {
        EditingInteger(id:, value:, rebuild:), _ ->
          case input.update_number(value, message) {
            input.Continue(new) -> {
              let mode = EditingInteger(..mode, value: new)
              let state = State(..state, mode:)
              #(state, [])
            }
            input.Confirmed(value) -> {
              let state =
                set_example(state, id, Example(rebuild(value, infer.pure())))
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
            input.Cancelled -> {
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
          }
        EditingText(id:, value:, rebuild:), _ ->
          case input.update_text(value, message) {
            input.Continue(new) -> {
              let mode = EditingText(..mode, value: new)
              let state = State(..state, mode:)
              #(state, [])
            }
            input.Confirmed(value) -> {
              let state =
                set_example(state, id, Example(rebuild(value, infer.pure())))
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
            input.Cancelled -> {
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
          }
        _, _ -> #(state, [])
      }
    }
    PickerMessage(message) -> {
      let State(mode:, ..) = state
      case mode {
        Picking(id:, rebuild:, ..) ->
          case message {
            picker.Updated(picker:) -> #(
              State(..state, mode: Picking(id:, picker:, rebuild:)),
              [],
            )
            picker.Decided(label) -> {
              let state =
                set_example(state, id, Example(rebuild(label, infer.pure())))
              let state = State(..state, mode: Editing(id:, failure: None))
              #(state, [])
            }
            picker.Dismissed -> #(
              State(..state, mode: Editing(id:, failure: None)),
              [],
            )
          }
        _ -> todo
      }
    }

    ClipboardReadCompleted(return) -> {
      case state.mode {
        ReadingFromClipboard(id, rebuild) ->
          case return {
            Ok(text) ->
              case json.parse(text, dag_json.decoder(Nil)) {
                Ok(expression) -> {
                  let buffer =
                    rebuild(e.from_annotated(expression), infer.pure())
                  let example = Example(buffer:)
                  let state = set_example(state, id, example)
                  let state = State(..state, mode: Editing(id, None))
                  #(state, [])
                }

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
        Running(id:, status: run.Suspended(task_id:, env:, k:))
          if tid == task_id
        -> {
          let #(mode, context, effects) =
            expression.resume(value, env, k)
            |> run.loop(state.context)
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
      let #(context, done, effects) =
        run.get_module_completed(state.context, cid, result)
      let mode =
        list.fold(done, state.mode, fn(mode, result) {
          mode
          todo
        })

      #(State(..state, context:, mode:), effects)
    }
  }
}

fn user_pressed_key(state, key) {
  let State(mode:, ..) = state
  // set error to nothing
  case mode, key {
    _, "Escape" -> #(State(..state, mode: UnFocused), [])
    _, "ArrowRight" -> navigate(state, "move right", buffer.next)
    _, "ArrowLeft" -> navigate(state, "move left", buffer.previous)
    _, "ArrowUp" -> navigate(state, "move up", buffer.up)
    _, "ArrowDown" -> navigate(state, "move down", buffer.down)
    // "Q" -> link_filesystem(state)
    // "q" -> choose_module(state)
    _, "w" -> edit(state, manipulation.call_with())
    _, "E" -> edit(state, manipulation.assign_before())
    _, "e" -> edit(state, manipulation.assign())
    _, "R" -> edit(state, manipulation.create_empty_record())
    _, "r" -> edit(state, manipulation.create_record())
    _, "t" -> edit(state, manipulation.insert_tag())
    _, "y" -> copy(state)
    _, "Y" -> paste(state)
    // // TODO mode is authenticating
    // // you won't see much on the front page
    // "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
    //   OpenPopup("/sign"),
    // ])
    _, "i" -> edit(state, manipulation.insert())
    _, "o" -> edit(state, manipulation.overwrite())
    _, "p" -> edit(state, manipulation.perform())
    _, "a" -> navigate(state, "increase selection", buffer.increase)
    _, "s" -> edit(state, manipulation.insert_string())
    _, "d" -> edit(state, manipulation.delete())
    _, "f" -> edit(state, manipulation.insert_function())
    _, "g" -> edit(state, manipulation.select_field())
    _, "h" -> edit(state, manipulation.insert_handle())
    _, "j" -> edit(state, manipulation.insert_builtin())
    _, "k" -> navigate(state, "toggle", buffer.toggle_open)
    _, "L" -> edit(state, manipulation.create_empty_list())
    _, "l" -> edit(state, manipulation.create_list())
    // choose release is different type returned i.e. cid
    // _, "@" -> choose_release(state)
    // _, "#" -> insert_reference(state)
    // _, // _, choose release just checks is expression
    _, "Z" -> edit(state, manipulation.redo())
    _, "z" -> edit(state, manipulation.undo())
    _, "x" -> edit(state, manipulation.spread())
    _, "c" -> edit(state, manipulation.call_function())
    _, "C" -> edit(state, manipulation.call_once())
    _, "b" -> edit(state, manipulation.insert_binary())
    _, "n" -> edit(state, manipulation.insert_integer())
    _, "m" -> edit(state, manipulation.insert_case())
    _, "v" -> edit(state, manipulation.insert_variable())
    _, "<" -> edit(state, manipulation.insert_before())
    _, ">" -> edit(state, manipulation.insert_after())
    _, "Enter" -> confirm(state)
    _, " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    Editing(id, _error), _ -> {
      let mode = Editing(id, Some(NoKeyBinding(key)))
      #(State(..state, mode:), [])
    }
    UnFocused, _ -> #(state, [])
    ReadingFromClipboard(id: _, rebuild: _), _ -> #(state, [])
    Running(id: _, status: _), _ -> #(state, [])
    Picking(id: _, picker: _, rebuild: _), _ -> #(state, [])
    EditingInteger(id: _, value: _, rebuild: _), _ -> #(state, [])
    EditingText(id: _, value: _, rebuild: _), _ -> #(state, [])
  }
}

fn navigate(state: State, name, func) {
  use id, Example(buffer:) <- is_editing(state)

  case func(buffer) {
    Ok(buffer) -> {
      let state = set_example(state, id, Example(buffer:))
      let state = State(..state, mode: Editing(id:, failure: None))
      #(state, [])
    }
    Error(_reason) -> action_failed(state, id, name)
  }
}

// can't 1 for 1 map over a working state for the buffer because of the gen -> buffer step in resolved
fn edit(state, manipulation) {
  use id, Example(buffer:) <- is_editing(state)
  let manipulation.Operation(name:, apply:) = manipulation
  case apply(buffer) {
    Ok(manipulation.Resolved(gen)) -> {
      let state = set_example(state, id, Example(buffer: gen(infer.pure())))
      let state = State(..state, mode: Editing(id:, failure: None))
      #(state, [])
    }
    Ok(manipulation.PickSingle(picker, rebuild)) -> {
      let mode = Picking(id, picker, rebuild:)
      #(State(..state, mode:), [])
    }
    Ok(manipulation.EnterText(value, rebuild)) -> {
      let mode = EditingText(id, value, rebuild:)
      #(State(..state, mode:), [])
    }
    Ok(manipulation.EnterInteger(value, rebuild)) -> {
      let mode = EditingInteger(id, value, rebuild:)
      #(State(..state, mode:), [])
    }
    Error(Nil) -> action_failed(state, id, name)
  }
}

/// don't do key press under a mode switch
fn copy(state: State) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.copy_source(buffer) {
    Ok(text) -> #(state, [
      browser.WriteToClipboard(text:, resume: fn(_) { Ignore }),
    ])
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn paste(state: State) {
  use id, Example(buffer:) <- is_editing(state)
  case buffer.set_expression(buffer) {
    Ok(rebuild) -> {
      let state = State(..state, mode: ReadingFromClipboard(id:, rebuild:))
      #(state, [browser.ReadFromClipboard(ClipboardReadCompleted)])
    }
    Error(Nil) -> action_failed(state, id, "copy")
  }
}

fn confirm(state: State) {
  use id, Example(buffer:) <- is_editing(state)
  let #(mode, context, effects) =
    expression.execute(buffer.source(buffer), []) |> run.loop(state.context)
  let mode = Running(id, mode)
  #(State(..state, mode:, context:), effects)
}

fn is_editing(state: State, then) {
  case state.mode {
    Editing(id:, failure: _) -> then(id, get_example(state, id))
    UnFocused -> #(state, [])
    ReadingFromClipboard(..) -> #(state, [])
    Running(id: _, status: _) -> #(state, [])
    Picking(id: _, picker: _, rebuild: _) -> #(state, [])
    _ -> #(state, [])
  }
}

fn action_failed(state, id, name) {
  let state =
    State(..state, mode: Editing(id:, failure: Some(ActionFailed(name))))
  #(state, [])
}
