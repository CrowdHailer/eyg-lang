import gleam/javascript/promisex
import gleam/uri
import lustre
import plinth/browser/window
import spotless/repl/loader
import spotless/state
import spotless/view/page

// run depends on page and page depends on state so need separate file for state/model
pub fn run() {
  let assert Ok(origin) = uri.parse(window.location())
  let src = uri.Uri(..origin, path: "/prompt.json")

  use r <- promisex.aside(loader.load(src))
  let assert Ok(#(prompt, env, k)) = r

  let app = lustre.application(state.init, state.update, page.render)
  // let assert Ok(_) = lustre.start(app, "#app", #(prompt, env, k))
  Nil
}
