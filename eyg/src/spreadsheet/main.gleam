import lustre
import lustre/cmd
import spreadsheet/state
import spreadsheet/action
import spreadsheet/view

external fn listen_keypress(fn(string) -> Nil) -> Nil =
  "../spreadsheet_ffi" "listenKeypress"

pub fn main() {
  let app =
    lustre.application(#(state.init(), cmd.none()), action.update, view.render)
  assert Ok(dispatch) = lustre.start(app, "#app")

  listen_keypress(fn(key) {
    // Dispatch keypress i.e. just listen to event here and update should have all the logic in.
    dispatch(action.Keypress(key))
  })
}
// Database as a Gleam file of [Commit([EAV(...), EAV(...)])]
