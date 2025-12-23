import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/state as istate
import eyg/interpreter/value
import eyg/ir/dag_json
import eyg/ir/tree
import gleam/dict
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import morph/action
import morph/analysis
import morph/editable
import morph/input
import morph/navigation
import morph/picker
import morph/projection as p
import morph/transformation
import website/components/runner
import website/components/snippet
import website/config
import website/harness/browser
import website/sync/cache
import website/sync/client

// Snippet actions returned a `NewCode action`
// new_code in the shell handles clearing analysis and running snippet analyse
// Choice for type checking don't check if any missing refs? the is permanent, but no relative still might change

// create a try function that returns state with error
// Use the ir builder as editable is an internal API that might change in Tests

pub type State {
  State(
    mode: Mode,
    focused: Target,
    repl: Buffer,
    modules: List(#(String, Buffer)),
    sync: client.Client,
  )
}

pub type Buffer {
  Buffer(history: snippet.History, projection: p.Projection)
}

fn history_new_entry(old, history) {
  let snippet.History(undo: undo, ..) = history
  let undo = [old, ..undo]
  snippet.History(undo: undo, redo: [])
}

fn empty_buffer() {
  Buffer(history: snippet.empty_history, projection: p.empty)
}

fn new_buffer(source) {
  Buffer(history: snippet.empty_history, projection: navigation.first(source))
}

// put/slot_expression
// update_source was the snippet function that also handles history
fn slot_expression(buffer, expression) {
  let Buffer(history:, projection: old) = buffer
  case old {
    #(p.Exp(_), zoom) -> {
      let new = #(p.Exp(expression), zoom)
      let history = history_new_entry(old, history)
      Ok(Buffer(history:, projection: new))
    }
    _ -> todo
  }
}

pub type Meta =
  Nil

pub type Mode {
  Editing
  // The Picker is still used as their is string input for fields,enums,variable
  Picking(picker: picker.Picker, rebuild: fn(String) -> p.Projection)
  // The projection in the target keeps all the rebuild information, but can error
  EditingText
  EditingInteger(value: Int, rebuild: fn(Int) -> p.Projection)
  ChoosingPackage
  // Only the shell is ever run
  // Once the run finishes the input is reset and running return
  RunningShell(debug: istate.Debug(Meta))
}

pub type Target {
  Repl
  Module(name: String)
}

pub type Action {
  FocusOnInput
  RunEffect(browser.Effect)
  SyncAction(client.Action)
}

pub fn init(config: config.Config) -> #(State, List(Action)) {
  let config.Config(registry_origin:) = config
  let #(sync, actions) = client.new(registry_origin) |> client.sync()
  let actions = list.map(actions, SyncAction)
  let state =
    State(
      sync:,
      mode: Editing,
      focused: Repl,
      repl: empty_buffer(),
      modules: [],
    )
  #(state, actions)
}

fn active(state) {
  let State(focused:, ..) = state
  case focused {
    Repl -> state.repl
    _ -> todo
  }
}

/// This is just a lens into active, it is used for navigation an edits that change code
/// Maybe the history should keep all the analysis fine but it can change if unknown refs are a thing
fn set_active(state, new) {
  let State(focused:, ..) = state
  case focused {
    Repl -> State(..state, repl: new)
    _ -> todo
  }
}

pub fn package_choice(state) {
  let State(sync: client.Client(cache:, ..), ..) = state
  cache.package_index(cache)
}

pub type Message {
  // snippet render_project doesn't include any event handling
  // actual_render_project sets up events based off attributes on the html
  // I think you need an autofocus to use normal tabs, which snippet does
  // 
  // This event assumes you are in command mode somewhere
  UserPressedCommandKey(key: String)
  // These might become autocomplete
  UserChosePackage(analysis.Release)
  InputMessage(input.Message)
  EffectImplementationCompleted(reference: Int, reply: istate.Value(Meta))
  PickerMessage(picker.Message)
  SyncMessage(client.Message)
}

pub fn update(state: State, message) -> #(State, List(Action)) {
  case message {
    UserPressedCommandKey(key:) -> user_pressed_key(state, key)
    UserChosePackage(release) -> user_chose_package(state, release)
    InputMessage(message) -> input_message(state, message)
    EffectImplementationCompleted(reference:, reply:) ->
      effect_implementation_completed(state, reference, reply)
    PickerMessage(message) -> picker_message(state, message)
    SyncMessage(message) -> sync_message(state, message)
  }
}

fn user_pressed_key(state, key) {
  let State(mode:, ..) = state
  case mode {
    Editing -> user_pressed_command_key(state, key)
    _ -> {
      echo "unexpected"
      #(state, [])
    }
  }
}

fn user_pressed_command_key(state, key) {
  let State(repl:, ..) = state
  case key {
    "ArrowRight" -> navigation.next(repl.projection) |> navigated(state)
    "ArrowLeft" -> navigation.previous(repl.projection) |> navigated(state)
    "e" -> assign_to(state)
    "g" -> select_field(state)
    "@" -> choose_release(state)
    "n" -> insert_integer(state)
    "v" -> insert_variable(state)
    "Enter" -> confirm(state)
    " " -> search_vacant(state)
    _ -> {
      echo key
      todo
    }
  }
}

fn navigated(projection, state) {
  let State(focused:, ..) = state
  case focused {
    Repl -> {
      let repl = Buffer(..state.repl, projection:)
      #(State(..state, repl:), [])
    }
    _ -> todo
  }
}

fn assign_to(state) {
  let State(focused:, ..) = state
  let buffer = case focused {
    Repl -> state.repl
    _ -> todo
  }
  let state = case transformation.assign_before(buffer.projection) {
    Ok(rebuild) ->
      State(
        ..state,
        mode: Picking(picker.new("", []), fn(s) { rebuild(editable.Bind(s)) }),
      )
    Error(Nil) -> todo as "failed position"
  }
  #(state, [FocusOnInput])
}

fn select_field(state) {
  let buffer = active(state)
  let analysis = None
  case action.select_field(buffer.projection, analysis) {
    Ok(#(hints, rebuild)) -> {
      let hints = listx.value_map(hints, debug.mono)
      #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
    }
    Error(Nil) -> todo as "cant select field"
  }
}

fn choose_release(state) {
  let state = State(..state, mode: ChoosingPackage)
  #(state, [FocusOnInput])
}

fn user_chose_package(state, release) {
  let State(mode:, ..) = state
  case mode {
    ChoosingPackage -> {
      let assert Repl = state.focused
      let analysis.Release(package:, version:, fragment:) = release
      let release =
        editable.Release(package:, release: version, identifer: fragment)
      let state = case slot_expression(state.repl, release) {
        Ok(repl) -> State(..state, mode: Editing, repl:)
        _ -> todo
      }
      #(state, [FocusOnInput])
    }

    _ -> todo
  }
}

fn insert_integer(state) {
  let buffer = active(state)
  case transformation.integer(buffer.projection) {
    Ok(#(value, rebuild)) -> #(
      State(..state, mode: EditingInteger(value:, rebuild:)),
      [FocusOnInput],
    )
    Error(Nil) -> todo as "error"
  }
}

fn insert_variable(state) {
  let buffer = active(state)
  let context =
    analysis.context()
    |> analysis.with_effects([])
  // |> update_context(cache)
  // analysis context includes effects and releases
  let analysis = analysis.do_analyse(p.rebuild(buffer.projection), context)

  case action.insert_variable(buffer.projection, Some(analysis)) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, snippet.render_poly)
      #(State(..state, mode: Picking(picker.new(filter, hints), rebuild:)), [])
    }
    Error(Nil) -> todo
  }
}

fn confirm(state) {
  let State(focused:, ..) = state
  case focused {
    Repl -> {
      let editable = p.rebuild(state.repl.projection)
      case evaluate(editable) {
        Ok(value) -> todo
        Error(#(reason, meta, env, k) as debug) ->
          case reason {
            break.UnhandledEffect(label, input) ->
              case list.key_find(browser.lookup(), label) {
                Ok(#(#(_, _), cast)) ->
                  case cast(input) {
                    Ok(effect) ->
                      case effect {
                        browser.ReadFile(file:) -> {
                          let reply = case list.key_find(state.modules, file) {
                            Ok(buffer) ->
                              value.ok(
                                value.Binary(
                                  dag_json.to_block(
                                    editable.to_annotated(
                                      p.rebuild(buffer.projection),
                                      [],
                                    ),
                                  ),
                                ),
                              )
                            Error(_) -> value.error(value.String("No file"))
                          }

                          let return = block.resume(reply, env, k)
                          case return {
                            Ok(value) -> {
                              let state = State(..state, mode: Editing)
                              echo value
                              #(state, [])
                            }
                            _ -> {
                              echo return
                              todo
                            }
                          }
                        }
                        _ -> {
                          let state = State(..state, mode: RunningShell(debug:))
                          #(state, [RunEffect(effect)])
                        }
                      }
                    Error(reason) -> {
                      let debug = #(reason, meta, env, k)
                      let state = State(..state, mode: RunningShell(debug:))
                      #(state, [])
                    }
                  }
                Error(Nil) -> {
                  let state = State(..state, mode: RunningShell(debug:))
                  #(state, [])
                }
              }
            _ -> {
              echo reason
              todo
            }
          }
      }
    }
    _ -> todo
  }
}

fn evaluate(editable) {
  editable.to_annotated(editable, [])
  |> tree.clear_annotation()
  // TODO why do we clear this
  |> block.execute([])
}

fn search_vacant(state) {
  let buffer = active(state)
  case snippet.go_to_next_vacant(buffer.projection) {
    Ok(projection) -> {
      let buffer = Buffer(..buffer, projection:)
      #(set_active(state, buffer), [])
    }
    _ -> todo
  }
}

fn input_message(state, message) {
  let State(mode:, ..) = state
  case mode, message {
    EditingInteger(value:, rebuild:), _ ->
      case input.update_number(value, message) {
        input.Continue(new) -> {
          let mode = EditingInteger(..mode, value: new)
          let state = State(..state, mode:)
          #(state, [])
        }
        input.Confirmed(value) -> #(
          update_projection(state, rebuild(value)),
          [],
        )
        input.Cancelled -> todo
      }
    _, _ -> todo
  }
}

fn effect_implementation_completed(state, reference, reply) {
  let State(mode:, ..) = state
  case mode {
    RunningShell(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      // TODO check reference and awaiting match
      echo reference
      // TODO move occured to a current state
      let occured = []
      let occured = [#(label, #(lift, reply)), ..occured]
      let return = block.resume(reply, env, k)
      case return {
        Ok(value) -> {
          let state = State(..state, mode: Editing)
          #(state, [])
        }
        _ -> {
          echo return
          todo
        }
      }
    }
    _ -> {
      echo reply
      todo
    }
  }
}

fn picker_message(state, message) {
  let State(mode:, ..) = state
  case mode {
    Picking(picker:, rebuild:) ->
      case message {
        picker.Updated(..) -> todo
        picker.Decided(label) -> {
          let new = rebuild(label)
          #(update_projection(state, new), [])
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }
    _ -> todo
  }
}

/// Always used after a change that was from a command and that changes the history
/// 
fn update_projection(state, new) {
  let State(focused:, ..) = state
  case focused {
    Repl -> {
      let Buffer(history:, projection: old) = state.repl
      let history = history_new_entry(old, history)
      let repl = Buffer(history:, projection: new)
      State(..state, mode: Editing, repl:)
    }
    _ -> todo
  }
}

/// Used for testing
pub fn replace_repl(state, new) {
  let State(repl:, ..) = state
  let repl = Buffer(..repl, projection: new)
  State(..state, repl:)
}

/// Used for testing
pub fn set_module(state, name, source) {
  let State(modules:, ..) = state
  let modules = listx.key_reject(modules, name)
  let modules = [#(name, new_buffer(source)), ..modules]
  State(..state, modules:)
}

fn sync_message(state, message) {
  let State(sync:, ..) = state
  let #(sync, actions) = client.update(sync, message)
  let actions = list.map(actions, SyncAction)
  let state = State(..state, sync:)
  #(state, actions)
}
