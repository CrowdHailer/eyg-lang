import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/state as istate
import eyg/interpreter/value
import eyg/ir/dag_json
import eyg/ir/tree
import gleam/bit_array
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import morph/action
import morph/analysis
import morph/editable as e
import morph/input
import morph/navigation
import morph/picker
import morph/projection as p
import morph/transformation
import website/components/readonly
import website/components/shell
import website/components/snippet
import website/config
import website/harness/browser
import website/routes/workspace/buffer
import website/sync/cache
import website/sync/client

// Create module effect
// Do analysis should be switched to using contextual
// action is build on analysis
// Work out how to migrate actions to not use morph analysis
// get rid of implicit insert when clicking on the same thing.
// j is expected on a vacant node

// Do we return actions from Buffer
// Are all the returns Current/labels + types and rebuild
// No because for choose packages we might go all the way to a semantic search
// Instead query from analysis. buffer.checkin_context

// TODO remove morph analysis instead try and link we contextual infer context

// Snippet actions returned a `NewCode action`
// new_code in the shell handles clearing analysis and running snippet analyse
// Choice for type checking don't check if any missing refs? the is permanent, but no relative still might change

// create a try function that returns state with error
// Use the ir builder as editable is an internal API that might change in Tests
// buffer errs or clears state
// copy is better at top level that actions returned from buffer, need other errors
// Buffer failure won't include unknown key type

// All the help is based on exact projection position
// type_varients,type_fields,or count arguments

// complexity on making record was on the pattern matching mostly
// OR editing matches
// extend before/after

// Keybind -> buffer.Message
// apply(buffer,action) -> history/not updated analysis or not removed
// when does new analysis get set

// overwrite etc does it move, can we get a new buffer in the right position

// Nothing -> We expect this
// Failed(Failure) -> return error
// ReturnToCode -> Don't need this is all key bindings
// FocusOnInput -> This is interesting Not from the Snippet
// ToggleHelp -> Not part of it
// MoveAbove -> Needed
// MoveBelow -> Needed
// WriteToClipboard(String)
// ReadFromClipboard
// NewCode -> Clear from analysis
// Confirm

pub type State {
  State(
    mode: Mode,
    user_error: Option(snippet.Failure),
    focused: Target,
    previous: List(shell.ShellEntry),
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
  from_projection(navigation.first(source))
}

fn from_projection(projection) {
  Buffer(history: snippet.empty_history, projection:)
}

/// set an expression in the active buffer assumes that you are already on an expression
fn set_expression(state, expression) {
  let buffer = active(state)
  case buffer.projection {
    #(p.Exp(_), zoom) -> {
      let new = #(p.Exp(expression), zoom)
      Ok(update_projection(state, new))
    }
    _ -> Error(Nil)
  }
}

/// Always used after a change that was from a command and that changes the history
/// The new value is the full projection, probably from a rebuild function
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
  WritingToClipboard
  ReadingFromClipboard
}

pub type Target {
  Repl
  Module(name: String)
}

pub type Action {
  FocusOnInput
  WriteToClipboard(text: String)
  ReadFromClipboard
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
      user_error: None,
      focused: Repl,
      previous: [],
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
  ClipboardReadCompleted(Result(String, String))
  ClipboardWriteCompleted(Result(Nil, String))
  EffectImplementationCompleted(reference: Int, reply: istate.Value(Meta))
  PickerMessage(picker.Message)
  SyncMessage(client.Message)
}

pub fn update(state: State, message) -> #(State, List(Action)) {
  case message {
    UserPressedCommandKey(key:) -> user_pressed_key(state, key)
    UserChosePackage(release) -> user_chose_package(state, release)
    InputMessage(message) -> input_message(state, message)
    ClipboardReadCompleted(result) -> clipboard_read_complete(state, result)
    ClipboardWriteCompleted(result) -> clipboard_write_complete(state, result)
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
      echo mode
      #(state, [])
    }
  }
}

fn user_pressed_command_key(state, key) {
  let State(repl:, ..) = state
  let state = State(..state, user_error: None)
  case key {
    "ArrowRight" -> navigation.next(repl.projection) |> navigated(state)
    "ArrowLeft" -> navigation.previous(repl.projection) |> navigated(state)
    "ArrowUp" -> move_up(state)
    "ArrowDown" -> move_down(state)
    "e" -> assign_to(state)
    "y" -> copy(state)
    "Y" -> paste(state)
    "p" -> perform(state)
    "a" -> increase(state)
    "g" -> select_field(state)
    "@" -> choose_release(state)
    "#" -> insert_reference(state)
    // choose release just checks is expression
    "n" -> insert_integer(state)
    "m" -> insert_case(state)
    "v" -> insert_variable(state)
    "Enter" -> confirm(state)
    " " -> search_vacant(state)
    _ -> #(State(..state, user_error: Some(snippet.NoKeyBinding(key))), [])
  }
}

// Experiment with op on buffer, will try move above/bellow as test first
// fn op(state, operation) {
//   let buffer = active(state)
//   let buffer = buffer_operate(buffer, operation)
//   // result of buffer
//   set_active(state, buffer)
// }

// If analysis missing then request and do the query
// Buffer should track packages on v 0

// fn buffer_operate(buffer: Buffer, operation) {
//   case operation {
//     buffer.GoToNext -> todo
//     _ -> todo
//   }
// }

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

fn move_up(state) {
  let buffer = active(state)
  case navigation.move_up(buffer.projection) {
    Ok(new) -> navigated(navigation.next(new), state)
    Error(Nil) ->
      case state.focused == Repl, state.previous {
        True, [entry, ..] -> {
          let repl = from_projection(entry.source.projection)
          #(State(..state, repl:), [])
        }
        _, _ -> fail(state, "move above")
      }
  }
}

fn move_down(state) {
  todo
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
        mode: Picking(picker.new("", []), fn(s) { rebuild(e.Bind(s)) }),
      )
    Error(Nil) -> todo as "failed position"
  }
  #(state, [FocusOnInput])
}

fn copy(state) {
  let buffer = active(state)
  case buffer.projection {
    #(p.Exp(expression), _) -> {
      let text =
        e.to_annotated(expression, [])
        |> dag_json.to_string

      let state = State(..state, mode: WritingToClipboard)
      #(state, [WriteToClipboard(text:)])
    }
    _ -> fail(state, "copy")
  }
}

fn paste(state) {
  let buffer = active(state)
  case buffer.projection {
    #(p.Exp(_expression), _) -> {
      let state = State(..state, mode: ReadingFromClipboard)
      #(state, [ReadFromClipboard])
    }
    _ -> todo
    // fail(state, "copy")
  }
}

fn fail(state, action) {
  let state = State(..state, user_error: Some(snippet.ActionFailed(action)))
  #(state, [])
}

// wrap in an on expression
fn perform(state) {
  let buffer = active(state)

  case buffer.projection {
    #(p.Exp(lift), zoom) -> {
      let hints =
        browser.lookup()
        |> list.map(fn(effect) {
          let #(key, #(types, _)) = effect
          #(key, snippet.render_effect(types))
        })
      let rebuild = fn(label) {
        let zoom = [p.CallArg(e.Perform(label), [], []), ..zoom]
        #(p.Exp(lift), zoom)
      }
      #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
    }
    _ ->
      // echo buffer
      // let analysis = do_analysis(buffer.projection)
      // // analysis on the effects of the function
      // echo analysis
      // is on expression
      // effects
      todo
  }
}

fn increase(state) {
  let buffer = active(state)
  case navigation.increase(buffer.projection) {
    Ok(projection) -> navigated(projection, state)
    _ -> todo
  }
}

fn select_field(state) {
  let buffer = active(state)
  let analysis = do_analysis(buffer.projection)
  case action.select_field(buffer.projection, Some(analysis)) {
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
      let analysis.Release(package:, version:, fragment:) = release
      let release = e.Release(package:, release: version, identifer: fragment)
      let state = case set_expression(state, release) {
        Ok(state) -> State(..state, mode: Editing)
        _ -> todo
      }
      #(state, [FocusOnInput])
    }

    _ -> todo
  }
}

fn insert_reference(state) {
  let buffer = active(state)
  case action.insert_reference(buffer.projection) {
    Ok(#(current, rebuild)) -> {
      let mode = Picking(picker: picker.new(current, []), rebuild:)
      #(State(..state, mode:), [FocusOnInput])
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

fn insert_case(state) {
  let buffer = active(state)
  case target_type(buffer.projection) {
    Ok(t.Union(t.RowExtend(first, _, rest))) -> {
      // expect there to be at least one row and for it not to be open
      let rest =
        list.map(analysis.rows(rest), fn(r) {
          let #(label, _) = r
          #(label, e.Function([e.Bind("_")], e.Vacant))
        })
      // Need to unpick as in some cases we just create and in others we pick.
      // Reality is we want a pick multiple
      let assert #(p.Exp(top), zoom) = buffer.projection

      let new = #(p.Exp(e.Vacant), [
        p.Body([e.Bind("_")]),
        p.CaseMatch(top, first, [], rest, None),
        ..zoom
      ])
      #(update_projection(state, new), [])
    }
    _ -> todo
  }
}

fn insert_variable(state) {
  let buffer = active(state)

  let analysis = do_analysis(buffer.projection)

  case action.insert_variable(buffer.projection, Some(analysis)) {
    Ok(#(filter, hints, rebuild)) -> {
      let hints = listx.value_map(hints, snippet.render_poly)
      #(State(..state, mode: Picking(picker.new(filter, hints), rebuild:)), [])
    }
    Error(Nil) -> todo
  }
}

fn do_analysis(projection) {
  // |> update_context(cache)
  // analysis context includes effects and releases
  let context =
    analysis.context()
    |> analysis.with_effects([])
  // |> update_context(cache)
  // analysis context includes effects and releases
  analysis.do_analyse(p.rebuild(projection), context)
}

fn confirm(state) {
  let State(focused:, ..) = state
  case focused {
    Repl -> {
      let editable = p.rebuild(state.repl.projection)
      case evaluate(editable) {
        Ok(#(value, scope)) -> {
          // Type is shell entry
          let entry =
            shell.Executed(
              value:,
              effects: [],
              source: readonly.new(p.rebuild(state.repl.projection)),
            )
          let previous = [entry, ..state.previous]
          let repl = empty_buffer()
          let state = State(..state, previous:, repl:)
          #(state, [])
        }
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
                                    e.to_annotated(
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
                              // echo value
                              #(state, [])
                            }
                            _ -> {
                              // echo return
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
  e.to_annotated(editable, [])
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

fn clipboard_read_complete(state, return) {
  let State(mode:, ..) = state
  case mode {
    ReadingFromClipboard ->
      case return {
        Ok(text) ->
          case dag_json.from_block(bit_array.from_string(text)) {
            Ok(expression) -> {
              case active(state).projection {
                #(p.Exp(_), zoom) -> {
                  let proj = #(p.Exp(e.from_annotated(expression)), zoom)
                  // update_source_from_buffer(proj, state)
                  #(update_projection(state, proj), [])
                }
                _ -> todo as "action_failed(state, paste)"
              }
            }
            Error(_) -> todo as "action_failed(state, paste)"
          }
        Error(_) -> todo as "action_failed(state, paste)"
      }
    _ -> todo
  }
}

fn clipboard_write_complete(state, message) {
  let State(mode:, ..) = state
  case mode {
    WritingToClipboard ->
      case message {
        Ok(Nil) -> {
          let state = State(..state, mode: Editing)
          #(state, [])
        }
        Error(_) -> todo
      }
    _ -> todo
  }
}

fn effect_implementation_completed(state, reference, reply) {
  let State(mode:, ..) = state
  case mode {
    RunningShell(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      // TODO check reference and awaiting match
      // echo reference
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
    Picking(picker: _, rebuild:) ->
      case message {
        picker.Updated(picker:) -> #(
          State(..state, mode: Picking(picker:, rebuild:)),
          [],
        )
        picker.Decided(label) -> {
          let new = rebuild(label)
          #(update_projection(state, new), [])
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
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

pub fn target_type(projection) {
  let source = e.to_annotated(p.rebuild(projection), [])
  let analysis =
    infer.pure()
    |> infer.check(source)

  let path = p.path(projection)

  // multi pick is what we really want here
  infer.type_at(analysis, path)
}
