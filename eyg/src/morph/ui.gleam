import lustre
import lustre/cmd
import morph/action
import morph/components/app

// TODO do js(all ffi's) files need to be top level
// careful is a js not mjs file
external fn listen_keypress(fn(string) -> Nil) -> Nil =
  "../browser_ffi.js" "listenKeypress"

pub fn main() {
  let state = action.State([])
  let app = lustre.application(#(state, cmd.none()), update, app.render)
  assert Ok(dispatch) = lustre.start(app, "#app")

  listen_keypress(fn(key) {
    // Dispatch keypress i.e. just listen to event here and update should have all the logic in.
    dispatch(action.Keypress(key))
  })
}

fn update(state, action) {
  case action {
    action.Keypress(_) -> #(state, cmd.none())
    action.SelectNode(path) -> #(action.State(path), cmd.none())
  }
}
