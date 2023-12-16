import lustre
import datalog/browser/app/model
import datalog/browser/view/page

pub fn run() {
  let app = lustre.simple(init, update, page.render)
  let assert Ok(_) = lustre.start(app, "body > *", Nil)
  Nil
}

fn init(_) {
  model.initial()
}

fn update(model, msg) {
  msg(model)
}
