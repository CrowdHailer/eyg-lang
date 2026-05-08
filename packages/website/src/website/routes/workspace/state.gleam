import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/hub/publisher
import eyg/hub/release
import eyg/hub/schema
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
import morph/buffer.{type Buffer}
import morph/editable as e
import morph/input
import morph/picker
import morph/projection as p
import multiformats/cid/v1
import multiformats/hashes
import plinth/browser/file_system
import plinth/browser/message_event
import plinth/browser/window_proxy
import website/command
import website/config
import website/harness/browser
import website/harness/harness
import website/manipulation as m
import website/run

pub type State {
  State(
    mode: Mode,
    user_error: Option(command.Failure),
    focused: Target,
    previous: List(run.Previous),
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
  Manipulating(m.UserInput)
  // Only the shell is ever run
  // Once the run finishes the input is reset and running return
  RunningShell(
    occured: List(#(String, #(istate.Value(Meta), istate.Value(Meta)))),
    status: run.Run(#(Option(istate.Value(Meta)), istate.Scope(Meta))),
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

  case state.focused {
    Repl -> #(state, [])
    Module(filename) -> {
      let flush_counter = state.flush_counter + 1
      echo "set timer"
      let actions = [
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
    run.empty(
      origin,
      EffectHandled,
      SpotlessConnectCompleted,
      ModuleLookupCompleted,
      PullPackagesCompleted,
    )
    |> run.pull()
  let #(context, effects) = run.flush(context)
  let scope = []
  let modules = dict.new()
  let state =
    State(
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
  #(state, effects)
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
  PreviousMessage(Int, List(Int))
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
  PullPackagesCompleted(Result(List(schema.ArchivedEntry), String))
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
    PreviousMessage(_, _) -> {
      // TODO clicked prvious
      echo "clicked previous"
      #(state, [])
    }
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
      let #(context, done) =
        run.get_module_completed(state.context, cid, result)
      // use the completed cid not the looked up cid as dependencies might have resolved
      let #(context, effects) = run.flush(context)
      case state.mode {
        RunningShell(occured, run.Pending(cache.Content(module), env:, k:)) -> {
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

fn loop(return, state) {
  let occured = []
  let State(context:, ..) = state
  let #(run, context, effects) = run.loop(return, context, block.resume)
  let state = case run {
    run.Concluded(#(value, scope)) -> {
      // Type is shell entry
      echo "todo effects"
      let entry =
        run.Previous(value:, effects: list.reverse([]), buffer: state.repl)
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
    "q" -> edit(state, m.choose_module(state.modules))
    "w" -> edit(state, m.call_with())
    "E" -> edit(state, m.assign_before())
    "e" -> edit(state, m.assign())
    "R" -> edit(state, m.create_empty_record())
    "r" -> edit(state, m.create_record())
    "t" -> edit(state, m.insert_tag())
    "y" -> copy(state)
    "Y" -> paste(state)
    // TODO mode is authenticating
    // you won't see much on the front page
    "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
      browser.OpenPopup("/sign", resume: OpenPopupCompleted),
    ])
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
    "@" -> edit(state, m.choose_release(state.context.cache))
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
    _ -> #(State(..state, user_error: Some(command.NoKeyBinding(key))), [])
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
  let m.Operation(name:, apply:) = operation
  case apply(active(state)) {
    Ok(m.Resolved(gen)) -> replace_buffer(state, gen)
    Ok(m.UserInput(input)) -> {
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
        True, [run.Previous(buffer: repl, ..), ..], None -> {
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
  State(..state, user_error: Some(command.ActionFailed(action)))
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
    True, Some(_handle) -> {
      // mark as not dirty so that if changes are made while saving they are captured.
      // if saving fails they are returned to dirty
      let actions =
        list.filter_map(dict.keys(state.dirty), fn(filename) {
          use _buffer <- result.map(dict.get(state.modules, filename))
          panic
          // let filename = 
          // let content = panic
          // browser.SaveFile(handle:, filename:, content:, resume: fn(_) {
          //   Ignore
          // })
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
    Manipulating(m.EnterInteger(value, rebuild)) ->
      case input.update_number(value, message) {
        input.Continue(new) -> {
          let mode = Manipulating(m.EnterInteger(new, rebuild))
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
    Manipulating(m.EnterText(value, rebuild)) ->
      case input.update_text(value, message) {
        input.Continue(new) -> {
          let mode = Manipulating(m.EnterText(new, rebuild))
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
    Manipulating(m.PickSingle(_, rebuild)) ->
      case message {
        picker.Updated(picker:) -> #(
          State(..state, mode: Manipulating(m.PickSingle(picker, rebuild))),
          [],
        )
        picker.Decided(label) -> {
          State(..state, mode: Editing)
          |> replace_buffer(rebuild(label, _))
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }
    Manipulating(m.PickCid(_picker, rebuild)) ->
      case message {
        picker.Updated(picker:) -> {
          let mode = Manipulating(m.PickCid(picker, rebuild))
          #(State(..state, mode:), [])
        }
        picker.Decided(text) -> {
          case v1.from_string(text) {
            Ok(#(cid, _)) ->
              State(..state, mode: Editing)
              |> replace_buffer(rebuild(cid, _))
            Error(_) -> {
              echo "need error message for bad cid"
              #(state, [])
            }
          }
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }

    Manipulating(m.PickRelease(_picker, rebuild)) ->
      case message {
        picker.Updated(picker:) -> {
          let mode = Manipulating(m.PickRelease(picker, rebuild))
          #(State(..state, mode:), [])
        }
        picker.Decided(text) -> {
          case cache.package(state.context.cache, text) {
            Ok(#(v, m)) ->
              State(..state, mode: Editing)
              |> replace_buffer(rebuild(#(text, v, m), _))
            Error(_) -> {
              echo "need error message for bad cid"
              #(state, [])
            }
          }
        }
        picker.Dismissed -> #(State(..state, mode: Editing), [])
      }
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
