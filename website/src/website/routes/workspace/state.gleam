import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/state as istate
import eyg/interpreter/value
import eyg/ir/dag_json
import eyg/ir/tree
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
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
import website/routes/workspace/buffer.{type Buffer}
import website/sync/cache
import website/sync/client

pub type State {
  State(
    mode: Mode,
    user_error: Option(snippet.Failure),
    focused: Target,
    previous: List(shell.ShellEntry),
    repl: Buffer,
    modules: Dict(String, Buffer),
    sync: client.Client,
  )
}

/// set an expression in the active buffer assumes that you are already on an expression
/// Always goes back to editing unless a fail
fn set_expression(state, expression) {
  let buffer = active(state)
  case buffer.projection {
    #(p.Exp(_), zoom) -> {
      let new = #(p.Exp(expression), zoom)
      update_projection(state, new)
    }
    _ -> fail(state, "set expression")
  }
}

fn typing_context(cache: cache.Cache) {
  infer.pure()
  |> infer.with_references(cache.type_map(cache))
}

/// Always used after a change that was from a command and that changes the history
/// The new value is the full projection, probably from a rebuild function
fn update_projection(state, new) {
  let buffer =
    buffer.update_code(active(state), new, typing_context(state.sync.cache))
  let cids = infer.missing_references(buffer.analysis)
  let #(sync, actions) = client.fetch_fragments(state.sync, cids)
  let actions = list.map(actions, SyncAction)

  let state =
    State(..state, mode: Editing, sync:)
    |> replace_buffer(buffer)
  #(state, actions)
}

/// replaces buffer in the tree
fn replace_buffer(state: State, buffer) {
  let State(focused:, modules:, ..) = state
  case focused {
    Repl -> State(..state, repl: buffer)
    Module(path) -> {
      let modules = dict.insert(modules, path, buffer)
      State(..state, modules:)
    }
  }
}

pub type Meta =
  Nil

pub type Mode {
  Editing
  // The Picker is still used as their is string input for fields,enums,variable
  Picking(picker: picker.Picker, rebuild: fn(String) -> p.Projection)
  // The projection in the target keeps all the rebuild information, but can error
  EditingText(value: String, rebuild: fn(String) -> p.Projection)
  EditingInteger(value: Int, rebuild: fn(Int) -> p.Projection)
  ChoosingPackage
  // Only the shell is ever run
  // Once the run finishes the input is reset and running return
  RunningShell(
    occured: List(#(String, #(istate.Value(Meta), istate.Value(Meta)))),
    debug: istate.Debug(Meta),
  )
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
      repl: buffer.empty(typing_context(sync.cache)),
      modules: dict.new(),
    )
  #(state, actions)
}

fn active(state) {
  let State(focused:, modules:, ..) = state
  case focused {
    Repl -> state.repl
    Module(path) ->
      case dict.get(modules, path) {
        Ok(buffer) -> buffer
        _ -> buffer.empty(typing_context(state.sync.cache))
      }
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
  let state = State(..state, user_error: None)
  case key {
    "Escape" -> #(State(..state, focused: Repl), [])
    "ArrowRight" -> move_next(state)
    "ArrowLeft" -> move_previous(state)
    "ArrowUp" -> move_up(state)
    "ArrowDown" -> move_down(state)
    "e" -> assign_to(state)
    "R" -> insert_empty_record(state)
    "y" -> copy(state)
    "Y" -> paste(state)
    "p" -> perform(state)
    "a" -> increase(state)
    "s" -> insert_string(state)
    "g" -> select_field(state)
    "L" -> insert_empty_list(state)
    "@" -> choose_release(state)
    "#" -> insert_reference(state)
    // choose release just checks is expression
    "Z" -> redo(state)
    "z" -> undo(state)
    "n" -> insert_integer(state)
    "m" -> insert_case(state)
    "v" -> insert_variable(state)
    "Enter" -> confirm(state)
    " " -> search_vacant(state)
    _ -> #(State(..state, user_error: Some(snippet.NoKeyBinding(key))), [])
  }
}

fn move_next(state) {
  always_nav(state, navigation.next)
}

fn move_previous(state) {
  always_nav(state, navigation.previous)
}

fn move_up(state) {
  let buffer = active(state)
  case navigation.move_up(buffer.projection) {
    Ok(new) -> {
      let buffer = buffer.update_position(buffer, new)
      #(replace_buffer(state, buffer), [])
    }
    Error(Nil) ->
      case state.focused == Repl, state.previous {
        True, [entry, ..] -> {
          let repl =
            buffer.from_projection(
              entry.source.projection,
              typing_context(state.sync.cache),
            )
          #(State(..state, repl:), [])
        }
        _, _ -> fail(state, "move above")
      }
  }
}

fn move_down(state) {
  nav(state, navigation.move_down, "move below")
}

fn always_nav(state, navigation) {
  nav(state, fn(p) { Ok(navigation(p)) }, "")
}

fn nav(state, navigation: fn(p.Projection) -> Result(_, _), reason) {
  case navigation(active(state).projection) {
    Ok(projection) -> {
      let buffer = buffer.update_position(state.repl, projection)
      #(replace_buffer(state, buffer), [])
    }
    Error(_) -> fail(state, reason)
  }
}

fn assign_to(state) {
  let buffer = active(state)
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

fn insert_empty_record(state) {
  set_expression(state, e.Record([], None))
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
    _ -> fail(state, "paste")
  }
}

fn state_fail(state, action) {
  State(..state, user_error: Some(snippet.ActionFailed(action)))
}

fn fail(state, action) {
  let state = state_fail(state, action)
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

      // // analysis on the effects of the function
      // echo analysis
      // is on expression
      // effects
      todo
  }
}

fn increase(state) {
  nav(state, navigation.increase, "increase selection")
}

fn insert_string(state) {
  case transformation.string(active(state).projection) {
    Ok(#(value, rebuild)) -> {
      let state = State(..state, mode: EditingText(value:, rebuild:))
      #(state, [])
    }
    Error(Nil) -> fail(state, "create text")
  }
}

fn select_field(state) {
  let buffer = active(state)
  let hints = case buffer.target_type(buffer) {
    Ok(t.Record(rows)) -> listx.value_map(analysis.rows(rows), debug.mono)
    _ -> []
  }
  case buffer.projection {
    #(p.Exp(inner), zoom) -> {
      let rebuild = fn(label) { #(p.Exp(e.Select(inner, label)), zoom) }
      #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
    }
    _ -> todo
  }
  // picked_transform(state, hints, do_select_field)
}

// fn do_select_field(projection) {
//   case projection {
//     #(p.Exp(inner), zoom) ->
//       Ok(fn(label) { #(p.Exp(e.Select(inner, label)), zoom) })
//     _ -> Error(Nil)
//   }
// }

// fn picked_transform(state, hints, start: fn(p.Projection) -> _) {
//   case start(active(state).projection) {
//     Ok(rebuild) -> #(
//       State(..state, mode: Picking(picker.new("", hints), rebuild:)),
//       [],
//     )
//     Error(Nil) -> todo
//   }
// }

fn insert_empty_list(state) {
  set_expression(state, e.List([], None))
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
      let #(state, actions) = set_expression(state, release)
      #(state, [FocusOnInput, ..actions])
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

fn undo(state) {
  case buffer.undo(active(state), typing_context(state.sync.cache)) {
    Ok(buffer) -> #(replace_buffer(state, buffer), [])
    Error(Nil) -> fail(state, "undo")
  }
}

fn redo(state) {
  case buffer.redo(active(state), typing_context(state.sync.cache)) {
    Ok(buffer) -> #(replace_buffer(state, buffer), [])
    Error(Nil) -> fail(state, "redo")
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
  case buffer.target_type(buffer) {
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
      update_projection(state, new)
    }
    _ ->
      case buffer.projection {
        #(p.Exp(_), _) -> todo
        _ -> fail(state, "insert match")
      }
  }
}

fn insert_variable(state) {
  let buffer = active(state)
  let scope = buffer.target_scope(buffer) |> result.unwrap([])
  let hints = listx.value_map(scope, snippet.render_poly)
  case buffer.projection {
    #(p.Exp(_), zoom) -> {
      let rebuild = fn(var) { #(p.Exp(e.Variable(var)), zoom) }
      #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
    }
    _ -> todo
  }
}

fn confirm(state) {
  let State(focused:, ..) = state
  case focused {
    Repl -> {
      let editable = p.rebuild(state.repl.projection)
      run(evaluate(editable), [], state)
    }
    _ -> fail(state, "Can't execute module")
  }
}

fn evaluate(editable) {
  e.to_annotated(editable, [])
  |> tree.clear_annotation()
  // TODO why do we clear this
  |> block.execute([])
}

fn run(return, occured, state: State) {
  case return {
    Ok(#(value, scope)) -> {
      // Type is shell entry
      let entry =
        shell.Executed(
          value:,
          effects: list.reverse(occured),
          source: readonly.new(p.rebuild(state.repl.projection)),
        )
      let previous = [entry, ..state.previous]
      let repl = buffer.empty(typing_context(state.sync.cache))
      let state = State(..state, mode: Editing, previous:, repl:)
      #(state, [])
    }
    Error(debug) -> {
      let #(reason, meta, env, k) = debug
      case reason {
        // internal not part of browser
        break.UnhandledEffect("Open", input) ->
          case cast.as_string(input) {
            Ok(filename) -> {
              let return = block.resume(value.Record(dict.new()), env, k)
              let state = State(..state, focused: Module(filename))
              // let occured = [#()]
              run(return, occured, state)
            }
            Error(_) -> todo
          }
        break.UnhandledEffect(label, input) ->
          case list.key_find(browser.lookup(), label) {
            Ok(#(#(_, _), cast)) ->
              case cast(input) {
                Ok(effect) ->
                  case effect {
                    browser.ReadFile(file:) -> {
                      let reply = case dict.get(state.modules, file) {
                        Ok(buffer) ->
                          value.ok(
                            value.Binary(
                              dag_json.to_block(
                                e.to_annotated(p.rebuild(buffer.projection), []),
                              ),
                            ),
                          )
                        Error(_) -> value.error(value.String("No file"))
                      }

                      run(block.resume(reply, env, k), occured, state)
                    }
                    _ -> {
                      let state =
                        State(..state, mode: RunningShell(occured:, debug:))
                      #(state, [RunEffect(effect)])
                    }
                  }
                Error(reason) -> {
                  let debug = #(reason, meta, env, k)
                  let state =
                    State(..state, mode: RunningShell(occured:, debug:))
                  #(state, [])
                }
              }
            Error(Nil) -> {
              let state = State(..state, mode: RunningShell(occured:, debug:))
              #(state, [])
            }
          }
        break.UndefinedReference(cid) ->
          case dict.get(state.sync.cache.fragments, cid) {
            Ok(cache.Fragment(value:, ..)) ->
              run(block.resume(value, env, k), occured, state)
            _ -> todo
          }
        _ -> {
          echo reason
          todo
        }
      }
    }
  }
}

fn search_vacant(state) {
  nav(state, snippet.go_to_next_vacant, "Jump to vacant")
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
        input.Confirmed(value) -> update_projection(state, rebuild(value))
        input.Cancelled -> todo
      }
    EditingText(value:, rebuild:), _ ->
      case input.update_text(value, message) {
        input.Continue(new) -> {
          let mode = EditingText(..mode, value: new)
          let state = State(..state, mode:)
          #(state, [])
        }
        input.Confirmed(value) -> update_projection(state, rebuild(value))
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
            Ok(expression) ->
              set_expression(state, e.from_annotated(expression))

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
    // put awaiting false for the fact it's no longer running
    RunningShell(occured, #(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      // TODO check reference and awaiting match
      // echo reference

      let occured = [#(label, #(lift, reply)), ..occured]
      run(block.resume(reply, env, k), occured, state)
    }
    _ -> {
      echo reply
      todo
    }
  }
}

// put mode on the first argument and  update state before looping
fn resume_from_effect(label, lift, reply, env, k) {
  todo
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
          update_projection(state, new)
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }
    _ -> todo
  }
}

/// Used for testing
pub fn replace_repl(state: State, new) {
  let repl = buffer.from_projection(new, typing_context(state.sync.cache))
  State(..state, repl:)
}

/// Used for testing
pub fn set_module(state, name, projection) {
  let State(modules:, ..) = state
  let modules =
    dict.insert(modules, name, buffer.from_projection(projection, infer.pure()))
  State(..state, modules:)
}

fn sync_message(state, message) {
  let State(sync:, ..) = state
  let before = sync.cache.fragments
  let #(sync, actions) = client.update(sync, message)
  let actions = list.map(actions, SyncAction)
  let before = set.from_list(dict.keys(before))
  let after = set.from_list(dict.keys(sync.cache.fragments))
  let diff = set.difference(after, before)
  let repl = buffer.add_references(state.repl, diff, typing_context(sync.cache))

  let state = State(..state, sync:, repl:)
  #(state, actions)
}
