// this can define state and UI maybe UI should be separate
import gleam/io
import gleam/int
import gleam/list
import gleam/option.{None, Option, Some}
import gleam/string
import gleam/javascript/promise.{Promise}
import gleam/fetch
import gleam/http
import gleam/http/request
import lustre/cmd
import atelier/transform
import eygir/expression as e
import eygir/encode
import eyg/analysis/inference
import eyg/runtime/standard

pub type WorkSpace {
  WorkSpace(
    selection: List(Int),
    source: e.Expression,
    inferred: inference.Infered,
    mode: Mode,
    yanked: Option(e.Expression),
    error: Option(String),
    history: #(
      List(#(e.Expression, List(Int))),
      List(#(e.Expression, List(Int))),
    ),
  )
}

pub type Mode {
  Navigate(actions: transform.Act)
  WriteLabel(value: String, commit: fn(String) -> e.Expression)
  WriteText(value: String, commit: fn(String) -> e.Expression)
  WriteNumber(value: Int, commit: fn(Int) -> e.Expression)
}

pub type Action {
  Keypress(key: String)
  Change(value: String)
  Commit
  SelectNode(path: List(Int))
  ClickOption(chosen: String)
}

pub fn init(source) {
  assert Ok(act) = transform.prepare(source, [])
  let mode = Navigate(act)
  WorkSpace([], source, standard.infer(source), mode, None, None, #([], []))
}

pub fn update(state: WorkSpace, action) {
  case action {
    Keypress(key) -> keypress(key, state)
    Change(value) -> {
      let mode = case state.mode {
        WriteLabel(_, commit) -> WriteLabel(value, commit)
        WriteNumber(_, commit) ->
          case value {
            "" -> WriteNumber(0, commit)
            _ -> {
              io.debug(value)
              assert Ok(number) = int.parse(value)
              WriteNumber(number, commit)
            }
          }
        WriteText(_, commit) -> WriteText(value, commit)
        m -> m
      }
      let state = WorkSpace(..state, mode: mode)
      #(state, cmd.none())
    }
    Commit -> {
      assert WriteText(current, commit) = state.mode
      let source = commit(current)
      assert Ok(workspace) = update_source(state, source)
      #(workspace, cmd.none())
    }
    ClickOption(text) -> {
      assert WriteLabel(_, commit) = state.mode
      let source = commit(text)
      assert Ok(workspace) = update_source(state, source)
      #(workspace, cmd.none())
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
    Navigate(act), "r" -> record(act, state)
    Navigate(act), "t" -> Ok(tag(act, state))
    Navigate(act), "y" -> Ok(copy(act, state))
    // copy paste quite rare so we use upper case. might be best as command
    Navigate(act), "Y" -> paste(act, state)
    Navigate(act), "u" -> unwrap(act, state)
    Navigate(act), "i" -> insert(act, state)
    Navigate(act), "o" -> overwrite(act, state)
    Navigate(act), "p" -> Ok(perform(act, state))
    Navigate(act), "a" -> increase(state)
    Navigate(act), "s" -> decrease(act, state)
    Navigate(act), "d" -> delete(act, state)
    Navigate(act), "f" -> Ok(abstract(act, state))
    Navigate(act), "g" -> select(act, state)
    // Navigate(act), "h" -> ("left probably not")
    // Navigate(act), "j" -> ("down probably not")
    // Navigate(act), "k" -> ("up probably not")
    // Navigate(act), "l" -> ("right probably not")
    Navigate(act), "z" -> undo(state)
    Navigate(act), "Z" -> redo(state)
    Navigate(act), "x" -> list(act, state)
    Navigate(act), "c" -> call(act, state)
    Navigate(act), "v" -> Ok(variable(act, state))
    Navigate(act), "b" -> Ok(binary(act, state))
    Navigate(act), "n" -> Ok(number(act, state))
    Navigate(act), "m" -> match(act, state)
    Navigate(act), "M" -> nocases(act, state)
    // Navigate(act), " " -> ("space follow suggestion next error")
    Navigate(_), _ -> Error("no action for keypress")
    // Other mode
    WriteLabel(text, commit), k if k == "Enter" -> {
      let source = commit(text)
      update_source(state, source)
    }
    WriteLabel(_, _), k -> Ok(state)
    WriteNumber(text, commit), k if k == "Enter" -> {
      let source = commit(text)
      update_source(state, source)
    }
    WriteNumber(_, _), k -> Ok(state)
    WriteText(_, _), k -> Ok(state)
  }

  case r {
    // Always clear message on new keypress
    Ok(state) -> #(WorkSpace(..state, error: None), cmd.none())
    Error(message) -> #(WorkSpace(..state, error: Some(message)), cmd.none())
  }
}

// could move to a atelier/client.{save}
fn save(state) {
  let request =
    request.new()
    |> request.set_method(http.Post)
    // Note needs scheme and host setting wont use fetch defaults of being able to have just a path
    |> request.set_scheme(http.Http)
    |> request.set_host("localhost:5000")
    |> request.set_path("/save")
    |> request.prepend_header("content-type", "application/json")
    |> request.set_body(encode.to_json(state.source))

  fetch.send(request)
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

fn record(act, state) {
  let commit = case act.target {
    e.Vacant ->
      act.update(e.Empty)
      |> update_source(state, _)
    e.Empty as exp | e.Apply(e.Apply(e.Extend(_), _), _) as exp -> {
      let commit = fn(text) {
        act.update(e.Apply(e.Apply(e.Extend(text), e.Vacant), exp))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
    exp -> {
      let commit = fn(text) {
        act.update(e.Apply(e.Apply(e.Extend(text), exp), e.Empty))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn tag(act, state) {
  let commit = case act.target {
    e.Vacant -> fn(text) { act.update(e.Tag(text)) }
    exp -> fn(text) { act.update(e.Apply(e.Tag(text), exp)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn copy(act, state) {
  WorkSpace(..state, yanked: Some(act.target))
}

fn paste(act, state) {
  case state.yanked {
    Some(snippet) -> {
      let source = act.update(snippet)
      update_source(state, source)
    }
    None -> Error("nothing on clipboard")
  }
}

fn unwrap(act, state) {
  case act.parent {
    None -> Error("top level")
    Some(#(i, list, _, parent_update)) -> {
      let source = parent_update(act.target)
      update_source(state, source)
    }
  }
}

fn insert(act, state) {
  let write = fn(text, build) {
    WriteLabel(text, fn(new) { act.update(build(new)) })
  }
  try mode = case act.target {
    e.Variable(value) -> Ok(write(value, e.Variable(_)))
    e.Lambda(param, body) -> Ok(write(param, e.Lambda(_, body)))
    e.Apply(_, _) -> Error("no insert option for apply")
    e.Let(var, body, then) -> Ok(write(var, e.Let(_, body, then)))

    e.Binary(value) ->
      Ok(WriteText(value, fn(new) { act.update(e.Binary(new)) }))
    e.Integer(value) ->
      Ok(WriteNumber(value, fn(new) { act.update(e.Integer(new)) }))
    e.Tail | e.Cons -> Error("there is no insert for lists")
    e.Vacant -> Error("no insert option for vacant")
    e.Record(_, _) -> Error("insert not implemented for record")
    e.Empty -> Error("empty record no insert")
    e.Extend(label) -> Ok(write(label, e.Extend))
    e.Select(label) -> Ok(write(label, e.Select))
    e.Overwrite(label) -> Ok(write(label, e.Overwrite))
    e.Tag(label) -> Ok(write(label, e.Tag))
    e.Case(label) -> Ok(write(label, e.Case))
    e.NoCases -> Error("no cases")
    e.Match(_, _) -> Error("insert not implemented for match")
    e.Perform(label) -> Ok(write(label, e.Perform))
    e.Deep(_, _) -> Error("insert not implemented for deep")
    e.Handle(label) -> Ok(write(label, e.Handle))
  }

  Ok(WorkSpace(..state, mode: mode))
}

fn overwrite(act, state) {
  let commit = case act.target {
    e.Apply(e.Apply(e.Overwrite(_), _), _) as exp -> {
      let commit = fn(text) {
        act.update(e.Apply(e.Apply(e.Overwrite(text), e.Vacant), exp))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
    exp -> {
      let commit = fn(text) {
        // This is the same as above
        act.update(e.Apply(e.Apply(e.Overwrite(text), e.Vacant), exp))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
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
    e.Let(label, value, then) -> Error("can't get on let")
    exp -> {
      let commit = fn(text) { act.update(e.Apply(e.Select(text), exp)) }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn perform(act, state) {
  let commit = case act.target {
    e.Let(label, value, then) -> fn(text) {
      act.update(e.Let(label, e.Perform(text), then))
    }
    exp -> fn(text) { act.update(e.Perform(text)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn undo(state: WorkSpace) {
  case state.history {
    #([], _) -> Error("No history")
    #([#(source, selection), ..rest], forward) -> {
      let history = #(rest, [#(state.source, state.selection), ..forward])
      try act = transform.prepare(source, selection)
      // Has to already be in navigate mode to undo
      let mode = Navigate(act)
      Ok(
        WorkSpace(
          ..state,
          source: source,
          selection: selection,
          mode: mode,
          history: history,
        ),
      )
    }
  }
}

fn redo(state) {
  case state.history {
    #(_, []) -> Error("No redo")
    #(backward, [#(source, selection), ..rest]) -> {
      let history = #([#(state.source, state.selection), ..backward], rest)
      try act = transform.prepare(source, selection)
      // Has to already be in navigate mode to undo
      let mode = Navigate(act)
      Ok(
        WorkSpace(
          ..state,
          source: source,
          selection: selection,
          mode: mode,
          history: history,
        ),
      )
    }
  }
}

fn list(act, state) {
  let new = case act.target {
    e.Vacant -> e.Tail
    e.Tail | e.Apply(e.Apply(e.Cons, _), _) ->
      e.Apply(e.Apply(e.Cons, e.Vacant), act.target)
    _ -> e.Apply(e.Apply(e.Cons, act.target), e.Tail)
  }
  let source = act.update(new)
  update_source(state, source)
}

fn call(act, state) {
  let source = act.update(e.Apply(act.target, e.Vacant))
  update_source(state, source)
}

fn variable(act, state) {
  let commit = case act.target {
    e.Let(label, value, then) -> fn(text) {
      act.update(e.Let(label, e.Variable(text), then))
    }
    exp -> fn(text) { act.update(e.Variable(text)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn binary(act, state) {
  let commit = case act.target {
    e.Let(label, value, then) -> fn(text) {
      act.update(e.Let(label, e.Binary(text), then))
    }
    exp -> fn(text) { act.update(e.Binary(text)) }
  }
  WorkSpace(..state, mode: WriteText("", commit))
}

fn number(act, state) {
  let #(v, commit) = case act.target {
    e.Let(label, value, then) -> #(
      0,
      fn(value) { act.update(e.Let(label, e.Integer(value), then)) },
    )
    e.Integer(value) -> #(value, fn(value) { act.update(e.Integer(value)) })
    exp -> #(0, fn(value) { act.update(e.Integer(value)) })
  }
  WorkSpace(..state, mode: WriteNumber(v, commit))
}

fn match(act, state) {
  let commit = case act.target {
    // e.Let(label, value, then) -> fn(text) {
    //   act.update(e.Let(label, e.Binary(text), then))
    // }
    // Match on original value should maybe be the arg? but I like promoting first class everything
    exp -> fn(text) {
      act.update(e.Apply(e.Apply(e.Case(text), e.Vacant), exp))
    }
  }
  Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
}

fn nocases(act, state) {
  update_source(state, act.update(e.NoCases))
}

// app state actions maybe separate from ui but maybe ui files organised by mode
// update source also ends the entry state
fn update_source(state: WorkSpace, source) {
  try act = transform.prepare(source, state.selection)
  let mode = Navigate(act)
  let #(history, inferred) = case source == state.source {
    True -> #(state.history, state.inferred)
    False -> {
      let #(backwards, _forwards) = state.history
      let history = #([#(state.source, state.selection), ..backwards], [])
      #(history, standard.infer(source))
    }
  }
  Ok(
    WorkSpace(
      ..state,
      source: source,
      mode: mode,
      history: history,
      inferred: inferred,
    ),
  )
}
