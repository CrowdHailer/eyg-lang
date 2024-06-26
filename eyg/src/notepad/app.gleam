import lustre
import notepad/state
import notepad/view/page

// run depends on page and page depends on state so need separate file for state/model
pub fn run() {
  let app = lustre.application(state.init, state.update, page.render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
