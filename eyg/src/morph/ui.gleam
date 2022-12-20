// atelier
import gleam/io
import gleam/list
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

// issue with render depending on state in main/ui and ui loading render
// need to extract state i think
pub fn main() {
  let state = WorkSpace([], source, Navigate(transform.prepare(source, [])))
  let app =
    lustre.application(
      #(state, cmd.none()),
      update,
      fn(state: WorkSpace) { app.render(state.source, state.selection) },
    )
  assert Ok(dispatch) = lustre.start(app, "#app")

  listen_keypress(fn(key) {
    // Dispatch keypress i.e. just listen to event here and update should have all the logic in.
    dispatch(action.Keypress(key))
  })
}

fn update(state: WorkSpace, action) {
  case action {
    action.Keypress(key) -> keypress(key, state)

    action.SelectNode(path) -> #(
      WorkSpace(..state, selection: path),
      cmd.none(),
    )
  }
}

pub type Mode {
  Navigate(actions: transform.Act)
}

pub type WorkSpace {
  WorkSpace(selection: List(Int), source: e.Expression, mode: Mode)
}

// nav.keypres
fn keypress(key, state: WorkSpace) {
  // TODO put this in the state
  // TODO split by mode
  // let act = transform.prepare(state.source, state.selection)
  let state = case state.mode, key {
    Navigate(act), "q" ->
      todo("!!show code or deploy, prob behind command or automatic")
    Navigate(act), "w" -> call_with(act, state)
    Navigate(act), "e" -> assign_to(act, state)
    Navigate(act), "r" -> todo("record")
    Navigate(act), "t" -> todo("tuple now tag")
    Navigate(act), "y" -> todo("copy")
    Navigate(act), "u" -> todo("unwrap")
    Navigate(act), "i" -> todo("insert test")
    Navigate(act), "o" -> todo("o")
    Navigate(act), "p" -> todo("provider not needed")
    Navigate(act), "a" -> increase(state)
    Navigate(act), "s" -> decrease(act, state)
    Navigate(act), "d" -> delete(act, state)
    Navigate(act), "f" -> todo("function")
    Navigate(act), "g" -> todo("get select")
    Navigate(act), "h" -> todo("left probably not")
    Navigate(act), "j" -> todo("down probably not")
    Navigate(act), "k" -> todo("up probably not")
    Navigate(act), "l" -> todo("right probably not")
    Navigate(act), "z" -> todo("z")
    Navigate(act), "x" -> todo("!!provider expansion not needed atm")
    Navigate(act), "c" -> todo("call")
    Navigate(act), "v" -> todo("variable")
    Navigate(act), "b" -> todo("!binary")
    Navigate(act), "n" -> todo("!named but this is likely to be tagged now")
    Navigate(act), "m" -> todo("match")
    Navigate(act), " " -> todo("space follow suggestion next error")
    _, _ -> state
  }
  #(state, cmd.none())
}

// TODO these should be grouped by mode
fn call_with(act, state) {
  let source = act.update(e.Apply(e.Vacant, act.target))
  WorkSpace(..state, source: source)
}

// e is essentially line above on a let statement.
// nested lets can only be created from the value on the right.
// moving something to a module might just have to be copy paste
fn assign_to(act, state) {
  let source = case act.target {
    e.Let(_, _, _) -> act.update(e.Let("new mode", e.Vacant, act.target))
    exp -> act.update(e.Let("new mode", exp, e.Vacant))
  }
  WorkSpace(..state, source: source)
}

fn increase(state) {
  let selection = case list.reverse(state.selection) {
    [_, ..rest] -> list.reverse(rest)
    [] -> {
      io.debug("no increase")
      []
    }
  }
  let act = transform.prepare(state.source, selection)
  WorkSpace(..state, selection: selection, mode: Navigate(act))
}

fn decrease(act, state) {
  case act.target {
    // TODO count children probably none
    //  ->
    _ -> {
      // TODO fix the indexing through things Let value is one but should probably be zeo
      // IF expression are all single addressable
      let selection = list.append(state.selection, [1])
      let act = transform.prepare(state.source, selection)
      WorkSpace(..state, selection: selection, mode: Navigate(act))
    }
  }
}

fn delete(act, state) {
  // an assignment vacant or not is always deleted.
  // when deleting with a vacant as a target there is no change
  // we can instead bump up the path
  let source = case act.target {
    e.Let(label, _, then) -> act.update(then)
    _ -> act.update(e.Vacant)
  }
  WorkSpace(..state, source: source)
}
