import gleam/io
import lustre
import lustre/cmd
import atelier/app
import atelier/view/root
import eygir/decode

// render -> app
// main -> render
// is main in app circle
// vew depends on state
// load source can I use same static path i.e. /src/source.json
pub fn main(source) {
  let assert Ok(source) = decode.from_json(source)
  let assert Ok(dispatch) =
    lustre.application(#(app.init(source), cmd.none()), app.update, root.render)
    |> lustre.start("#app")

  io.debug(dispatch)
  listen_keypress(fn(key) { dispatch(app.Keypress(key)) })
}

// js(all ffi's) files need to be top level
// careful is a js not mjs file
external fn listen_keypress(fn(string) -> Nil) -> Nil =
  "../browser_ffi.js" "listenKeypress"
