import gleam/option.{None, Some}
import lustre
import lustre/cmd
import atelier/app
import atelier/view/root
import source.{source}

// render -> app
// main -> render
// is main in app circle
// vew depends on state
pub fn main() {
  assert Ok(dispatch) =
    lustre.application(#(app.init(source), cmd.none()), app.update, root.render)
    |> lustre.start("#app")

  listen_keypress(fn(key) { dispatch(app.Keypress(key)) })
}

// js(all ffi's) files need to be top level
// careful is a js not mjs file
external fn listen_keypress(fn(string) -> Nil) -> Nil =
  "../browser_ffi.js" "listenKeypress"
