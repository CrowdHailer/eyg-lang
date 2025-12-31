import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state as istate
import eyg/interpreter/value
import eyg/ir/dag_json
import eyg/ir/tree
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/http/request
import gleam/int
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/set
import gleam/string
import gleam/uri
import morph/analysis
import morph/editable as e
import morph/input
import morph/picker
import morph/projection as p
import website/components/readonly
import website/components/shell
import website/components/snippet
import website/config
import website/routes/workspace/buffer.{type Buffer}
import website/routes/workspace/effects
import website/sync/cache
import website/sync/client

pub type State {
  State(
    mode: Mode,
    user_error: Option(snippet.Failure),
    focused: Target,
    counter: Int,
    previous: List(shell.ShellEntry),
    scope: List(#(String, istate.Value(Meta))),
    repl: Buffer,
    modules: Dict(Filename, Buffer),
    sync: client.Client,
  )
}

pub type Mode {
  Editing
  // The Picker is still used as their is string input for fields,enums,variable
  Picking(picker: picker.Picker, rebuild: Rebuild(String))
  // The projection in the target keeps all the rebuild information, but can error
  EditingText(value: String, rebuild: Rebuild(String))
  EditingInteger(value: Int, rebuild: Rebuild(Int))
  ChoosingPackage(
    picker: picker.Picker,
    rebuild: Rebuild(#(String, Int, String)),
  )
  ChoosingModule(
    picker: picker.Picker,
    rebuild: Rebuild(#(String, Int, String)),
  )
  // Only the shell is ever run
  // Once the run finishes the input is reset and running return
  RunningShell(
    occured: List(#(String, #(istate.Value(Meta), istate.Value(Meta)))),
    awaiting: Option(Int),
    debug: istate.Debug(Meta),
  )
  WritingToClipboard
  ReadingFromClipboard(rebuild: Rebuild(e.Expression))
}

pub type Rebuild(t) =
  fn(t, infer.Context) -> Buffer

pub type Target {
  Repl
  Module(name: Filename)
}

pub type Filename =
  #(String, Ext)

pub type Ext {
  EygJson
}

pub type Meta =
  Nil

/// helper to make a context from a state, when a state exists
/// In not all cases does this exist
fn ctx(state) {
  let State(modules:, scope:, sync:, ..) = state
  typing_context(scope, modules, sync.cache)
}

fn typing_context(
  scope: List(#(String, istate.Value(Meta))),
  modules: Dict(Filename, Buffer),
  cache: cache.Cache,
) {
  let #(bindings, tenv) = analysis.env_to_tenv(scope, Nil)
  let relative =
    dict.to_list(modules)
    |> list.filter_map(fn(entry) {
      let #(#(name, ext), buffer) = entry

      case ext {
        EygJson -> {
          // name is only when we check the refs
          // "./" <> name
          Ok(#("./" <> name, infer.poly_type(buffer.analysis)))
        }
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
  let gen = buffer.update_code(active(state), new, _)

  State(..state, mode: Editing)
  |> replace_buffer(gen)
}

/// replaces buffer in the tree
fn replace_buffer(state: State, gen) {
  let buffer = gen(ctx(state))
  let state = set_buffer(state, buffer)
  let cids = infer.missing_references(buffer.analysis)
  let #(sync, actions) = client.fetch_fragments(state.sync, cids)
  let actions = list.map(actions, SyncAction)
  let state = State(..state, sync:)
  #(state, actions)
}

fn set_buffer(state, buffer) {
  let State(focused:, modules:, ..) = state
  case focused {
    Repl -> State(..state, repl: buffer)
    Module(path) -> {
      let modules = dict.insert(modules, path, buffer)
      State(..state, modules:)
    }
  }
}

pub type Action {
  FocusOnInput
  WriteToClipboard(text: String)
  ReadFromClipboard
  RunEffect(reference: Int, effect: Effect)
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
      counter: 0,
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
    RunningShell(awaiting: None, ..), _ ->
      user_pressed_command_key(State(..state, mode: Editing), key)
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
    "ArrowRight" -> navigate(state, "move right", buffer.next)
    "ArrowLeft" -> navigate(state, "move left", buffer.previous)
    "ArrowUp" -> move_up(state)
    "ArrowDown" -> navigate(state, "move below", buffer.down)
    "q" -> choose_module(state)
    "E" -> pick_any(state, "assign", buffer.assign_before)
    "e" -> pick_any(state, "assign", buffer.assign)
    "R" -> transform(state, "create record", buffer.create_empty_record)
    "r" -> create_record(state)
    "t" -> insert_tag(state)
    "y" -> copy(state)
    "Y" -> paste(state)
    // "u"
    "i" -> insert(state)
    "o" -> overwrite(state)
    "p" -> perform(state)
    "a" -> navigate(state, "increase selection", buffer.increase)
    "s" -> insert_string(state)
    "d" -> transform(state, "delete", buffer.delete)
    "f" -> pick_any(state, "insert function", buffer.insert_function)
    "g" -> select_field(state)
    // "h" -> 
    "j" -> insert_builtin(state)
    // "k"
    "L" -> transform(state, "create list", buffer.create_empty_list)
    "l" -> transform(state, "create list", buffer.create_list)
    "@" -> choose_release(state)
    "#" -> pick_any(state, "insert reference", buffer.insert_reference)
    // choose release just checks is expression
    "Z" -> map_buffer(state, "redo", buffer.redo)
    "z" -> map_buffer(state, "undo", buffer.undo)
    "x" -> transform(state, "spread", buffer.spread)
    "c" -> call_function(state)
    // "C" insert one
    "b" -> transform(state, "create list", buffer.insert_binary)
    "n" -> insert_integer(state)
    "m" -> insert_case(state)
    "v" -> insert_variable(state)
    "<" -> transform(state, "insert before", buffer.insert_before)
    ">" -> transform(state, "insert after", buffer.insert_after)
    "Enter" -> confirm(state)
    " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    _ -> #(State(..state, user_error: Some(snippet.NoKeyBinding(key))), [])
  }
}

fn navigate(state, name, func) {
  case func(active(state)) {
    Ok(gen) -> #(set_buffer(state, gen), [])
    Error(_) -> fail(state, name)
  }
}

fn transform(state, name, func) {
  case func(active(state)) {
    Ok(gen) -> replace_buffer(state, gen)
    Error(_) -> fail(state, name)
  }
}

/// pick from any value, i.e. the picker hints are empty
fn pick_any(state, name, action) {
  use rebuild <- try(action(active(state)), state, name)
  let state = State(..state, mode: Picking(picker.new("", []), rebuild))
  #(state, [FocusOnInput])
}

fn move_up(state) {
  let buffer = active(state)
  case buffer.up(buffer) {
    Ok(new) -> {
      #(set_buffer(state, new), [])
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

// If on something pick a field
// If not then go for all types
fn create_record(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.create_record(buffer), state, "record")
  let hints = case buffer.target_type(buffer) {
    Ok(t.Record(rows)) -> listx.value_map(analysis.rows(rows), debug.mono)
    _ -> []
  }
  case hints {
    [] -> {
      let state =
        State(
          ..state,
          mode: Picking(picker.new("", []), fn(label, context) {
            rebuild([label], context)
          }),
        )
      #(state, [FocusOnInput])
    }
    _ -> replace_buffer(state, rebuild(listx.keys(hints), _))
  }
}

fn overwrite(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.overwrite(buffer), state, "record")
  let hints = case buffer.target_type(buffer) {
    Ok(t.Record(rows)) -> listx.value_map(analysis.rows(rows), debug.mono)
    _ -> []
  }
  let state = State(..state, mode: Picking(picker.new("", hints), rebuild))
  #(state, [FocusOnInput])
}

fn insert_tag(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.tag(buffer), state, "tag")
  let hints = case buffer.target_type(buffer) {
    Ok(t.Union(variants)) ->
      listx.value_map(analysis.rows(variants), debug.mono)
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
  use rebuild <- try(buffer.set_expression(buffer), state, "paste")
  #(State(..state, mode: ReadingFromClipboard(rebuild:)), [ReadFromClipboard])
}

fn state_fail(state, action) {
  State(..state, user_error: Some(snippet.ActionFailed(action)))
}

fn fail(state, action) {
  let state = state_fail(state, action)
  #(state, [])
}

fn insert(state) {
  let buffer = active(state)
  use #(value, rebuild) <- try(buffer.insert(buffer), state, "insert")
  #(State(..state, mode: Picking(picker.new(value, []), rebuild:)), [
    FocusOnInput,
  ])
}

// wrap in an on expression
fn perform(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.perform(buffer), state, "perform")
  let hints =
    list.map(effects.types(), fn(effect) {
      let #(key, types) = effect
      #(key, snippet.render_effect(types))
    })

  #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
}

fn insert_string(state) {
  let action = buffer.insert_string(active(state))
  use #(value, rebuild) <- try(action, state, "insert string")
  #(State(..state, mode: EditingText(value:, rebuild:)), [FocusOnInput])
}

fn select_field(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.select_field(buffer), state, "select field")
  let hints = case buffer.target_type(buffer) {
    Ok(t.Record(rows)) -> listx.value_map(analysis.rows(rows), debug.mono)
    _ -> []
  }
  let mode = Picking(picker: picker.new("", hints), rebuild:)
  #(State(..state, mode:), [FocusOnInput])
}

fn insert_builtin(state) {
  let action = buffer.insert_builtin(active(state))
  use rebuild <- try(action, state, "insert builtin")
  let hints = listx.value_map(infer.builtins(), snippet.render_poly)
  let mode = Picking(picker: picker.new("", hints), rebuild:)
  #(State(..state, mode:), [FocusOnInput])
}

fn choose_module(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.insert_release(buffer), state, "insert release")
  let hints =
    list.map(dict.to_list(state.modules), fn(module) {
      let #(#(name, _ext), buffer) = module
      #(name, snippet.render_poly(infer.poly_type(buffer.analysis)))
    })

  let picker = picker.new("", hints)
  let state = State(..state, mode: ChoosingModule(picker:, rebuild:))
  #(state, [FocusOnInput])
}

fn choose_release(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.insert_release(buffer), state, "insert release")
  let hints =
    list.map(package_choice(state), fn(release) {
      let analysis.Release(package:, version:, ..) = release
      #(package, int.to_string(version))
    })

  let picker = picker.new("", hints)
  let state = State(..state, mode: ChoosingPackage(picker:, rebuild:))
  #(state, [FocusOnInput])
}

fn map_buffer(state, name, f) {
  case f(active(state)) {
    Ok(buffer) -> replace_buffer(state, buffer)
    Error(Nil) -> fail(state, name)
  }
}

fn call_function(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.call_many(buffer), state, "call function")
  let arity = buffer.target_arity(buffer) |> result.unwrap(1)
  replace_buffer(state, rebuild(arity, _))
}

fn insert_integer(state) {
  let action = buffer.insert_integer(active(state))
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
  use rebuild <- try(buffer.insert_variable(buffer), state, "insert variable")
  let scope = buffer.target_scope(buffer) |> result.unwrap([])
  let hints = listx.value_map(scope, snippet.render_poly)
  #(State(..state, mode: Picking(picker.new("", hints), rebuild:)), [])
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

pub type Effect {
  Alert(String)
  Copy(String)
  Download(#(String, BitArray))
  Fetch(request.Request(BitArray))
  Follow(uri.Uri)
  Geolocation
  Now
  Paste
  Prompt(message: String)
  Random(max: Int)
}

type EffectImplementation {
  Internal(state: State, reply: istate.Value(Meta))
  External(Effect)
}

fn run(return, occured, state: State) -> #(State, List(_)) {
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
        break.UnhandledEffect(label, input) ->
          case effects.cast(label, input) {
            Ok(effect) -> {
              case run_effect(effect, state) {
                Internal(state:, reply:) -> {
                  let return = block.resume(reply, env, k)
                  let occured = [#(label, #(input, reply))]
                  run(return, occured, state)
                }
                External(effect) -> {
                  let counter = state.counter + 1
                  let awaiting = Some(counter)
                  let mode = RunningShell(occured:, awaiting:, debug:)
                  let state = State(..state, counter:, mode:)
                  #(state, [RunEffect(counter, effect)])
                }
              }
            }
            Error(reason) ->
              runner_stoped(state, occured, #(reason, meta, env, k))
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
              case dict.get(state.modules, #(name, EygJson)) {
                Ok(buffer) -> {
                  let source = e.to_annotated(p.rebuild(buffer.projection), [])
                  // echo buffer.cid(buffer) == cid
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

/// This must stay in the state module as it assumes that having access to the state object is it's concurrency model
fn run_effect(effect, state: State) {
  case effect {
    // effects.Abort()
    effects.Alert(message) -> External(Alert(message))
    effects.Copy(message) -> External(Copy(message))
    effects.Download(file) -> External(Download(file))
    effects.Fetch(request) -> External(Fetch(request))
    effects.Follow(uri) -> External(Follow(uri))
    effects.Geolocation -> External(Geolocation)
    effects.Now -> External(Now)
    effects.Open(filename) -> {
      let reply = case string.contains(filename, ".") {
        True -> value.error(value.String("invalid module name"))
        False -> value.ok(value.Record(dict.new()))
      }
      let state = State(..state, focused: Module(#(filename, EygJson)))

      Internal(state:, reply:)
    }
    effects.Paste -> External(Paste)
    effects.Prompt(message) -> External(Prompt(message))
    effects.Random(max) -> External(Random(max))
    effects.ReadFile(file) -> {
      let reply = case string.split_once(file, ".eyg.json") {
        Ok(#(name, "")) ->
          case dict.get(state.modules, #(name, EygJson)) {
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
        _ -> value.error(value.String("No file"))
      }
      Internal(state:, reply:)
    }
  }
}

fn runner_stoped(state, occured, debug) {
  #(State(..state, mode: RunningShell(occured:, awaiting: None, debug:)), [])
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
        input.Confirmed(value) ->
          State(..state, mode: Editing)
          |> replace_buffer(rebuild(value, _))
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
        input.Confirmed(value) ->
          State(..state, mode: Editing)
          |> replace_buffer(rebuild(value, _))
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
    ReadingFromClipboard(rebuild) ->
      case return {
        Ok(text) ->
          case dag_json.from_block(bit_array.from_string(text)) {
            Ok(expression) ->
              State(..state, mode: Editing)
              |> replace_buffer(rebuild(e.from_annotated(expression), _))

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
    )
      if awaiting == Some(reference)
    -> {
      let occured = [#(label, #(lift, reply)), ..occured]
      run(block.resume(reply, env, k), occured, state)
    }
    _ -> #(state, [])
  }
}

fn picker_message(state, message) {
  let State(mode:, ..) = state
  case mode {
    Picking(rebuild:, ..) ->
      case message {
        picker.Updated(picker:) -> #(
          State(..state, mode: Picking(picker:, rebuild:)),
          [],
        )
        picker.Decided(label) -> {
          State(..state, mode: Editing)
          |> replace_buffer(rebuild(label, _))
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }
    ChoosingPackage(rebuild:, ..) ->
      case message {
        picker.Updated(picker:) -> #(
          State(..state, mode: ChoosingPackage(picker:, rebuild:)),
          [],
        )
        picker.Decided(label) -> {
          case dict.get(state.sync.cache.packages, label) {
            Ok(cache.Release(package_id:, version:, cid:, ..)) ->
              State(..state, mode: Editing)
              |> replace_buffer(rebuild(#(package_id, version, cid), _))
            Error(Nil) -> todo
          }
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }
    ChoosingModule(rebuild:, ..) ->
      case message {
        picker.Updated(picker:) -> #(
          State(..state, mode: ChoosingModule(picker:, rebuild:)),
          [],
        )
        picker.Decided(label) -> {
          State(..state, mode: Editing)
          |> replace_buffer(rebuild(#("./" <> label, 0, "./" <> label), _))
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
