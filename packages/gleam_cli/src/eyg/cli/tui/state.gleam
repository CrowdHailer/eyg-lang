import etui/backend
import etui/keys
import etui/widgets/input
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/cli/etui/widgets/combobox
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/state as istate
import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/string
import loam/execute
import loam/platform/computer
import loam/source
import morph/analysis
import morph/buffer.{type Buffer}
import morph/command
import morph/editable as e
import morph/manipulation as m
import morph/picker
import morph/projection
import morph/repl/history
import touch_grass/interface

/// Note the buffer is a morph buffer not an etui buffer
pub type State {
  State(
    quit: Bool,
    mode: Mode,
    buffer: Buffer,
    scope: istate.Scope(source.Location),
    history: List(history.Entry(source.Location)),
    execute_state: execute.State,
    message: String,
  )
}

pub type Mode {
  Navigating
  FreeInput(input: input.InputState, kind: InputKind)
  PickSingle(box: combobox.Combobox, rebuild: m.Rebuild(String))
  // id is likely to be added in when we get a full IDE
  // ReadingFromClipboard(id: String, rebuild: Rebuild(e.Expression))
  // Running(id: String, run: Run)
  // UnFocused
}

pub type InputKind {
  // PickSingle(m.Rebuild(String))
  // PickCid(m.Rebuild(v1.Cid))
  // PickRelease(m.Rebuild(ir.Release))
  EnterText(m.Rebuild(String))
  EnterInteger(m.Rebuild(Int))
}

/// Use the same configuration for rendering and editing the input.
pub fn input_widget(kind: InputKind) -> input.InputWidget {
  case kind {
    EnterText(_) -> input.input_new("Enter text")
    EnterInteger(_) ->
      input.input_new("Enter an integer")
      |> input.with_validator(fn(value) {
        case int.parse(value) {
          Ok(_) -> Ok(Nil)
          Error(_) -> Error("Enter a valid integer")
        }
      })
  }
}

pub fn init(
  scope: istate.Scope(source.Location),
  execute_state: execute.State,
) -> State {
  // I think cache types should turn into a lookup
  let buffer =
    buffer.empty(repl_context(scope), cache.types(execute_state.cache))
  let message = "Enter runs the program"
  State(
    quit: False,
    mode: Navigating,
    buffer:,
    scope:,
    history: [],
    execute_state:,
    message:,
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

pub fn update(event: backend.InputEvent, state: State) -> State {
  case state.mode, event {
    _, backend.KeyPress("ctrl+q") -> State(..state, quit: True)
    Navigating, backend.KeyPress(key:) -> command_key_press(state, key)
    PickSingle(box, rebuild), event ->
      case combobox.update(event, box) {
        combobox.Cancelled -> State(..state, mode: Navigating)
        combobox.Selected(value) ->
          submit_input(state, value, EnterText(rebuild))
        combobox.Updated(box) -> State(..state, mode: PickSingle(box, rebuild))
      }
    FreeInput(input:, kind:), backend.KeyPress(key:) ->
      input_key_pressed(state, input, kind, key)
    FreeInput(input:, kind:), backend.Paste(text:) -> {
      let edited =
        text
        |> string.replace("\r", "")
        |> string.replace("\n", " ")
        |> string.to_graphemes
        |> list.fold(input, fn(editing, char) {
          input.insert_char(input_widget(kind), editing, char)
        })
      State(..state, mode: FreeInput(edited, kind))
    }
    _, backend.Resize(width: _, height: _) -> state
    _, backend.Tick -> state
    _, backend.MousePress(x: _, y: _, button: _) -> state
    _, backend.MouseRelease(x: _, y: _, button: _) -> state
    _, backend.MouseScroll(x: _, y: _, up: _) -> state
    _, backend.MouseDrag(x: _, y: _, button: _) -> state
    _, backend.MouseMove(x: _, y: _) -> state
    Navigating, backend.Paste(text:) -> paste(state, text)
  }
}

fn input_key_pressed(
  state: State,
  input: input.InputState,
  kind: InputKind,
  key: String,
) -> State {
  let keys.KeyEvent(code:, modifiers:) = keys.parse(key)
  case modifiers.ctrl || modifiers.alt {
    True -> state
    False ->
      case code {
        keys.Escape -> State(..state, mode: Navigating)
        keys.Enter -> submit_input(state, input.value, kind)
        _ -> {
          let edited = case code {
            keys.Char(char) ->
              input.insert_char(input_widget(kind), input, char)
            keys.Left -> input.move_cursor_left(input)
            keys.Right -> input.move_cursor_right(input)
            keys.Backspace -> input.backspace(input)
            keys.Delete -> {
              let moved = input.move_cursor_right(input)
              case moved.cursor == input.cursor {
                True -> input
                False -> input.backspace(moved)
              }
            }
            keys.Home -> input.move_to_start(input)
            keys.End -> input.move_to_end(input)
            _ -> input
          }
          State(..state, mode: FreeInput(edited, kind))
        }
      }
  }
}

fn submit_input(state: State, value: String, kind: InputKind) -> State {
  let context = repl_context(state.scope)
  let refs = cache.types(state.execute_state.cache)
  case kind {
    EnterText(rebuild) ->
      State(..state, mode: Navigating, buffer: rebuild(value, context, refs))
    EnterInteger(rebuild) ->
      case int.parse(value) {
        Ok(value) ->
          State(
            ..state,
            mode: Navigating,
            buffer: rebuild(value, context, refs),
          )
        Error(_) -> state
      }
  }
}

fn command_key_press(state: State, key: String) -> State {
  case key {
    "esc" -> state
    "right" -> navigate(state, "move right", buffer.next)
    "left" -> navigate(state, "move left", buffer.previous)
    "up" -> navigate(state, "move up", buffer.up)
    "down" -> navigate(state, "move down", buffer.down)
    // "Q" -> link_filesystem(state)
    // "q" -> edit(state, m.choose_module(state.modules))
    "w" -> edit(state, m.call_with())
    "E" -> edit(state, m.assign_before())
    "e" -> edit(state, m.assign())
    "R" -> edit(state, m.create_empty_record())
    "r" -> edit(state, m.create_record())
    "t" -> edit(state, m.insert_tag())
    // "y" -> copy(state)
    // "Y" -> paste(state)
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
    // "@" ->
    //   edit(
    //     state,
    //     m.choose_release(
    //       list.map(dict.to_list(state.cache.packages), fn(entry) {
    //         #(entry.0, entry.1.version)
    //       }),
    //     ),
    //   )
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
    _ -> fail(state, command.fail_message(command.NoKeyBinding(key)))
  }
}

fn navigate(state: State, name, func) {
  case func(state.buffer) {
    Ok(buffer) -> State(..state, buffer:)
    Error(_) -> fail(state, command.fail_message(command.ActionFailed(name)))
  }
}

fn edit(state: State, operation: m.Operation) -> State {
  let m.Operation(name:, apply:) = operation
  case apply(state.buffer) {
    Ok(m.Resolved(gen)) ->
      State(
        ..state,
        buffer: gen(
          repl_context(state.scope),
          cache.types(state.execute_state.cache),
        ),
      )
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

    // Reference pickers need parsing before their rebuild callbacks can run.
    Ok(m.UserInput(_)) ->
      fail(state, command.fail_message(command.ActionFailed(name)))

    Error(Nil) -> fail(state, command.fail_message(command.ActionFailed(name)))
  }
}

fn confirm(state: State) {
  // TODO remove 
  let cwd = "/repl"
  let expression = projection.rebuild(state.buffer.projection)
  case expression {
    e.Vacant -> fail(state, "write a program")
    _ -> {
      let source =
        e.to_annotated(expression, [])
        |> ir.map_annotation(fn(_) { source.Location(source.Repl, source.Json) })

      let scope = state.scope
      case loop(block.execute(source, scope), state) {
        Ok(#(value, scope)) -> {
          let entry = history.Entry(value:, effects: [], buffer: state.buffer)
          let history = [entry, ..state.history]
          State(..state, history:, scope:, message: "")
        }

        Error(#(reason, location, _, stack)) ->
          fail(state, execute.render_error(reason, location, stack, cwd))
      }
    }
  }
}

fn loop(return, _state) {
  return
}

fn fail(state, message) {
  State(..state, message:)
}

pub fn paste(state: State, text: String) -> State {
  case source.parse(text, source.Repl) {
    Ok(source) ->
      State(
        ..state,
        buffer: buffer.from_source(
          source,
          repl_context(state.scope),
          cache.types(state.execute_state.cache),
        ),
        message: "",
      )
    Error(reason) -> fail(state, reason)
  }
}
