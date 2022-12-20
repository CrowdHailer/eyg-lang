import gleam/io
import lustre
import lustre/cmd
import morph/action
import morph/components/app
import morph/workspace as transform
import source.{source}
import eygir/expression as e

// TODO do js(all ffi's) files need to be top level
// careful is a js not mjs file
external fn listen_keypress(fn(string) -> Nil) -> Nil =
  "../browser_ffi.js" "listenKeypress"

pub fn main() {
  let state = action.State([], source)
  let app = lustre.application(#(state, cmd.none()), update, app.render)
  assert Ok(dispatch) = lustre.start(app, "#app")

  listen_keypress(fn(key) {
    // Dispatch keypress i.e. just listen to event here and update should have all the logic in.
    dispatch(action.Keypress(key))
  })
}

fn update(state: action.State, action) {
  case action {
    action.Keypress(key) -> {
      let act = transform.prepare(state.source, state.selection)
      case key {
        "w" -> {
          // 
          let source = act.update(e.Apply(e.Vacant, act.target))
          #(action.State(..state, source: source), cmd.none())
        }
        "e" -> {
          // e is essentially line above on a let statement. 
          // nested lets can only be created from the value on the right.
          // moving something to a module might just have to be copy paste
          let source = case act.target {
            e.Let(_, _, _) ->
              act.update(e.Let("new mode", e.Vacant, act.target))
            exp -> act.update(e.Let("new mode", exp, e.Vacant))
          }
          #(action.State(..state, source: source), cmd.none())
        }
        "d" -> {
          let source = case act.target {
            // This can be a step in an delete
            // though as failure causes a delete up then maybe not
            e.Let(label, _, then) -> act.update(then)
            _ -> act.update(e.Vacant)
          }
          // on let it always deletes the row, vacant or not
          // on vacant we need to bump up the selection
          #(action.State(..state, source: source), cmd.none())
        }
        _ -> #(state, cmd.none())
      }
    }
    action.SelectNode(path) -> #(
      action.State(..state, selection: path),
      cmd.none(),
    )
  }
}
