// this can define state and UI maybe UI should be separate
import gleam/io
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import lustre/cmd
import atelier/transform
import eygir/expression as e
import eygir/encode
import gleam/javascript/promise.{Promise}

pub type WorkSpace {
  WorkSpace(
    selection: List(Int),
    source: e.Expression,
    mode: Mode,
    yanked: Option(e.Expression),
    error: Option(String),
  )
}

pub type Mode {
  Navigate(actions: transform.Act)
  WriteLabel(value: String, commit: fn(String) -> e.Expression)
}

pub type Action {
  Keypress(key: String)
  Change(value: String)
  SelectNode(path: List(Int))
}

pub fn init(source) {
  assert Ok(act) = transform.prepare(source, [])
  let mode = Navigate(act)
  WorkSpace([], source, mode, None, None)
}

pub fn update(state: WorkSpace, action) {
  case action {
    Keypress(key) -> keypress(key, state)
    Change(value) -> {
      let mode = case state.mode {
        WriteLabel(_, commit) -> WriteLabel(value, commit)
        m -> m
      }
      let state = WorkSpace(..state, mode: mode)
      #(state, cmd.none())
    }
    SelectNode(path) -> select_node(state, path)
  }
}

pub fn select_node(state, path) {
  let WorkSpace(source: source, ..) = state
  assert Ok(act) = transform.prepare(source, path)
  let mode = Navigate(act)
  let state = WorkSpace(..state, source: source, selection: path, mode: mode)

  #(state, cmd.none())
}

// select node is desired action specific but keypress is user action specific.
// is this a problem?
// call click_node and then switch by state
// clicking a variable could use it in place
pub fn keypress(key, state: WorkSpace) {
  let r = case state.mode, key {
    // save in this state only because q is a normal letter needed when entering text
    Navigate(act), "q" -> save(state)
    Navigate(act), "w" -> call_with(act, state)
    Navigate(act), "e" -> Ok(assign_to(act, state))
    // Navigate(act), "r" -> todo("record")
    // Navigate(act), "t" -> todo("tuple now tag")
    Navigate(act), "y" -> Ok(copy(act, state))
    // Navigate(act), "u" -> todo("unwrap")
    Navigate(act), "i" -> insert(act, state)
    // Navigate(act), "o" -> todo("o")
    // Navigate(act), "p" -> todo("provider not needed")
    Navigate(act), "a" -> increase(state)
    Navigate(act), "s" -> decrease(act, state)
    Navigate(act), "d" -> delete(act, state)
    Navigate(act), "f" -> Ok(abstract(act, state))
    Navigate(act), "g" -> Ok(select(act, state))
    // Navigate(act), "h" -> todo("left probably not")
    // Navigate(act), "j" -> todo("down probably not")
    // Navigate(act), "k" -> todo("up probably not")
    // Navigate(act), "l" -> todo("right probably not")
    // Navigate(act), "z" -> todo("z")
    // Navigate(act), "x" -> todo("!!provider expansion not needed atm")
    Navigate(act), "c" -> call(act, state)
    // Navigate(act), "v" -> todo("variable")
    Navigate(act), "b" -> Ok(binary(act, state))
    // Navigate(act), "n" -> todo("!named but this is likely to be tagged now")
    Navigate(act), "m" -> match(act, state)
    // Navigate(act), " " -> todo("space follow suggestion next error")
    Navigate(_), _ -> Error("no action for keypress")
    // Other mode
    WriteLabel(text, commit), k if k == "Enter" -> {
      let source = commit(text)
      update_source(state, source)
    }
    WriteLabel(_, _), k -> Ok(state)
  }
  case r {
    // Always clear message on new keypress
    Ok(state) -> #(WorkSpace(..state, error: None), cmd.none())
    Error(message) -> #(WorkSpace(..state, error: Some(message)), cmd.none())
  }
}

external fn post_json(String, a) -> Promise(Result(#(), String)) =
  "../browser_ffi.js" "postJSON"

external fn post(String, String) -> Promise(Result(#(), String)) =
  "../browser_ffi.js" "post"

fn save(state) {
  // todo("encode")
  post("/save", encode.to_json(state.source))
  |> io.debug
  Ok(state)
}

fn call_with(act, state) {
  let source = act.update(e.Apply(e.Vacant, act.target))
  update_source(state, source)
}

// e is essentially line above on a let statement.
// nested lets can only be created from the value on the right.
// moving something to a module might just have to be copy paste
fn assign_to(act, state) {
  let commit = case act.target {
    e.Let(_, _, _) -> fn(text) { act.update(e.Let(text, e.Vacant, act.target)) }
    exp -> fn(text) { act.update(e.Let(text, exp, e.Vacant)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn copy(act, state) {
  WorkSpace(..state, yanked: Some(act.target))
}

fn insert(act, state) {
  try #(text, build) = case act.target {
    e.Variable(value) -> Ok(#(value, e.Variable(_)))
    e.Lambda(param, body) -> Ok(#(param, e.Lambda(_, body)))
    e.Apply(_, _) -> Error("no insert option for apply")
    e.Let(var, body, then) -> Ok(#(var, e.Let(_, body, then)))

    e.Binary(value) -> Ok(#(value, e.Binary(_)))
    e.Integer(value) -> Error("there needs to be a new mode for integer insert")
    e.Vacant -> Error("no insert option for vacant")
    e.Record(_, _) -> todo("record insert")
    e.Empty -> Error("empty record no insert")
    e.Extend(label) -> Ok(#(label, e.Extend))
    e.Select(label) -> Ok(#(label, e.Select))
    e.Tag(label) -> Ok(#(label, e.Tag))
    e.Case(label) -> Ok(#(label, e.Case))
    e.NoCases -> Error("no cases")
    e.Match(_, _) -> todo("match inset")
    e.Perform(label) -> Ok(#(label, e.Perform))
    e.Deep(_, _) -> todo("handle inserte")
  }

  let mode = WriteLabel(text, fn(new) { act.update(build(new)) })
  Ok(WorkSpace(..state, mode: mode))
}

fn increase(state) {
  try selection = case list.reverse(state.selection) {
    [_, ..rest] -> Ok(list.reverse(rest))
    [] -> Error("no increase")
  }
  assert Ok(act) = transform.prepare(state.source, selection)
  Ok(WorkSpace(..state, selection: selection, mode: Navigate(act)))
}

fn decrease(act, state) {
  let selection = list.append(state.selection, [0])
  try act = transform.prepare(state.source, selection)
  Ok(WorkSpace(..state, selection: selection, mode: Navigate(act)))
}

fn delete(act, state) {
  // an assignment vacant or not is always deleted.
  // when deleting with a vacant as a target there is no change
  // we can instead bump up the path
  let source = case act.target {
    e.Let(label, _, then) -> act.update(then)
    _ -> act.update(e.Vacant)
  }
  update_source(state, source)
}

fn abstract(act, state) {
  let commit = case act.target {
    e.Let(label, value, then) -> fn(text) {
      act.update(e.Let(label, e.Lambda(text, value), then))
    }
    exp -> fn(text) { act.update(e.Lambda(text, exp)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

// g for get
fn select(act, state) {
  let commit = case act.target {
    e.Let(label, value, then) -> {
      io.debug("can't get on let")
      state
    }
    exp -> {
      let commit = fn(text) { act.update(e.Apply(e.Select(text), exp)) }
      WorkSpace(..state, mode: WriteLabel("", commit))
    }
  }
}

fn call(act, state) {
  let source = act.update(e.Apply(act.target, e.Vacant))
  update_source(state, source)
}

fn binary(act, state) {
  let commit = case act.target {
    e.Let(label, value, then) -> fn(text) {
      act.update(e.Let(label, e.Binary(text), then))
    }
    exp -> fn(text) { act.update(e.Binary(text)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn match(act, state) {
  let commit = case act.target {
    // e.Let(label, value, then) -> fn(text) {
    //   act.update(e.Let(label, e.Binary(text), then))
    // }
    // TODO probably need matching to do diff in case
    // Match on original value should maybe be the arg? but I like promoting first class everything
    exp -> fn(text) {
      act.update(e.Apply(e.Apply(e.Case(text), e.Vacant), exp))
    }
  }
  Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
}

// app state actions maybe separate from ui but maybe ui files organised by mode
// update source also ends the entry state
fn update_source(state: WorkSpace, source) {
  // try mode = case state.mode {
  //   Navigate(_) -> {
  try act = transform.prepare(source, state.selection)
  let mode = Navigate(act)
  //   }
  //   _ -> Ok(state.mode)
  // }
  Ok(WorkSpace(..state, source: source, mode: mode))
}
