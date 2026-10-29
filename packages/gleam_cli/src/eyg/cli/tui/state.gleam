import etui/backend
import etui/style
import etui/widgets/input
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/cli/etui/widgets/combobox
import eyg/cli/tui/references
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/state as istate
import eyg/interpreter/value
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import loam/execute
import loam/platform/computer
import loam/source
import loam/system
import morph/analysis
import morph/buffer.{type Buffer}
import morph/command
import morph/editable as e
import morph/manipulation as m
import morph/picker
import morph/projection
import morph/repl/history
import multiformats/cid/v1
import touch_grass/harness/computer as harness
import touch_grass/interface
import touch_grass/standard_in

/// Note the buffer is a morph buffer not an etui buffer
pub type State {
  State(
    quit: Bool,
    mode: Mode,
    buffer: Buffer,
    scope: istate.Scope(source.Location),
    history: List(history.Entry(source.Location)),
    execute_state: execute.State,
    message: Option(String),
    counter: Int,
    imports: dict.Dict(references.FileKey, references.File),
    dependencies: set.Set(references.Dependency),
  )
}

pub type Mode {
  Navigating
  FreeInput(input: input.InputState, kind: InputKind)
  PickSingle(box: combobox.Combobox, rebuild: m.Rebuild(String))
  PickRelease(box: combobox.Combobox, rebuild: m.Rebuild(ir.Release))
  // Browsing history, newest first.
  History(selected: Int)
  Running(
    active: Active,
    env: istate.Env(source.Location),
    k: istate.Stack(source.Location),
    occured: List(history.EffectRecord(source.Location)),
  )
  // id is likely to be added in when we get a full IDE
  // ReadingFromClipboard(id: String, rebuild: Rebuild(e.Expression))
  // Running(id: String, run: Run)
  // UnFocused
}

/// Same as repl.Run(meta) except when finished it always moves to history.
pub type Active {
  Handling(task_id: Int, label: String, lift: execute.Value)
  Blocked(dep: cache.Dependency)
}

pub type InputKind {
  // PickSingle(m.Rebuild(String))
  PickCid(m.Rebuild(v1.Cid))
  // PickRelease(m.Rebuild(ir.Release))
  EnterText(m.Rebuild(String))
  EnterInteger(m.Rebuild(Int))
  EnterImport(m.Rebuild(ir.Reference))
  ReplyStandardIn(
    // active: Active,
    env: istate.Env(source.Location),
    k: istate.Stack(source.Location),
    occured: List(history.EffectRecord(source.Location)),
  )
}

pub type Event {
  Input(backend.InputEvent)
  Task(Message)
}

pub type Message {
  EffectHandled(task_id: Int, value: istate.Value(source.Location))
  CacheUpdated(cache.ActionCompleted)
  ImportRead(
    task_id: Int,
    key: references.FileKey,
    result: Result(ir.Node(source.Location), String),
  )
}

/// Use the same configuration for rendering and editing the input.
pub fn input_widget(kind: InputKind) -> input.InputWidget {
  case kind {
    EnterText(_) -> input.input_new("Enter text")
    EnterImport(_) -> input.input_new("Enter a file path")
    EnterInteger(_) ->
      input.input_new("Enter an integer")
      |> input.with_validator(fn(value) {
        case int.parse(value) {
          Ok(_) -> Ok(Nil)
          Error(_) -> Error("Enter a valid integer")
        }
      })
    ReplyStandardIn(..) -> input.input_new("Standard input")
    PickCid(_) ->
      input.input_new("Enter a content reference")
      |> input.with_validator(fn(value) {
        case parse_content_reference(value) {
          Ok(_) -> Ok(Nil)
          Error(_) -> Error("Enter a valid cid")
        }
      })
  }
  |> input.with_error_color(style.Indexed(1))
}

fn parse_content_reference(value: String) {
  let cid = case value {
    "#" <> cid -> cid
    cid -> cid
  }
  v1.from_string(cid)
}

pub fn init(
  scope: istate.Scope(source.Location),
  execute_state: execute.State,
) -> State {
  let buffer =
    buffer.empty()
    |> buffer.check(repl_context(scope))
    |> cache.infer_sync(execute_state.cache)

  State(
    quit: False,
    mode: Navigating,
    buffer:,
    scope:,
    history: [],
    execute_state:,
    message: None,
    counter: 0,
    imports: dict.new(),
    dependencies: set.new(),
  )
}

pub fn repl_context(
  scope: List(#(String, istate.Value(source.Location))),
) -> infer.Context {
  let #(bindings, env) =
    analysis.env_to_tenv(
      scope,
      source.Location(origin: source.Inline, source: source.Json),
    )
  infer.Context(..infer.pure(), env:, level: 0, bindings:)
  |> infer.with_effects(interface.types(computer.effects()))
}

pub fn update(
  state: State,
  event: Event,
) -> #(State, List(system.Effect(Message))) {
  let #(next, effects) = transition(state, event)
  let retry = case event {
    Input(_) -> True
    Task(_) -> False
  }
  let #(next, reads) = case next.buffer.analysis {
    Some(_) -> #(next, [])
    None -> check_buffer(next, retry)
  }
  let #(execute_state, loads) = execute.flush(next.execute_state, CacheUpdated)
  #(State(..next, execute_state:), list.flatten([effects, loads, reads]))
}

fn transition(state: State, event: Event) {
  // A message stays until the next input from the user.
  let state = case event {
    Input(_) -> State(..state, message: None)
    Task(_) -> state
  }
  case state.mode, event {
    _, Input(backend.KeyPress("ctrl+q")) -> #(State(..state, quit: True), [])
    _, Task(CacheUpdated(completed)) -> cache_updated(state, completed)
    _, Task(ImportRead(id, key, result)) ->
      case dict.get(state.imports, key) {
        Ok(references.Reading(current)) if current == id -> {
          let file = case result {
            Ok(module) -> references.Read(module, False)
            Error(reason) -> references.Unreadable(reason)
          }
          #(
            State(
              ..state,
              imports: dict.insert(state.imports, key, file),
              buffer: buffer.invalidate(state.buffer),
            ),
            [],
          )
        }
        _ -> #(state, [])
      }
    Running(active: _, env: _, k: _, occured:), Input(backend.KeyPress("esc"))
    ->
      history.Aborted("Cancelled")
      |> finish_run(state.scope, occured, state)
    Running(..), Input(_) -> #(state, [])
    Running(Handling(task_id:, label:, lift:), env, k, occured),
      Task(EffectHandled(id, value))
      if id == task_id
    -> after_perform(system.Done(value), label, lift, env, k, state, occured)
    Navigating, Input(backend.KeyPress(key:)) -> command_key_press(state, key)
    History(selected:), Input(backend.KeyPress(key:)) -> #(
      history_key_press(state, selected, key),
      [],
    )
    History(..), Input(_) -> #(state, [])
    PickSingle(box, rebuild), Input(event) ->
      case combobox.update(event, box) {
        combobox.Cancelled -> #(State(..state, mode: Navigating), [])
        combobox.Selected(value) ->
          submit_input(state, value, EnterText(rebuild))
        combobox.Updated(box) -> #(
          State(..state, mode: PickSingle(box, rebuild)),
          [],
        )
      }
    PickRelease(box, rebuild), Input(event) ->
      case combobox.update(event, box) {
        combobox.Cancelled -> #(State(..state, mode: Navigating), [])
        combobox.Updated(box) -> #(
          State(..state, mode: PickRelease(box, rebuild)),
          [],
        )
        combobox.Selected(name) ->
          case cache.package(state.execute_state.cache, name) {
            Ok(cache.Entry(version:, module:, ..)) -> #(
              State(
                ..state,
                mode: Navigating,
                buffer: rebuild(ir.Release(name, version, module)),
              ),
              [],
            )
            Error(_) -> #(fail(state, "Choose a published package"), [])
          }
      }
    FreeInput(input:, kind:), Input(backend.KeyPress(key:)) ->
      input_key_pressed(state, input, kind, key)
    FreeInput(input:, kind:), Input(backend.Paste(text:)) -> {
      let edited =
        text
        |> string.replace("\r", "")
        |> string.replace("\n", " ")
        |> string.to_graphemes
        |> list.fold(input, fn(editing, char) {
          input.insert_char(input_widget(kind), editing, char)
        })
      #(State(..state, mode: FreeInput(edited, kind)), [])
    }
    _, Input(backend.Resize(width: _, height: _)) -> #(state, [])
    _, Input(backend.Tick) -> #(state, [])
    _, Input(backend.MousePress(x: _, y: _, button: _)) -> #(state, [])
    _, Input(backend.MouseRelease(x: _, y: _, button: _)) -> #(state, [])
    _, Input(backend.MouseScroll(x: _, y: _, up: _)) -> #(state, [])
    _, Input(backend.MouseDrag(x: _, y: _, button: _)) -> #(state, [])
    _, Input(backend.MouseMove(x: _, y: _)) -> #(state, [])
    Navigating, Input(backend.Paste(text:)) -> #(paste(state, text), [])
    _, Task(_) -> {
      #(state, [])
    }
  }
}

fn input_key_pressed(
  state: State,
  input: input.InputState,
  kind: InputKind,
  key: String,
) -> #(State, _) {
  case key, kind {
    "esc", ReplyStandardIn(env:, k:, occured:) -> {
      let reply = system.Done(standard_in.encode(Error("Cancelled")))
      after_perform(reply, "StandardIn", value.unit(), env, k, state, occured)
    }
    "esc", _ -> #(State(..state, mode: Navigating), [])
    "enter", _ -> submit_input(state, input.value, kind)
    _, _ -> {
      let edited = combobox.edit_input(input_widget(kind), input, key)
      #(State(..state, mode: FreeInput(edited, kind)), [])
    }
  }
}

fn submit_input(
  state: State,
  value: String,
  kind: InputKind,
) -> #(State, List(_)) {
  case kind {
    EnterText(rebuild) -> #(
      State(..state, mode: Navigating, buffer: rebuild(value)),
      [],
    )
    EnterImport(rebuild) -> #(import_file(state, rebuild, value), [])
    EnterInteger(rebuild) ->
      case int.parse(value) {
        Ok(value) -> #(
          State(..state, mode: Navigating, buffer: rebuild(value)),
          [],
        )
        Error(_) -> #(state, [])
      }
    PickCid(rebuild) ->
      case parse_content_reference(value) {
        Ok(#(cid, _)) -> #(
          State(..state, mode: Navigating, buffer: rebuild(cid)),
          [],
        )
        Error(_) -> #(state, [])
      }

    ReplyStandardIn(env:, k:, occured:) -> {
      let reply =
        system.Done(standard_in.encode(Ok(bit_array.from_string(value))))
      after_perform(reply, "StandardIn", value.unit(), env, k, state, occured)
    }
  }
}

fn command_key_press(
  state: State,
  key: String,
) -> #(State, List(system.Effect(Message))) {
  case key {
    "esc" -> #(state, [])
    "right" -> navigate(state, "move right", buffer.next)
    "left" -> navigate(state, "move left", buffer.previous)
    "up" ->
      case state.history != [] && empty_draft(state) {
        True -> #(State(..state, mode: History(0)), [])
        False -> navigate(state, "move up", buffer.up)
      }
    "down" -> navigate(state, "move down", buffer.down)
    // "Q" -> link_filesystem(state)
    "q" -> import_input(state)
    "w" -> edit(state, m.call_with())
    "E" -> edit(state, m.assign_before())
    "e" -> edit(state, m.assign())
    "R" -> edit(state, m.create_empty_record())
    "r" -> edit(state, m.create_record())
    "t" -> edit(state, m.insert_tag())
    "y" -> #(fail(state, "Copy is not supported"), [])
    "Y" -> #(
      fail(state, "Use your terminal's native paste shortcut to paste"),
      [],
    )
    // TODO mode is authenticating
    // you won't see much on the front page
    // "u" -> #(State(..state, mode: SigningPayload(None, "foo")), [
    //   system.OpenPopup("/sign", resume: fn(result) {
    //     system.Done(OpenPopupCompleted(result))
    //   }),
    // ])
    "i" -> edit(state, m.insert())
    "o" -> edit(state, m.overwrite())
    "p" -> edit(state, m.perform(interface.types(computer.effects())))
    "a" -> navigate(state, "increase selection", buffer.increase)
    "s" -> edit(state, m.insert_string())
    "d" -> edit(state, m.delete())
    "f" -> edit(state, m.insert_function())
    "g" -> edit(state, m.select_field())
    "h" -> edit(state, m.insert_handle(interface.types(computer.effects())))
    "j" -> edit(state, m.insert_builtin())
    "k" -> navigate(state, "toggle", buffer.toggle_open)
    "L" -> edit(state, m.create_empty_list())
    "l" -> edit(state, m.create_list())
    "@" -> edit(state, m.choose_release(packages(state)))
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
    "enter" -> confirm(state)
    " " -> navigate(state, "Jump to vacant", buffer.next_vacant)
    _ -> #(fail(state, command.fail_message(command.NoKeyBinding(key))), [])
  }
}

fn navigate(state: State, name, func) {
  case func(state.buffer) {
    Ok(buffer) -> #(State(..state, buffer:), [])
    Error(_) -> #(
      fail(state, command.fail_message(command.ActionFailed(name))),
      [],
    )
  }
}

fn edit(state: State, operation: m.Operation) -> #(State, List(_)) {
  let m.Operation(name:, apply:) = operation
  let state = case apply(state.buffer) {
    Ok(m.Resolved(buffer)) -> State(..state, buffer:)
    Ok(m.UserInput(m.EnterText(value, rebuild))) ->
      State(
        ..state,
        mode: FreeInput(input.state_from_string(value), EnterText(rebuild)),
      )
    Ok(m.UserInput(m.EnterInteger(value, rebuild))) ->
      State(
        ..state,
        mode: FreeInput(
          input.state_from_string(int.to_string(value)),
          EnterInteger(rebuild),
        ),
      )
    Ok(m.UserInput(m.PickSingle(picker.Typing(value, choices), rebuild))) ->
      State(
        ..state,
        mode: PickSingle(
          combobox.Combobox(
            ..combobox.new(choices),
            input: input.state_from_string(value),
          ),
          rebuild,
        ),
      )

    Ok(m.UserInput(m.PickRelease(picker.Typing(value, choices), rebuild))) ->
      State(
        ..state,
        mode: PickRelease(
          combobox.Combobox(
            ..combobox.new(choices),
            input: input.state_from_string(value),
          ),
          rebuild,
        ),
      )

    Ok(m.UserInput(m.PickCid(_, rebuild))) ->
      State(..state, mode: FreeInput(input.state_new(), PickCid(rebuild)))
    Ok(m.UserInput(_)) ->
      fail(state, command.fail_message(command.ActionFailed(name)))
    Error(Nil) -> fail(state, command.fail_message(command.ActionFailed(name)))
  }
  #(state, [])
}

fn confirm(state: State) -> #(State, List(system.Effect(Message))) {
  let expression = projection.rebuild(state.buffer.projection)
  case expression {
    e.Vacant -> #(fail(state, "write a program"), [])
    _ -> {
      let source =
        e.to_annotated(expression, [])
        |> ir.map_annotation(fn(_) { source.Location(source.Repl, source.Json) })

      loop(block.execute(source, state.scope), state, [])
    }
  }
}

fn loop(
  return: Result(
    #(Option(istate.Value(source.Location)), istate.Scope(source.Location)),
    istate.Debug(source.Location),
  ),
  state: State,
  occured: List(history.EffectRecord(source.Location)),
) -> #(State, List(system.Effect(Message))) {
  let return =
    cache.static_loop(return, state.execute_state.cache, block.resume)
  case return {
    Ok(#(value, scope)) ->
      finish_run(history.Success(value), scope, occured, state)
    Error(#(break.UnhandledEffect(label, lift), location, env, k)) ->
      case computer.cast(label, lift) {
        Ok(effect) ->
          perform(effect, location.origin, label, lift, env, k, state, occured)
        Error(reason) ->
          history.Exception(#(reason, location, env, k))
          |> finish_run(state.scope, occured, state)
      }
    Error(debug) ->
      history.Exception(debug)
      |> finish_run(state.scope, occured, state)
  }
}

/// Nothing has been written in the draft yet.
fn empty_draft(state: State) {
  projection.rebuild(state.buffer.projection) == e.Vacant
}

/// Up and down select entries; moving past the newest returns to editing.
fn history_key_press(state: State, selected, key) {
  case key {
    "up" -> {
      let selected = int.min(selected + 1, list.length(state.history) - 1)
      State(..state, mode: History(selected))
    }
    "down" if selected == 0 -> State(..state, mode: Navigating)
    "down" -> State(..state, mode: History(selected - 1))
    "esc" -> State(..state, mode: Navigating)
    _ -> state
  }
}

/// Insert a path relative to the working directory.
fn import_input(state: State) {
  case buffer.insert_explicit_reference(state.buffer) {
    Error(_) -> #(fail(state, "Select an expression to import into"), [])
    Ok(rebuild) -> {
      let mode = FreeInput(input.state_new(), EnterImport(rebuild))
      #(State(..state, mode:), [])
    }
  }
}

fn import_file(state: State, rebuild, path) {
  let path = string.trim(path)
  case path == "" || string.ends_with(path, "/") {
    True -> fail(state, "Choose a file to import")
    False -> {
      let buffer = rebuild(ir.Relative(path))
      State(..state, mode: Navigating, buffer:)
    }
  }
}

fn packages(state: State) {
  state.execute_state.cache.packages
  |> dict.to_list
  |> list.map(fn(entry) { #(entry.0, entry.1.version) })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
}

fn check_buffer(state: State, retry) {
  let #(buffer, tracked) =
    buffer.check(state.buffer, repl_context(state.scope))
    |> references.check(
      state.execute_state.cache,
      state.imports,
      state.counter,
      state.dependencies,
      retry,
    )
  let reads =
    list.map(tracked.reads, fn(read) {
      let #(key, id) = read
      references.read(key) |> system.map(ImportRead(id, key, _))
    })
  #(
    State(
      ..state,
      buffer:,
      execute_state: execute.State(..state.execute_state, cache: tracked.cache),
      imports: tracked.files,
      counter: tracked.counter,
      dependencies: tracked.dependencies,
    ),
    reads,
  )
}

pub fn reference_loading(state: State, reference) {
  references.loading(state.imports, state.execute_state.cache, reference)
}

fn cache_updated(state: State, completed) {
  let cache = execute.apply(state.execute_state.cache, completed)
  let state =
    State(
      ..state,
      execute_state: execute.State(..state.execute_state, cache:),
      buffer: buffer.invalidate(state.buffer),
    )

  case state.mode {
    PickRelease(box, rebuild) -> {
      let items =
        list.map(packages(state), fn(entry) {
          #(entry.0, int.to_string(entry.1))
        })
      #(
        State(
          ..state,
          mode: PickRelease(combobox.Combobox(..box, items:), rebuild),
        ),
        [],
      )
    }
    _ -> #(state, [])
  }
}

fn perform(effect, origin, label, lift, env, k, state, occured) {
  case effect {
    harness.StandardOut(_) | harness.StandardError(_) ->
      system.Done(value.unit())
      |> after_perform(label, lift, env, k, state, occured)
    harness.StandardIn -> {
      let mode = FreeInput(input.state_new(), ReplyStandardIn(env, k, occured))
      #(State(..state, mode:), [])
    }
    harness.Exit(status) ->
      history.Aborted("Exited with status " <> int.to_string(status))
      |> finish_run(state.scope, occured, state)
    _ ->
      computer.extrinsic(effect, origin)
      |> after_perform(label, lift, env, k, state, occured)
  }
}

fn after_perform(reply, label, lift, env, k, state, occured) {
  case reply {
    system.Done(value) -> {
      let occured = [#(label, #(lift, value)), ..occured]
      loop(block.resume(value, env, k), state, occured)
    }
    effect -> {
      let task_id = state.counter
      let active = Handling(task_id:, label:, lift:)
      #(
        State(
          ..state,
          mode: Running(active, env, k, occured),
          counter: task_id + 1,
        ),
        [system.map(effect, EffectHandled(task_id, _))],
      )
    }
  }
}

fn finish_run(outcome, scope, occured, state: State) {
  let entry = history.Entry(outcome:, effects: occured, buffer: state.buffer)
  let history = [entry, ..state.history]
  let buffer = buffer.empty()
  #(
    State(
      ..state,
      mode: Navigating,
      history:,
      scope:,
      buffer:,
      imports: dict.new(),
    ),
    [],
  )
}

fn fail(state, message) {
  State(..state, message: Some(message))
}

pub fn paste(state: State, text: String) -> State {
  case buffer.set_expression(state.buffer), source.parse(text, source.Repl) {
    Ok(rebuild), Ok(source) -> {
      let expression = e.from_annotated(source) |> e.open_all
      State(..state, buffer: rebuild(expression))
    }

    Error(Nil), _ -> fail(state, "Select an expression to paste into")
    _, Error(reason) -> fail(state, reason)
  }
}
