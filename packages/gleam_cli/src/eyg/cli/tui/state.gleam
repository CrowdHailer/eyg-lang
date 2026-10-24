import etui/backend

pub type State {
  State(quit: Bool, text: String)
}

pub fn init(_scope, _state) -> State {
  State(quit: False, text: "")
}

pub fn update(event: backend.InputEvent, state: State) -> State {
  case event {
    backend.KeyPress("ctrl+q") -> State(..state, quit: True)
    backend.KeyPress(key:) -> State(..state, text: key)
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
