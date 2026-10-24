import etui/backend
import eyg/analysis/inference/levels_j/contextual as infer
import eyg/hub/cache
import eyg/interpreter/state as istate
import loam/execute
import loam/platform/computer
import loam/source
import morph/analysis
import morph/buffer.{type Buffer}
import morph/manipulation as m
import touch_grass/interface

/// Note the buffer is a morph buffer not an etui buffer
pub type State {
  State(quit: Bool, buffer: Buffer, execute_state: execute.State)
}

pub fn init(
  scope: istate.Scope(source.Location),
  execute_state: execute.State,
) -> State {
  // I think cache types should turn into a lookup
  let buffer =
    buffer.empty(repl_context(scope), cache.types(execute_state.cache))
  State(quit: False, buffer:, execute_state:)
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
  case event {
    backend.KeyPress("ctrl+q") -> State(..state, quit: True)
    backend.KeyPress(key:) -> key_press(state, key)
    backend.Resize(width: _, height: _) -> state
    backend.Tick -> state
    backend.MousePress(x: _, y: _, button: _) -> state
    backend.MouseRelease(x: _, y: _, button: _) -> state
    backend.MouseScroll(x: _, y: _, up: _) -> state
    backend.MouseDrag(x: _, y: _, button: _) -> state
    backend.MouseMove(x: _, y: _) -> state
    backend.Paste(text: _) -> state
  }
}

fn key_press(state: State, key: String) -> State {
  // keymap.all_bindings
  case key {
    "e" -> edit(state, m.assign())
    "L" -> edit(state, m.create_empty_list())
    _ -> navigate(state)
  }
}

fn navigate(state) {
  state
}

fn edit(state: State, operation: m.Operation) -> State {
  let m.Operation(name: _, apply:) = operation
  case apply(state.buffer) {
    Ok(m.Resolved(gen)) ->
      State(
        ..state,
        buffer: gen(repl_context([]), cache.types(state.execute_state.cache)),
      )
    Ok(m.UserInput(_input)) -> {
      // let mode = Manipulating(input)
      // let state = State(..state, mode:)
      state
    }

    Error(Nil) ->
      // fail(state, name)
      state
  }
}
