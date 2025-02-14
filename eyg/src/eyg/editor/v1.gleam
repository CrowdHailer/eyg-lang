// previously called atelier
import eyg/editor/v1/app
import eyg/editor/v1/view/root
import eyg/ir/tree as ir
import eyg/website/page
import gleam/option.{Some}
import lustre
import lustre/effect

pub fn page(bundle) {
  page.app(Some("editor"), "eyg/editor/v1/", "client", bundle)
}

pub fn client() {
  let app = lustre.application(init, app.update, root.render)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

fn init(_) {
  let state = app.init(ir.vacant())
  #(state, effect.none())
}
