import examine/state
import examine/view/page
import lustre

// run depends on page and page depends on state so need separate file for state/model
pub fn run() {
  let app = lustre.application(state.init, state.update, page.render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
