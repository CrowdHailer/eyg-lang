import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/state as istate
import eyg/ir/dag_json
import eyg/ir/tree as ir
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
import ogre/origin
import pal/platform/browser as platform
import pal/system
import plinth/browser/file_system
import plinth/browser/message_event
import plinth/browser/window_proxy
import spotless/oauth_2_1/token
import touch_grass/harness/browser as harness
import touch_grass/interface
import website/command
import website/config
import website/manipulation as m

pub type State {
  State(
    mode: Mode,
    user_error: Option(command.Failure),
    focused: Target,
    previous: List(Previous),
    after: Option(p.Projection),
    scope: List(#(String, istate.Value(Meta))),
    repl: Buffer,
    modules: Dict(Filename, Buffer),
    mounted_directory: Option(file_system.DirectoryHandle),
    flush_counter: Int,
    dirty: Dict(Filename, Nil),
    origin: origin.Origin,
    cache: cache.Cache(Meta),
    counter: Int,
  )
}

pub type EffectRecord =
  #(String, #(istate.Value(Meta), istate.Value(Meta)))

pub type Previous {
  Previous(
    value: Option(istate.Value(List(Int))),
    effects: List(EffectRecord),
    buffer: buffer.Buffer,
  )
}

// This run is different to a doc run, it doesn't have a success case
pub type Run {
  Exception(istate.Reason(Meta))
  Aborted(String)
  Handling(task_id: Int, env: istate.Env(Meta), k: istate.Stack(Meta))
  Blocked(dep: cache.Dependency, env: istate.Env(Meta), k: istate.Stack(Meta))
}

pub type Mode {
  Editing
  Manipulating(m.UserInput)
  // Only the shell is ever run
  // Once the run finishes the input is reset and running return
  RunningShell(occured: List(EffectRecord), status: Run)
  WritingToClipboard
  ReadingFromClipboard(rebuild: Rebuild(e.Expression))
  SigningPayload(popup: Option(window_proxy.WindowProxy), payload: String)
}

pub type Rebuild(t) =
  fn(t, infer.Context, dict.Dict(v1.Cid, binding.Poly)) -> Buffer

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
fn ctx(state: State, target: Target) -> infer.Context {
  let State(scope:, ..) = state
  case target {
    Repl -> repl_context(scope)
    Module(_) -> infer.pure()
  }
}

pub fn repl_context(
  scope: List(#(String, istate.Value(Meta))),
) -> infer.Context {
  let #(bindings, env) = analysis.env_to_tenv(scope, [])
  infer.Context(env:, eff: t.Empty, level: 0, bindings:)
  |> infer.with_effects(interface.types(harness.effects()))
}

/// This is a fake hash that is used to lookup specifically in the case of relative dependencies.
/// Publishing code with this reference will fail
pub fn relative_cid(name) {
  v1.Cid(297, hashes.Multihash(hashes.Sha256, <<{ "./" <> name }:utf8>>))
}

/// replaces buffer in the tree
fn replace_buffer(state: State, gen) {
  let buffer = gen(ctx(state, state.focused), cache.types(state.cache))
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

pub fn init(config: config.Config) -> #(State, List(system.Effect(Message))) {
  let config.Config(origin:) = config
  let cache = cache.ready()
  let #(cache, effects) = flush_cache(cache, origin)
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
      repl: buffer.empty(repl_context(scope), cache.types(cache)),
      modules:,
      mounted_directory: None,
      flush_counter: 0,
      dirty: dict.new(),
      origin:,
      cache:,
      counter: 0,
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

fn active(state) {
  let State(focused:, modules:, ..) = state
  case focused {
    Repl -> state.repl
    Module(path) ->
      case dict.get(modules, path) {
        Ok(buffer) -> buffer
        _ -> buffer.empty(ctx(state, focused), cache.types(state.cache))
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
  SpotlessConnectCompleted(harness.Service, Result(token.Response, String))
  CacheMessage(cache.ActionCompleted)
}

pub fn update(state: State, message) -> #(State, List(system.Effect(Message))) {
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
        RunningShell(_occured, Handling(task_id:, env:, k:)) if tid == task_id -> {
          let output =
            block.resume(value, env, k)
            |> loop(state)

          case output {
            Stop(value:, scope:) -> {
              let entry =
                Previous(value:, effects: list.reverse([]), buffer: state.repl)
              let previous = [entry, ..state.previous]

              let repl =
                buffer.empty(
                  ctx(State(..state, scope:), Repl),
                  cache.types(state.cache),
                )
              #(State(..state, mode: Editing, previous:, scope:, repl:), [])
            }
            Running(run, counter, effect) -> {
              let mode = RunningShell([], run)
              let effects = case effect {
                Some(effect) -> [effect]
                None -> []
              }
              #(State(..state, mode:, counter:), effects)
            }
          }
        }
        _ -> #(state, [])
      }
    SpotlessConnectCompleted(_service, _result) -> {
      fail(state, "Connect unsupported")
      // let #(context, effects) =
      //   run.connect_completed(state.context, service, result)
      // #(State(..state, context:), effects)
    }
    CacheMessage(message) -> {
      let #(cache, _done) = cache.update(state.cache, message, fn(_) { [] })
      let state = State(..state, cache:)
      // reanalyse modules
      case state.mode {
        RunningShell(occured: _, status:) -> {
          let output = restart(status, state)
          case output {
            Stop(value:, scope:) -> {
              let entry =
                Previous(value:, effects: list.reverse([]), buffer: state.repl)
              let previous = [entry, ..state.previous]

              let repl =
                buffer.empty(
                  ctx(State(..state, scope:), Repl),
                  cache.types(state.cache),
                )
              #(State(..state, mode: Editing, previous:, scope:, repl:), [])
            }
            Running(run, counter, effect) -> {
              let mode = RunningShell([], run)
              let effects = case effect {
                Some(effect) -> [effect]
                None -> []
              }
              #(State(..state, mode:, counter:), effects)
            }
          }
        }
        _ -> #(state, [])
      }
    }
  }
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
      system.OpenPopup("/sign", resume: fn(result) {
        system.Done(OpenPopupCompleted(result))
      }),
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
    "@" -> edit(state, m.choose_release(state.cache))
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
        True, [Previous(buffer: repl, ..), ..], None -> {
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
          let repl =
            buffer.from_projection(
              projection,
              ctx(state, Repl),
              cache.types(state.cache),
            )
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
        system.WriteToClipboard(text:, resume: fn(result) {
          system.Done(ClipboardWriteCompleted(result))
        }),
      ])
    }
    _ -> fail(state, "copy")
  }
}

fn paste(state) {
  let buffer = active(state)
  use rebuild <- try(buffer.set_expression(buffer), state, "paste")
  #(State(..state, mode: ReadingFromClipboard(rebuild:)), [
    system.ReadFromClipboard(resume: fn(result) {
      system.Done(ClipboardReadCompleted(result))
    }),
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

fn confirm(state: State) -> #(State, List(system.Effect(Message))) {
  let State(focused:, ..) = state
  case focused {
    Repl -> {
      let output =
        state.repl.projection
        |> p.rebuild()
        |> e.to_annotated([])
        |> block.execute(state.scope)
        |> loop(state)
      case output {
        Stop(value:, scope:) -> {
          let entry =
            Previous(value:, effects: list.reverse([]), buffer: state.repl)
          let previous = [entry, ..state.previous]

          let repl =
            buffer.empty(
              ctx(State(..state, scope:), Repl),
              cache.types(state.cache),
            )
          #(State(..state, mode: Editing, previous:, scope:, repl:), [])
        }
        Running(run, counter, effect) -> {
          let mode = RunningShell([], run)
          let effects = case effect {
            Some(effect) -> [effect]
            None -> []
          }
          #(State(..state, mode:, counter:), effects)
        }
      }
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
        system.PostMessage(
          target:,
          payload: json.object([
            #("type", json.string("payload")),
            #("exchange", json.string(exchange)),
            #("payload", json.object([#("foo", json.string("123"))])),
          ]),
          resume: fn(_: Nil) { system.Done(Ignore) },
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
  #(state, [
    system.ShowDirectoryPicker(resume: fn(result) {
      system.Done(ShowDirectoryPickerCompleted(result))
    }),
  ])
}

fn link_filesystem_completed(state, result) {
  use dir_handle <- try(result, state, "link filesystem")
  #(State(..state, mounted_directory: Some(dir_handle)), [
    // system.LoadFiles(dir_handle),
    panic as "unsupported",
  ])
}

fn loaded_files(state: State, result) {
  use files <- try(result, state, "load files")

  let modules =
    list.filter_map(files, fn(file) {
      let #(name, code) = file
      use source <- result.map(code)

      let buffer =
        buffer.from_source(source, infer.pure(), cache.types(state.cache))
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
          // system.SaveFile(handle:, filename:, content:, resume: fn(_) {
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
          |> replace_buffer(fn(context, refs) { rebuild(value, context, refs) })
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
          |> replace_buffer(fn(context, refs) { rebuild(value, context, refs) })
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
          case json.parse(text, dag_json.decoder(Nil)) {
            Ok(expression) ->
              State(..state, mode: Editing)
              |> replace_buffer(fn(context, refs) {
                rebuild(e.from_annotated(expression), context, refs)
              })

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
          |> replace_buffer(fn(context, refs) { rebuild(label, context, refs) })
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
              |> replace_buffer(fn(context, refs) {
                rebuild(cid, context, refs)
              })
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
          case cache.package(state.cache, text) {
            Ok(cache.Entry(version:, module:, ..)) ->
              State(..state, mode: Editing)
              |> replace_buffer(fn(context, refs) {
                rebuild(ir.Release(text, version, module), context, refs)
              })
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

/// loop is effectful, it is only ever invoked if the state is already RunningShell
/// This means loop handles completions being pushed into the proxy
fn loop(
  return: Result(#(Option(istate.Value(Meta)), List(_)), istate.Debug(Meta)),
  state: State,
) -> StopOrRunning {
  case return {
    Error(#(break.UnhandledEffect(label, lift), _meta, env, k)) -> {
      case platform.cast(label, lift) {
        Ok(effect) -> {
          case platform.extrinsic(effect) {
            platform.Work(system.Done(value)) -> {
              loop(block.resume(value, env, k), state)
            }
            platform.Work(effect) -> {
              let effect = system.map(effect, EffectHandled(state.counter, _))
              let run = Handling(state.counter, env, k)
              Running(run, state.counter + 1, Some(effect))
            }
            platform.Abort(reason) ->
              Running(Aborted(reason), state.counter, None)
            platform.Spotless(service: _, operation: _) ->
              Running(Aborted("unsupported"), state.counter, None)
          }
        }
        Error(reason) -> Running(Exception(reason), state.counter, None)
      }
    }
    Error(#(break.UndefinedReference(ir.Content(cid)), _, env, k)) ->
      case cache.get_module(state.cache, cid) {
        Ok(cache.Module(value:, ..)) -> loop(block.resume(value, env, k), state)
        // All dependencies are marked as blocked the view shows error vs running status
        Error(_) -> {
          let run = Blocked(cache.Content(cid), env, k)
          Running(run, state.counter, None)
        }
      }
    Error(#(break.UndefinedReference(ir.Pinned(release)), _, env, k)) -> {
      case cache.release_code(state.cache, release) {
        Ok(cache.Module(value:, ..)) -> loop(block.resume(value, env, k), state)
        _ -> {
          let run = Blocked(cache.Pinned(release), env, k)
          Running(run, state.counter, None)
        }
      }
    }
    Ok(#(value, scope)) -> {
      Stop(value, scope)
    }
    Error(#(reason, _, _, _)) -> Running(Exception(reason), state.counter, None)
  }
}

pub fn restart(run: Run, state: State) -> StopOrRunning {
  case run {
    Blocked(dep:, env:, k:) -> {
      let reason = cache.dep_to_reason(dep)
      let return = Error(#(reason, [], env, k))
      loop(return, state)
    }
    _ -> Running(run, state.counter, None)
  }
}

/// This is a bad name as running is in error cases
/// Really Stop means clear and push onto history
pub type StopOrRunning {
  Stop(value: Option(istate.Value(Meta)), scope: istate.Scope(Meta))
  Running(Run, Int, Option(system.Effect(Message)))
}
