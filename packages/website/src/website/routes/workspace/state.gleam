import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/block
import eyg/interpreter/state as istate
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import morph/analysis
import morph/editable as e
import morph/input
import morph/picker
import morph/projection as p
import multiformats/cid/v1
import multiformats/hashes
import ogre/origin
import plinth/browser/file_system
import plinth/browser/message_event
import plinth/browser/window_proxy
import website/components/readonly
import website/components/runner
import website/components/shell
import website/components/snippet
import website/config
import website/harness/browser
import website/harness/harness
import website/manipulation
import website/routes/workspace/buffer.{type Buffer}
import website/run

pub type State {
  State(
    origin: origin.Origin,
    mode: Mode,
    user_error: Option(snippet.Failure),
    focused: Target,
    previous: List(shell.ShellEntry),
    after: Option(p.Projection),
    scope: List(#(String, istate.Value(Meta))),
    repl: Buffer,
    modules: Dict(Filename, Buffer),
    mounted_directory: Option(file_system.DirectoryHandle),
    flush_counter: Int,
    dirty: Dict(Filename, Nil),
    context: run.Context(Message),
  )
}

pub type Mode {
  Editing
  Manipulating(manipulation.UserInput)
  // Only the shell is ever run
  // Once the run finishes the input is reset and running return
  RunningShell(
    occured: List(#(String, #(istate.Value(Meta), istate.Value(Meta)))),
    status: run.Run(#(Option(istate.Value(Meta)), runner.Scope(Meta))),
  )
  WritingToClipboard
  ReadingFromClipboard(rebuild: Rebuild(e.Expression))
  SigningPayload(popup: Option(window_proxy.WindowProxy), payload: String)
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
  List(Int)

/// helper to make a context from a state, when a state exists
/// In not all cases does this exist
/// Cant take ctx from state as sync messages or other might not be focused
fn ctx(state, target) {
  let State(modules:, scope:, ..) = state
  case target {
    Repl -> repl_context(scope, modules)
    Module(_) -> module_context(scope, modules)
  }
}

pub fn repl_context(
  scope: List(#(String, istate.Value(Meta))),
  modules: Dict(Filename, Buffer),
) -> infer.Context {
  module_context(scope, modules)
  |> infer.with_effects(harness.types(harness.effects()))
}

fn module_context(
  scope: List(#(String, istate.Value(Meta))),
  modules: Dict(Filename, Buffer),
) {
  let #(bindings, tenv) = analysis.env_to_tenv(scope, [])
  let relative =
    dict.to_list(modules)
    |> list.filter_map(fn(entry) {
      let #(#(name, ext), buffer) = entry

      case ext {
        EygJson -> Ok(#(relative_cid(name), infer.poly_type(buffer.analysis)))
      }
    })
    |> dict.from_list()
  let references = dict.merge(relative, dict.new())
  // TODO use a helper in infer that can accept this env to tenv environment 
  // but it requires moving the function out of morph analysis
  // infer.pure()
  infer.Context(tenv, t.Empty, dict.new(), 1, bindings)
  |> infer.with_references(references)
}

/// This is a fake hash that is used to lookup specifically in the case of relative dependencies.
/// Publishing code with this reference will fail
pub fn relative_cid(name) {
  v1.Cid(297, hashes.Multihash(hashes.Sha256, <<{ "./" <> name }:utf8>>))
}

/// replaces buffer in the tree
fn replace_buffer(state: State, gen) {
  let buffer = gen(ctx(state, state.focused))
  let state = set_buffer(state, buffer)
  let cids = infer.missing_references(buffer.analysis)

  // let actions = list.map(actions, SyncAction)
  echo "todo "
  let actions = []

  case state.focused {
    Repl -> #(state, actions)
    Module(filename) -> {
      let flush_counter = state.flush_counter + 1
      let actions = [
        todo as "set timer",
        // SetFlushTimer(flush_counter)
      ]
      let dirty = dict.insert(state.dirty, filename, Nil)
      let state = State(..state, flush_counter:, dirty:)
      #(state, actions)
    }
  }
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

pub fn init(config: config.Config) -> #(State, List(browser.Effect(Message))) {
  let config.Config(origin:) = config
  let context =
    run.empty(EffectHandled, SpotlessConnectCompleted, ModuleLookupCompleted)

  let actions = []
  let scope = []
  let modules = dict.new()
  let state =
    State(
      origin:,
      mode: Editing,
      user_error: None,
      focused: Repl,
      previous: [],
      after: None,
      scope:,
      repl: buffer.empty(repl_context(scope, modules)),
      modules:,
      mounted_directory: None,
      flush_counter: 0,
      dirty: dict.new(),
      context:,
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
        _ -> buffer.empty(ctx(state, focused))
      }
  }
}

pub type Message {
  // snippet render_project doesn't include any event handling
  // actual_render_project sets up events based off attributes on the html
  // I think you need an autofocus to use normal tabs, which snippet does
  // 
  // This event assumes you are in command mode somewhere
  UserPressedCommandKey(key: String)
  // window received message event.
  // Could be from any source so is passed into the application as is.
  WindowReceivedMessageEvent(event: message_event.MessageEvent)
  // This is used for when a user clicks on an error message
  UserClickedOnPathReference(reversed: List(Int))
  UserClickedOnModule(filename: Filename)
  InputMessage(input.Message)
  ClipboardReadCompleted(Result(String, String))
  ClipboardWriteCompleted(Result(Nil, String))
  PreviousMessage(Int, readonly.Message)
  UserSelectedPrevious(Int)
  PickerMessage(picker.Message)
  ShowDirectoryPickerCompleted(
    Result(file_system.Handle(file_system.D), String),
  )
  LoadedFiles(
    Result(List(#(Filename, Result(ir.Node(Nil), json.DecodeError))), String),
  )
  FlushTimeout(reference: Int)
  OpenPopupCompleted(Result(window_proxy.WindowProxy, String))
  Ignore
  EffectHandled(task_id: Int, value: istate.Value(Meta))
  SpotlessConnectCompleted(harness.Service, Result(String, String))
  ModuleLookupCompleted(v1.Cid, Result(ir.Node(Nil), String))
}

pub fn update(state: State, message) -> #(State, List(browser.Effect(Message))) {
  case message {
    UserPressedCommandKey(key:) -> user_pressed_key(state, key)
    WindowReceivedMessageEvent(event:) ->
      window_received_message_event(state, event)
    UserClickedOnPathReference(reversed:) ->
      user_clicked_on_path_reference(state, reversed)
    UserClickedOnModule(filename:) -> user_clicked_on_module(state, filename)
    InputMessage(message) -> input_message(state, message)
    ClipboardReadCompleted(result) -> clipboard_read_complete(state, result)
    ClipboardWriteCompleted(result) -> clipboard_write_complete(state, result)
    PreviousMessage(_, _) -> #(state, [])
    UserSelectedPrevious(_) -> #(state, [])
    PickerMessage(message) -> picker_message(state, message)
    ShowDirectoryPickerCompleted(result) ->
      link_filesystem_completed(state, result)
    LoadedFiles(results) -> loaded_files(state, results)
    FlushTimeout(reference) -> flush_timeout(state, reference)
    OpenPopupCompleted(result) -> open_popup_completed(state, result)
    Ignore -> #(state, [])
    EffectHandled(task_id: tid, value:) ->
      case state.mode {
        RunningShell(_occured, run.Handling(task_id:, env:, k:))
          if tid == task_id
        ->
          block.resume(value, env, k)
          |> loop(state)
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
      // use the completed cid not the looked up cid as dependencies might have resolved
      case state.mode {
        RunningShell(occured, run.Fetching(module:, env:, k:)) ->
          case list.key_find(done, module) {
            Ok(Ok(value)) -> {
              let #(run, context, inner_effects) =
                block.resume(value, env, k)
                |> run.loop(context, block.resume)
              let mode = RunningShell(occured, run)
              #(
                State(..state, context:, mode:),
                list.append(effects, inner_effects),
              )
            }
            // If the module is a bad one the running state stays the same. it's up for the view to render the status
            Ok(Error(_)) -> #(State(..state, context:), effects)
            Error(Nil) -> #(State(..state, context:), effects)
          }
        _ -> #(State(..state, context:), effects)
      }
    }
  }
}

fn loop(return, state) {
  let occured = []
  let State(context:, ..) = state
  let #(run, context, effects) = run.loop(return, context, block.resume)
  let state = case run {
    run.Concluded(#(value, scope)) -> {
      // Type is shell entry
      let entry =
        shell.Executed(
          value:,
          effects: list.reverse([]),
          source: readonly.new(p.rebuild(state.repl.projection)),
        )
      let previous = [entry, ..state.previous]

      let repl = buffer.empty(ctx(State(..state, scope:), Repl))
      State(..state, mode: Editing, previous:, scope:, repl:)
    }
    _ -> {
      let mode = RunningShell(occured, run)
      State(..state, context:, mode:)
    }
  }
  #(state, effects)
}

fn user_pressed_key(state, key) {
  let State(mode:, ..) = state
  case mode, key {
    Editing, _ -> user_pressed_command_key(state, key)
    RunningShell(..), "Escape" -> #(State(..state, mode: Editing), [])
    // TODO reinstate
    // RunningShell(awaiting: None, ..), _ ->
    //   user_pressed_command_key(State(..state, mode: Editing), key)
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
    "ArrowDown" -> move_down(state)
    "Q" -> link_filesystem(state)
    "q" -> edit(state, manipulation.choose_module(state.modules))
    "w" -> edit(state, manipulation.call_with())
    "E" -> edit(state, manipulation.assign_before())
    "e" -> edit(state, manipulation.assign())
    "R" -> edit(state, manipulation.create_empty_record())
    "r" -> edit(state, manipulation.create_record())
    "t" -> edit(state, manipulation.insert_tag())
    "y" -> copy(state)
    "Y" -> paste(state)
    // TODO mode is authenticating
    // you won't see much on the front page
    "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
      browser.OpenPopup("/sign", resume: OpenPopupCompleted),
    ])
    "i" -> edit(state, manipulation.insert())
    "o" -> edit(state, manipulation.overwrite())
    "p" -> edit(state, manipulation.perform())
    "a" -> navigate(state, "increase selection", buffer.increase)
    "s" -> edit(state, manipulation.insert_string())
    "d" -> edit(state, manipulation.delete())
    "f" -> edit(state, manipulation.insert_function())
    "g" -> edit(state, manipulation.select_field())
    "h" -> edit(state, manipulation.insert_handle())
    "j" -> edit(state, manipulation.insert_builtin())
    "k" -> navigate(state, "toggle", buffer.toggle_open)
    "L" -> edit(state, manipulation.create_empty_list())
    "l" -> edit(state, manipulation.create_list())
    "@" -> edit(state, manipulation.choose_release())
    "#" -> edit(state, manipulation.insert_reference())
    "Z" -> edit(state, manipulation.redo())
    "z" -> edit(state, manipulation.undo())
    "x" -> edit(state, manipulation.spread())
    "c" -> edit(state, manipulation.call_function())
    "C" -> edit(state, manipulation.call_once())
    "b" -> edit(state, manipulation.insert_binary())
    "n" -> edit(state, manipulation.insert_integer())
    "m" -> edit(state, manipulation.insert_case())
    "v" -> edit(state, manipulation.insert_variable())
    "<" -> edit(state, manipulation.insert_before())
    ">" -> edit(state, manipulation.insert_after())
    "Enter" -> confirm(state)
    " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    _ -> #(State(..state, user_error: Some(snippet.NoKeyBinding(key))), [])
  }
}

fn user_clicked_on_path_reference(state, reversed) {
  navigate(state, "jump to", buffer.focus_at_reversed(_, reversed))
}

fn user_clicked_on_module(state, filename) {
  #(State(..state, mode: Editing, focused: Module(filename)), [])
}

fn navigate(state, name, func) {
  case func(active(state)) {
    Ok(gen) -> #(set_buffer(state, gen), [])
    Error(_) -> fail(state, name)
  }
}

fn edit(state, operation) {
  let manipulation.Operation(name:, apply:) = operation
  case apply(active(state)) {
    Ok(manipulation.Resolved(gen)) -> replace_buffer(state, gen)
    Ok(manipulation.UserInput(input)) -> {
      let mode = Manipulating(input)
      let state = State(..state, mode:)
      #(state, [])
    }

    Error(Nil) -> fail(state, name)
  }
}

fn move_up(state) {
  let buffer = active(state)
  case buffer.up(buffer) {
    Ok(new) -> {
      #(set_buffer(state, new), [])
    }
    Error(Nil) ->
      case state.focused == Repl, state.previous, state.after {
        True, [entry, ..], None -> {
          let repl =
            buffer.from_projection(entry.source.projection, ctx(state, Repl))
          #(State(..state, repl:, after: Some(state.repl.projection)), [])
        }
        _, _, _ -> fail(state, "move above")
      }
  }
}

fn move_down(state) {
  let buffer = active(state)
  case buffer.down(buffer) {
    Ok(new) -> {
      #(set_buffer(state, new), [])
    }
    Error(Nil) ->
      case state.focused == Repl, state.after {
        True, Some(projection) -> {
          let repl = buffer.from_projection(projection, ctx(state, Repl))
          #(State(..state, repl:, after: None), [])
        }
        _, _ -> fail(state, "move below")
      }
  }
}

fn copy(state) {
  let buffer = active(state)
  case buffer.projection {
    #(p.Exp(expression), _) -> {
      let text =
        e.to_annotated(expression, [])
        |> dag_json.to_string

      let state = State(..state, mode: WritingToClipboard)
      #(state, [
        browser.WriteToClipboard(text:, resume: ClipboardWriteCompleted),
      ])
    }
    _ -> fail(state, "copy")
  }
}

fn paste(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.set_expression(buffer), state, "paste")
  #(State(..state, mode: ReadingFromClipboard(rebuild:)), [
    browser.ReadFromClipboard(resume: ClipboardReadCompleted),
  ])
}

fn state_fail(state, action) {
  State(..state, user_error: Some(snippet.ActionFailed(action)))
}

fn fail(state, action) {
  let state = state_fail(state, action)
  #(state, [])
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
      state.repl.projection
      |> p.rebuild()
      |> e.to_annotated([])
      |> block.execute(state.scope)
      |> loop(state)
    }
    _ -> fail(state, "Can't execute module")
  }
}

// TODO test with sign effect
fn window_received_message_event(state, event) {
  let State(mode:, ..) = state
  case mode {
    SigningPayload(popup: Some(target), payload: _) -> {
      // wallet protocol
      let assert Ok(exchange) =
        decode.run(message_event.data(event), {
          use type_ <- decode.field("type", decode.string)
          case type_ {
            "get_payload" -> {
              use exchange <- decode.field("exchange", decode.string)
              echo exchange
              decode.success(exchange)
            }
            _ -> decode.failure("", "type")
          }
        })
      echo exchange
      #(state, [
        browser.PostMessage(
          target:,
          payload: json.object([
            #("type", json.string("payload")),
            #("exchange", json.string(exchange)),
            #("payload", json.object([#("foo", json.string("123"))])),
          ]),
          resume: fn(_: Nil) { Ignore },
        ),
      ])
    }
    _ -> {
      echo "unexpected mode"
      #(state, [])
    }
  }
}

fn link_filesystem(state) {
  #(state, [browser.ShowDirectoryPicker(resume: ShowDirectoryPickerCompleted)])
}

fn link_filesystem_completed(state, result) {
  use dir_handle <- try(result, state, "link filesystem")
  #(State(..state, mounted_directory: Some(dir_handle)), [
    browser.LoadFiles(dir_handle),
  ])
}

fn loaded_files(state: State, result) {
  use files <- try(result, state, "load files")

  let modules =
    list.filter_map(files, fn(file) {
      let #(name, code) = file
      use source <- result.map(code)

      let buffer =
        buffer.from_source(source, module_context(state.scope, state.modules))
      #(name, buffer)
    })
  let modules = dict.from_list(modules)
  #(State(..state, modules:), [])
}

fn flush_timeout(state, reference) {
  let State(mounted_directory:, flush_counter:, ..) = state
  case flush_counter == reference, mounted_directory {
    True, Some(handle) -> {
      // mark as not dirty so that if changes are made while saving they are captured.
      // if saving fails they are returned to dirty
      let actions =
        list.filter_map(dict.keys(state.dirty), fn(filename) {
          use buffer <- result.map(dict.get(state.modules, filename))
          let filename = todo
          let content = todo
          browser.SaveFile(handle:, filename:, content:, resume: fn(_) {
            Ignore
          })
        })
      let state = State(..state, dirty: dict.new())
      #(state, actions)
    }
    True, None -> {
      let state = State(..state, dirty: dict.new())
      #(state, [])
    }
    False, _ -> #(state, [])
  }
}

fn input_message(state, message) {
  let State(mode:, ..) = state
  case mode {
    Manipulating(manipulation.EnterInteger(value, rebuild)) ->
      case input.update_number(value, message) {
        input.Continue(new) -> {
          let mode = Manipulating(manipulation.EnterInteger(new, rebuild))
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
    Manipulating(manipulation.EnterText(value, rebuild)) ->
      case input.update_text(value, message) {
        input.Continue(new) -> {
          let mode = Manipulating(manipulation.EnterText(new, rebuild))
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

    _ -> #(state, [])
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

fn picker_message(state, message) {
  let State(mode:, ..) = state
  case mode {
    Manipulating(manipulation.PickSingle(_, rebuild)) ->
      case message {
        picker.Updated(picker:) -> #(
          State(
            ..state,
            mode: Manipulating(manipulation.PickSingle(picker, rebuild)),
          ),
          [],
        )
        picker.Decided(label) -> {
          State(..state, mode: Editing)
          |> replace_buffer(rebuild(label, _))
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }
    // ChoosingPackage(rebuild:, ..) ->
    //   case message {
    //     picker.Updated(picker:) -> #(
    //       State(..state, mode: ChoosingPackage(picker:, rebuild:)),
    //       [],
    //     )
    //     picker.Decided(label) -> {
    //       case dict.get(todo, label) {
    //         Ok(cache.Release(package:, version:, module:)) ->
    //           State(..state, mode: Editing)
    //           |> replace_buffer(rebuild(#(package, version, module), _))
    //         Error(Nil) -> #(
    //           State(
    //             ..state,
    //             user_error: Some(snippet.ActionFailed("choose package")),
    //           ),
    //           [],
    //         )
    //       }
    //     }
    //     picker.Dismissed -> #(State(..state, mode: Editing), [])
    //   }
    // ChoosingModule(rebuild:, ..) ->
    //   case message {
    //     picker.Updated(picker:) -> #(
    //       State(..state, mode: ChoosingModule(picker:, rebuild:)),
    //       [],
    //     )
    //     picker.Decided(label) -> {
    //       State(..state, mode: Editing)
    //       |> replace_buffer(rebuild(#("./" <> label, 0, relative_cid(label)), _))
    //     }
    //     picker.Dismissed -> #(State(..state, mode: Editing), [])
    //   }
    _ -> #(state, [])
  }
}

fn open_popup_completed(state: State, result) {
  let State(mode:, ..) = state
  case mode {
    SigningPayload(payload:, ..) ->
      case result {
        Ok(popup) -> {
          let mode = SigningPayload(popup: Some(popup), payload:)
          let state = State(..state, mode:)
          #(state, [])
        }
        _ -> {
          echo "failed to open popup"
          #(state, [])
        }
      }
    _ -> {
      echo "unexpected mode"
      #(state, [])
    }
  }
}
