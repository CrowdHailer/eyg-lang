import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/cast
import eyg/interpreter/expression
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
import gleam/string
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
    scope: List(#(String, istate.Value(Meta))),
    repl: Buffer,
    modules: Dict(String, Buffer),
    sync: client.Client,
  )
}

pub type Meta =
  Nil

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

/// helper to make a context from a state, when a state exists
/// In not all cases does this exist
fn ctx(state) {
  let State(modules:, scope:, sync:, ..) = state
  typing_context(scope, modules, sync.cache)
}

fn typing_context(
  scope: List(#(String, istate.Value(Meta))),
  modules: Dict(String, Buffer),
  cache: cache.Cache,
) {
  let #(bindings, tenv) = analysis.env_to_tenv(scope, Nil)
  let relative =
    dict.to_list(modules)
    |> list.filter_map(fn(entry) {
      let #(path, buffer) = entry
      use #(_name, rest) <- result.try(string.split_once(path, ".eyg.json"))
      case rest {
        "" -> {
          // name is only when we check the refs
          // "./" <> name
          Ok(#(buffer.cid(buffer), infer.poly_type(buffer.analysis)))
        }
        _ -> Error(Nil)
      }
    })
    |> dict.from_list()
  let references = dict.merge(relative, cache.type_map(cache))
  // TODO use a helper in infer that can accept this env to tenv environment 
  // but it requires moving the function out of morph analysis
  // infer.pure()
  infer.Context(tenv, t.Empty, dict.new(), 1, bindings)
  |> infer.with_references(references)
}

/// Always used after a change that was from a command and that changes the history
/// The new value is the full projection, probably from a rebuild function
fn update_projection(state, new) {
  let buffer = buffer.update_code(active(state), new, ctx(state))

  State(..state, mode: Editing)
  |> replace_buffer(buffer)
}

/// replaces buffer in the tree
fn replace_buffer(state: State, buffer) {
  let State(focused:, modules:, ..) = state
  let state = case focused {
    Repl -> State(..state, repl: buffer)
    Module(path) -> {
      let modules = dict.insert(modules, path, buffer)
      State(..state, modules:)
    }
  }
  let cids = infer.missing_references(buffer.analysis)
  let #(sync, actions) = client.fetch_fragments(state.sync, cids)
  let actions = list.map(actions, SyncAction)
  let state = State(..state, sync:)
  #(state, actions)
}

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
    awaiting: Option(Int),
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
  let scope = []
  let modules = dict.new()
  let state =
    State(
      sync:,
      mode: Editing,
      user_error: None,
      focused: Repl,
      previous: [],
      scope:,
      repl: buffer.empty(typing_context(scope, modules, sync.cache)),
      modules:,
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
        _ -> buffer.empty(ctx(state))
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
  PreviousMessage(Int, readonly.Message)
  UserSelectedPrevious(Int)
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
    PreviousMessage(_, _) -> #(state, [])
    UserSelectedPrevious(_) -> #(state, [])
    PickerMessage(message) -> picker_message(state, message)
    SyncMessage(message) -> sync_message(state, message)
  }
}

fn user_pressed_key(state, key) {
  let State(mode:, ..) = state
  case mode, key {
    Editing, _ -> user_pressed_command_key(state, key)
    RunningShell(..), "Escape" -> #(State(..state, mode: Editing), [])
    RunningShell(awaiting: None, ..), _ -> user_pressed_command_key(state, key)
    _, _ -> {
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
    "R" -> place(state, "create record", e.Record([], None))
    "t" -> insert_tag(state)
    "y" -> copy(state)
    "Y" -> paste(state)
    "p" -> perform(state)
    "a" -> nav(state, navigation.increase, "increase selection")
    "s" -> insert_string(state)
    "d" -> transform(state, "delete", transformation.delete)
    "g" -> select_field(state)
    "j" -> insert_builtin(state)
    "L" -> place(state, "create list", e.List([], None))
    "@" -> choose_release(state)
    "#" -> insert_reference(state)
    // choose release just checks is expression
    "Z" -> map_buffer(state, "redo", buffer.redo)
    "z" -> map_buffer(state, "undo", buffer.undo)
    "n" -> insert_integer(state)
    "m" -> insert_case(state)
    "v" -> insert_variable(state)
    "Enter" -> confirm(state)
    " " -> search_vacant(state)
    _ -> #(State(..state, user_error: Some(snippet.NoKeyBinding(key))), [])
  }
}

fn place(state, name, new) {
  transform(state, name, fn(projection) {
    case projection {
      #(p.Exp(_), zoom) -> Ok(#(p.Exp(new), zoom))
      _ -> Error(Nil)
    }
  })
}

fn transform(state, name, func) {
  case func(active(state).projection) {
    Ok(projection) -> update_projection(state, projection)
    Error(Nil) -> fail(state, name)
  }
}

fn nav(state, navigation: fn(p.Projection) -> Result(_, _), reason) {
  case navigation(active(state).projection) {
    Ok(projection) -> {
      let buffer = buffer.update_position(state.repl, projection)
      replace_buffer(state, buffer)
    }
    Error(_) -> fail(state, reason)
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
      replace_buffer(state, buffer)
    }
    Error(Nil) ->
      case state.focused == Repl, state.previous {
        True, [entry, ..] -> {
          let repl = buffer.from_projection(entry.source.projection, ctx(state))
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

fn assign_to(state) {
  let buffer = active(state)
  let action = transformation.assign_before(buffer.projection)
  use rebuild <- try(action, state, "assign")
  let rebuild = fn(s) { rebuild(e.Bind(s)) }
  let state = State(..state, mode: Picking(picker.new("", []), rebuild))
  #(state, [FocusOnInput])
}

fn insert_tag(state) {
  let buffer = active(state)
  let action = transformation.tag(buffer.projection)
  use rebuild <- try(action, state, "tag")
  let hints = case buffer.target_type(buffer) {
    Ok(t.Union(variants)) -> {
      analysis.rows(variants)
      |> listx.value_map(debug.mono)
    }
    _ -> []
  }
  let state = State(..state, mode: Picking(picker.new("", hints), rebuild))
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
  let action = transformation.perform(buffer.projection)
  use rebuild <- try(action, state, "perform")
  let hints =
    browser.lookup()
    |> list.map(fn(effect) {
      let #(key, #(types, _)) = effect
      #(key, snippet.render_effect(types))
    })

  #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
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
  // case buffer.projection {
  //   #(p.Exp(inner), zoom) -> {
  //     let rebuild = fn(label) { #(p.Exp(e.Select(inner, label)), zoom) }
  //     #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
  //   }
  //   _ -> todo
  // }

  pick_on_expression(state, "select field", hints, fn(label, inner, zoom) {
    #(p.Exp(e.Select(inner, label)), zoom)
  })
}

fn insert_builtin(state) {
  let hints = listx.value_map(infer.builtins(), snippet.render_poly)
  pick_on_expression(state, "insert builtin", hints, fn(label, _inner, zoom) {
    #(p.Exp(e.Builtin(label)), zoom)
  })
}

fn pick_on_expression(state, name, hints, f) {
  case active(state).projection {
    #(p.Exp(inner), zoom) -> {
      let rebuild = fn(label) { f(label, inner, zoom) }
      #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
    }
    _ -> fail(state, name)
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
      let #(state, actions) = set_expression(state, release)
      #(state, [FocusOnInput, ..actions])
    }

    _ -> #(state, [])
  }
}

fn insert_reference(state) {
  let buffer = active(state)
  let action = action.insert_reference(buffer.projection)
  use #(current, rebuild) <- try(action, state, "insert reference")
  let mode = Picking(picker: picker.new(current, []), rebuild:)
  #(State(..state, mode:), [FocusOnInput])
}

fn map_buffer(state, name, f) {
  case f(active(state), ctx(state)) {
    Ok(buffer) -> replace_buffer(state, buffer)
    Error(Nil) -> fail(state, name)
  }
}

fn insert_integer(state) {
  let buffer = active(state)
  let action = transformation.integer(buffer.projection)
  use #(value, rebuild) <- try(action, state, "insert integer")
  #(State(..state, mode: EditingInteger(value:, rebuild:)), [FocusOnInput])
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
  case transformation.variable(buffer.projection) {
    Ok(rebuild) -> {
      #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
    }
    Error(Nil) -> fail(state, "insert variable")
  }
}

fn try(result, state, message, then) {
  case result {
    Ok(value) -> then(value)
    Error(_) -> fail(state, message)
  }
}

fn confirm(state) {
  let State(focused:, ..) = state
  case focused {
    Repl -> {
      let editable = p.rebuild(state.repl.projection)
      run(evaluate(editable, state.scope), [], state)
    }
    _ -> fail(state, "Can't execute module")
  }
}

fn evaluate(editable, scope) {
  e.to_annotated(editable, [])
  |> tree.clear_annotation()
  // TODO why do we clear this
  |> block.execute(scope)
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
      let repl = buffer.empty(ctx(State(..state, scope:)))
      let state = State(..state, mode: Editing, previous:, scope:, repl:)
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
            Error(reason) ->
              runner_stoped(state, occured, #(reason, meta, env, k))
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
                        State(
                          ..state,
                          mode: RunningShell(
                            occured:,
                            awaiting: Some(-11),
                            debug:,
                          ),
                        )
                      #(state, [RunEffect(effect)])
                    }
                  }
                Error(reason) ->
                  runner_stoped(state, occured, #(reason, meta, env, k))
              }
            Error(Nil) -> runner_stoped(state, occured, debug)
          }
        break.UndefinedReference(cid) ->
          case dict.get(state.sync.cache.fragments, cid) {
            Ok(cache.Fragment(value:, ..)) ->
              run(block.resume(value, env, k), occured, state)
            _ -> runner_stoped(state, occured, debug)
          }
        break.UndefinedRelease(package:, release: version, cid:) ->
          case package, version {
            "./" <> name, 0 ->
              case dict.get(state.modules, name <> ".eyg.json") {
                Ok(buffer) -> {
                  let source = e.to_annotated(p.rebuild(buffer.projection), [])
                  echo buffer.cid(buffer) == cid
                  // evaluate is for shell and expects a block and has effects
                  // evaluate(source,[])
                  let source = source |> tree.clear_annotation()
                  case expression.execute(source, []) {
                    Ok(value) ->
                      run(block.resume(value, env, k), occured, state)
                    _ -> todo
                  }
                }
                Error(Nil) -> todo
              }
            _, _ ->
              // These always return a value or an effect if working
              case dict.get(state.sync.cache.releases, #(package, version)) {
                Ok(release) if release.cid == cid ->
                  case dict.get(state.sync.cache.fragments, cid) {
                    Ok(cache.Fragment(value:, ..)) ->
                      run(block.resume(value, env, k), occured, state)
                    _ -> runner_stoped(state, occured, debug)
                  }
                Ok(_) -> todo
                Error(Nil) -> todo
              }
          }
        _ -> runner_stoped(state, occured, debug)
      }
    }
  }
}

fn runner_stoped(state, occured, debug) {
  #(State(..state, mode: RunningShell(occured:, awaiting: None, debug:)), [])
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
        input.Cancelled -> {
          let state = State(..state, mode: Editing)
          #(state, [])
        }
      }
    EditingText(value:, rebuild:), _ ->
      case input.update_text(value, message) {
        input.Continue(new) -> {
          let mode = EditingText(..mode, value: new)
          let state = State(..state, mode:)
          #(state, [])
        }
        input.Confirmed(value) -> update_projection(state, rebuild(value))
        input.Cancelled -> {
          let state = State(..state, mode: Editing)
          #(state, [])
        }
      }
    _, _ -> #(state, [])
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

            Error(_) -> fail(state, "paste")
          }
        Error(_) -> fail(state, "paste")
      }
    _ -> #(state, [])
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
        Error(_) -> fail(state, "copy")
      }
    _ -> #(state, [])
  }
}

fn effect_implementation_completed(state, reference, reply) {
  let State(mode:, ..) = state
  case mode {
    // put awaiting false for the fact it's no longer running
    RunningShell(
      occured:,
      awaiting:,
      debug: #(break.UnhandledEffect(label, lift), _meta, env, k),
    ) -> {
      // TODO check reference and awaiting match

      let occured = [#(label, #(lift, reply)), ..occured]
      run(block.resume(reply, env, k), occured, state)
    }
    _ -> #(state, [])
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
          update_projection(state, new)
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }
    _ -> #(state, [])
  }
}

/// Used for testing
pub fn replace_repl(state: State, new) {
  let repl = buffer.from_projection(new, ctx(state))
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
  let repl = buffer.add_references(state.repl, diff, ctx(State(..state, sync:)))

  let state = State(..state, sync:, repl:)
  #(state, actions)
}
