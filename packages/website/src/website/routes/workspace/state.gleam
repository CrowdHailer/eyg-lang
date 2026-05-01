import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/state as istate
import eyg/ir/dag_json
import eyg/ir/tree
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/http/request
import gleam/int
import gleam/json
import gleam/list
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
import multiformats/cid/v1
import multiformats/hashes
import ogre/operation
import ogre/origin
import plinth/browser/file_system
import plinth/browser/message_event
import plinth/browser/window_proxy
import snag
import touch_grass/decode_json
import touch_grass/download
import touch_grass/flip
import touch_grass/print
import website/components/readonly
import website/components/shell
import website/components/snippet
import website/config
import website/harness/browser
import website/harness/harness
import website/manipulation
import website/routes/workspace/buffer.{type Buffer}
import website/sync/cache
import website/sync/client

pub type State {
  State(
    origin: origin.Origin,
    mode: Mode,
    user_error: Option(snippet.Failure),
    focused: Target,
    // The "Sequence ID" Pattern
    effect_counter: Int,
    previous: List(shell.ShellEntry),
    after: Option(p.Projection),
    scope: List(#(String, istate.Value(Meta))),
    repl: Buffer,
    modules: Dict(Filename, Buffer),
    mounted_directory: Option(file_system.DirectoryHandle),
    flush_counter: Int,
    dirty: Dict(Filename, Nil),
    sync: client.Client,
    tokens: dict.Dict(harness.Service, String),
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
    rebuild: Rebuild(#(String, Int, v1.Cid)),
  )
  ChoosingModule(
    picker: picker.Picker,
    rebuild: Rebuild(#(String, Int, v1.Cid)),
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
  Nil

/// helper to make a context from a state, when a state exists
/// In not all cases does this exist
/// Cant take ctx from state as sync messages or other might not be focused
fn ctx(state, target) {
  let State(modules:, scope:, sync:, ..) = state
  case target {
    Repl -> repl_context(scope, modules, sync.cache)
    Module(_) -> module_context(scope, modules, sync.cache)
  }
}

fn repl_context(
  scope: List(#(String, istate.Value(Meta))),
  modules: Dict(Filename, Buffer),
  cache: cache.Cache,
) {
  module_context(scope, modules, cache)
  |> infer.with_effects(harness.types(harness.effects()))
}

fn module_context(
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
        EygJson -> Ok(#(relative_cid(name), infer.poly_type(buffer.analysis)))
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
  let #(sync, actions) = client.fetch_fragments(state.sync, cids)
  // let actions = list.map(actions, SyncAction)
  echo "todo "
  let actions = []
  let state = State(..state, sync:)

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
  let #(sync, actions) = client.new(origin) |> client.sync()
  // let actions = list.map(actions, SyncAction)
  echo "todo need the sync actions"
  let actions = []
  let scope = []
  let modules = dict.new()
  let state =
    State(
      origin:,
      sync:,
      mode: Editing,
      user_error: None,
      focused: Repl,
      effect_counter: 0,
      previous: [],
      after: None,
      scope:,
      repl: buffer.empty(repl_context(scope, modules, sync.cache)),
      modules:,
      mounted_directory: None,
      flush_counter: 0,
      dirty: dict.new(),
      tokens: dict.new(),
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

fn package_choice(state) {
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
  // window received message event.
  // Could be from any source so is passed into the application as is.
  WindowReceivedMessageEvent(event: message_event.MessageEvent)
  // This is used for when a user clicks on an error message
  UserClickedOnPathReference(reversed: List(Int))
  UserClickedOnModule(filename: Filename)
  InputMessage(input.Message)
  ClipboardReadCompleted(Result(String, String))
  ClipboardWriteCompleted(Result(Nil, String))
  EffectImplementationCompleted(reference: Int, reply: istate.Value(Meta))
  PreviousMessage(Int, readonly.Message)
  UserSelectedPrevious(Int)
  PickerMessage(picker.Message)
  SyncMessage(client.Message)
  ShowDirectoryPickerCompleted(
    Result(file_system.Handle(file_system.D), String),
  )
  LoadedFiles(
    Result(List(#(Filename, Result(tree.Node(Nil), json.DecodeError))), String),
  )
  FlushTimeout(reference: Int)
  SpotlessConnected(
    reference: Int,
    service: harness.Service,
    result: Result(String, snag.Snag),
  )
  OpenPopupCompleted(Result(window_proxy.WindowProxy, String))
  Ignore
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
    EffectImplementationCompleted(reference:, reply:) ->
      effect_implementation_completed(state, reference, reply)
    PreviousMessage(_, _) -> #(state, [])
    UserSelectedPrevious(_) -> #(state, [])
    PickerMessage(message) -> picker_message(state, message)
    SyncMessage(message) -> sync_message(state, message)
    ShowDirectoryPickerCompleted(result) ->
      link_filesystem_completed(state, result)
    LoadedFiles(results) -> loaded_files(state, results)
    FlushTimeout(reference) -> flush_timeout(state, reference)
    SpotlessConnected(reference:, service:, result:) ->
      spotless_connected(state, reference, service, result)
    OpenPopupCompleted(result) -> open_popup_completed(state, result)
    Ignore -> #(state, [])
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
    "ArrowDown" -> move_down(state)
    "Q" -> link_filesystem(state)
    "q" -> choose_module(state)
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
    "@" -> choose_release(state)
    "#" -> insert_reference(state)
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
    Ok(manipulation.PickSingle(picker, rebuild)) -> {
      let state = State(..state, mode: Picking(picker, rebuild))
      #(state, [])
    }
    Ok(manipulation.EnterText(value, rebuild)) -> {
      let state = State(..state, mode: EditingText(value, rebuild))
      #(state, [])
    }
    Ok(manipulation.EnterInteger(value, rebuild)) -> {
      let state = State(..state, mode: EditingInteger(value, rebuild))
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
  #(state, [])
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
  #(state, [])
}

fn insert_reference(state) {
  use rebuild <- try(
    buffer.insert_reference(active(state)),
    state,
    "insert reference",
  )
  let rebuild = fn(cid, context) {
    let assert Ok(#(cid, _)) = v1.from_string(cid)
    rebuild(cid, context)
  }
  let state = State(..state, mode: Picking(picker.new("", []), rebuild))
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
  Download(download.Input)
  Fetch(request.Request(BitArray))

  Geolocation
  Now
  Paste
  Prompt(message: String)
  Random(max: Int)
  Visit(uri.Uri)
}

type EffectImplementation {
  Abort(String)
  Internal(state: State, reply: istate.Value(Meta))
  External(Effect)
  Spotless(service: harness.Service, operation: operation.Operation(BitArray))
}

/// Have tried normalise run and run_module (or extract to runner?)
/// resume is different based on expression/block also effects are different
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
      let repl = buffer.empty(ctx(State(..state, scope:), Repl))
      let state = State(..state, mode: Editing, previous:, scope:, repl:)
      #(state, [])
    }
    Error(debug) -> {
      let #(reason, meta, env, k) = debug
      case reason {
        // internal not part of browser
        break.UnhandledEffect(label, input) ->
          case harness.cast(label, input) {
            Ok(effect) -> {
              case run_effect(effect, state) {
                Abort(_message) ->
                  runner_stoped(state, occured, #(reason, meta, env, k))
                Internal(state:, reply:) -> {
                  let return = block.resume(reply, env, k)
                  let occured = [#(label, #(input, reply))]
                  run(return, occured, state)
                }
                External(effect) -> {
                  let effect_counter = state.effect_counter + 1
                  let awaiting = Some(effect_counter)
                  let mode = RunningShell(occured:, awaiting:, debug:)
                  let state = State(..state, effect_counter:, mode:)
                  #(state, [
                    todo as "need run effect",
                    // RunEffect(effect_counter, effect)
                  ])
                }
                Spotless(service:, operation:) -> {
                  case dict.get(state.tokens, service) {
                    Error(Nil) -> {
                      let effect_counter = state.effect_counter + 1
                      let awaiting = Some(effect_counter)
                      let mode = RunningShell(occured:, awaiting:, debug:)
                      let state = State(..state, effect_counter:, mode:)
                      #(state, [
                        todo as "needs to be follow",
                        // SpotlessConnect(
                      //   effect_counter:,
                      //   origin: state.origin,
                      //   service:,
                      // ),
                      ])
                    }
                    Ok(token) -> {
                      run_spotless_effect_with_token(
                        state,
                        occured,
                        debug,
                        service,
                        token,
                        operation,
                      )
                    }
                  }
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
        break.UndefinedRelease(package:, release: version, module:) ->
          case package, version {
            "./" <> name, 0 ->
              case dict.get(state.modules, #(name, EygJson)) {
                Ok(buffer) -> {
                  let source = e.to_annotated(p.rebuild(buffer.projection), [])
                  // echo buffer.module(buffer) == module
                  // evaluate is for shell and expects a block and has effects
                  // evaluate(source,[])
                  let source = source |> tree.clear_annotation()
                  case run_module(expression.execute(source, []), state) {
                    Ok(value) ->
                      run(block.resume(value, env, k), occured, state)
                    Error(debug) -> runner_stoped(state, occured, debug)
                  }
                }
                Error(Nil) -> runner_stoped(state, occured, debug)
              }
            _, _ ->
              // These always return a value or an effect if working
              case dict.get(state.sync.cache.releases, #(package, version)) {
                Ok(release) if release.module == module ->
                  case dict.get(state.sync.cache.fragments, module) {
                    Ok(cache.Fragment(value:, ..)) ->
                      run(block.resume(value, env, k), occured, state)
                    _ -> runner_stoped(state, occured, debug)
                  }
                Ok(_) -> runner_stoped(state, occured, debug)
                Error(Nil) -> runner_stoped(state, occured, debug)
              }
          }
        _ -> runner_stoped(state, occured, debug)
      }
    }
  }
}

fn run_spotless_effect_with_token(
  state: State,
  occured,
  debug,
  service: harness.Service,
  token: String,
  operation: operation.Operation(BitArray),
) {
  let service = harness.effect_label(service) |> string.lowercase
  let path = "/proxy/" <> service <> operation.path
  let origin = origin.https("spotless.run")

  let request =
    operation.to_request(operation, origin)
    |> request.set_path(path)
    |> request.set_header("authorization", "Bearer " <> token)

  let effect = Fetch(request)
  let effect_counter = state.effect_counter + 1
  let awaiting = Some(effect_counter)
  let mode = RunningShell(occured:, awaiting:, debug:)
  let state = State(..state, effect_counter:, mode:)
  #(state, [
    todo as "need run effect",
    // RunEffect(effect_counter, effect)
  ])
}

/// module has no effects, it can return functions with effects so no access to state for internal effects
fn run_module(
  return: Result(istate.Value(Meta), _),
  state: State,
) -> Result(_, _) {
  case return {
    Ok(value) -> Ok(value)
    Error(debug) -> {
      let #(reason, _meta, env, k) = debug
      case reason {
        break.UndefinedReference(cid) ->
          case dict.get(state.sync.cache.fragments, cid) {
            Ok(cache.Fragment(value:, ..)) ->
              run_module(expression.resume(value, env, k), state)
            _ -> Error(debug)
          }
        break.UndefinedRelease(package:, release: version, module:) ->
          case package, version {
            "./" <> name, 0 ->
              case dict.get(state.modules, #(name, EygJson)) {
                Ok(buffer) -> {
                  let source = e.to_annotated(p.rebuild(buffer.projection), [])
                  // echo buffer.module(buffer) == module
                  // evaluate is for shell and expects a block and has effects
                  // evaluate(source,[])
                  let source = source |> tree.clear_annotation()
                  case run_module(expression.execute(source, []), state) {
                    Ok(value) ->
                      run_module(expression.resume(value, env, k), state)
                    _ -> Error(debug)
                  }
                }
                Error(Nil) -> Error(debug)
              }
            _, _ ->
              // These always return a value or an effect if working
              case dict.get(state.sync.cache.releases, #(package, version)) {
                Ok(release) if release.module == module ->
                  case dict.get(state.sync.cache.fragments, module) {
                    Ok(cache.Fragment(value:, ..)) ->
                      run_module(expression.resume(value, env, k), state)
                    _ -> Error(debug)
                  }
                Ok(_) -> Error(debug)
                Error(Nil) -> Error(debug)
              }
          }
        _ -> Error(debug)
      }
    }
  }
}

/// This must stay in the state module as it assumes that having access to the state object is it's concurrency model
fn run_effect(effect, state: State) {
  case effect {
    harness.Abort(message) -> Abort(message)
    harness.Alert(message) -> External(Alert(message))
    harness.Copy(message) -> External(Copy(message))
    harness.DecodeJson(raw) -> Internal(state:, reply: decode_json.sync(raw))
    harness.Download(file) -> External(Download(file))
    harness.Fetch(request) -> External(Fetch(request))
    harness.Flip -> Internal(state:, reply: flip.encode(flip.sync()))

    // harness.Follow(uri) -> External(Follow(uri))
    // harness.Geolocation -> External(Geolocation)
    // harness.Now -> External(Now)
    // harness.Open(filename) -> {
    //   let reply = case string.contains(filename, ".") {
    //     True -> value.error(value.String("invalid module name"))
    //     False -> value.ok(value.Record(dict.new()))
    //   }
    //   let state = State(..state, focused: Module(#(filename, EygJson)))
    //   Internal(state:, reply:)
    // }
    harness.Paste -> External(Paste)
    harness.Print(message) ->
      Internal(state:, reply: print.encode(print.sync(message)))
    harness.Prompt(message) -> External(Prompt(message))
    harness.Random(max) -> External(Random(max))
    // harness.ReadFile(file) -> {
    //   let reply = case string.split_once(file, ".eyg.json") {
    //     Ok(#(name, "")) ->
    //       case dict.get(state.modules, #(name, EygJson)) {
    //         Ok(buffer) ->
    //           value.ok(
    //             value.Binary(
    //               dag_json.to_block(
    //                 e.to_annotated(p.rebuild(buffer.projection), []),
    //               ),
    //             ),
    //           )
    //         Error(_) -> value.error(value.String("No file"))
    //       }
    //     _ -> value.error(value.String("No file"))
    //   }
    //   Internal(state:, reply:)
    // }
    harness.Visit(uri) -> External(Visit(uri))
    harness.Spotless(service, operation) -> Spotless(service:, operation:)
  }
}

fn runner_stoped(state, occured, debug) {
  #(State(..state, mode: RunningShell(occured:, awaiting: None, debug:)), [])
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
        buffer.from_source(
          source,
          module_context(state.scope, state.modules, state.sync.cache),
        )
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

fn spotless_connected(state, reference, service, result) {
  let State(mode:, ..) = state
  case mode {
    // put awaiting false for the fact it's no longer running
    RunningShell(
      occured:,
      awaiting:,
      debug: #(break.UnhandledEffect(label, lift), _meta, _env, _k) as debug,
    )
      if awaiting == Some(reference)
    -> {
      case result {
        Ok(token) -> {
          let assert Ok(harness.Spotless(service: expected, operation:)) =
            harness.cast(label, lift)
          assert expected == service

          let tokens = dict.insert(state.tokens, service, token)
          let state = State(..state, tokens:)
          run_spotless_effect_with_token(
            state,
            occured,
            debug,
            service,
            token,
            operation,
          )
        }
        Error(reason) -> {
          let mode = RunningShell(occured:, awaiting:, debug:)
          #(
            State(
              ..state,
              mode:,
              user_error: Some(snippet.ActionFailed(
                "run effect: " <> snag.line_print(reason),
              )),
            ),
            [],
          )
        }
      }
    }
    _ -> #(state, [])
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
            Ok(cache.Release(package:, version:, module:)) ->
              State(..state, mode: Editing)
              |> replace_buffer(rebuild(#(package, version, module), _))
            Error(Nil) -> #(
              State(
                ..state,
                user_error: Some(snippet.ActionFailed("choose package")),
              ),
              [],
            )
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
          |> replace_buffer(rebuild(#("./" <> label, 0, relative_cid(label)), _))
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

/// Used for testing
pub fn replace_repl(state: State, new) {
  let repl = buffer.from_projection(new, ctx(state, Repl))
  State(..state, repl:)
}

/// Used for testing
pub fn set_module(state, name, projection) {
  let State(modules:, ..) = state
  let modules =
    dict.insert(
      modules,
      name,
      buffer.from_projection(projection, ctx(state, Module(name))),
    )
  State(..state, modules:)
}

fn sync_message(state, message) {
  let State(sync:, ..) = state
  let before = sync.cache.fragments
  let #(sync, actions) = client.update(sync, message)
  let actions = list.map(actions, todo)
  let before = set.from_list(dict.keys(before))
  let after = set.from_list(dict.keys(sync.cache.fragments))
  let diff = set.difference(after, before)
  let repl =
    buffer.add_references(state.repl, diff, ctx(State(..state, sync:), Repl))
  let modules =
    dict.map_values(state.modules, fn(name, buffer) {
      buffer.add_references(
        buffer,
        diff,
        ctx(State(..state, sync:), Module(name)),
      )
    })

  let state = State(..state, sync:, repl:, modules:)
  #(state, actions)
}
