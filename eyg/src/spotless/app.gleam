import gleam/javascript/promisex
import lustre
import spotless/view/page
import spotless/state
import spotless/repl/loader

// run depends on page and page depends on state so need separate file for state/model
pub fn run() {
  use r <- promisex.aside(loader.load())
  let assert Ok(#(prompt, env, k)) = r

  let app = lustre.application(state.init, state.update, page.render)
  let assert Ok(_) = lustre.start(app, "#app", #(prompt, env, k))
  Nil
}
