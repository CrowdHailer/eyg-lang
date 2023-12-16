import lustre
import lustre/effect
import datalog/browser/app/model
import datalog/browser/view/page

pub fn run() {
  let app = lustre.application(init, update, page.render)
  let assert Ok(_) = lustre.start(app, "body > *", Nil)
  Nil
}

fn init(_) {
  #(model.initial(), effect.none())
}

fn update(model, msg: model.Wrap) {
  let model.Wrap(msg) = msg
  msg(model)
}
