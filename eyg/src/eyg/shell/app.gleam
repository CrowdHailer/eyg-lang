import eyg/shell/state
import eyg/shell/view/page
import lustre

// page needs to know all the sub types it works with but maybe they should always be modules
pub fn run() {
  let app = lustre.application(state.init, state.update, page.render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}
