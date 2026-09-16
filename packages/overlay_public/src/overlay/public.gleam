import gleam/javascript/promise
import gleam/list
import lustre
import lustre/effect
import ogre/origin
import overlay/public/view
import overlay/web/context
import overlay/web/state
import pal/system
import plinth/browser/location
import plinth/browser/window

pub fn main() -> Nil {
  let app = lustre.application(do_init, do_update, view.render)
  let location = window.location(window.self())
  let assert Ok(origin) = origin.from_string(location.origin(location))
  let context = case location.search(location) {
    Ok(search) -> context.from_search(search)
    Error(Nil) -> context.Default
  }
  let config = state.Config(origin:, context:)
  let assert Ok(_runtime) = lustre.start(app, "#app", config)
  Nil
}

fn do_init(config) {
  let #(state, actions) = state.init(config)
  #(state, effect.batch(list.map(actions, effect)))
}

fn do_update(state, message) {
  let #(state, actions) = state.update(state, message)
  #(state, effect.batch(list.map(actions, effect)))
}

fn effect(action) {
  effect.from(fn(dispatch) {
    promise.map(system.run(action), dispatch)
    Nil
  })
}
