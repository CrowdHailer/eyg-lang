import easel/expression/zipper
import eyg/analysis/jm/tree
import eyg/analysis/jm/type_ as t
import eygir/annotated as a
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/effect as cmd

pub type WorkSpace {
  WorkSpace(
    selection: List(Int),
    source: a.Node(Nil),
    inferred: Option(tree.State),
    mode: Mode,
    yanked: Option(a.Node(Nil)),
    error: Option(String),
    history: #(List(#(a.Node(Nil), List(Int))), List(#(a.Node(Nil), List(Int)))),
  )
}

pub type Mode {
  Navigate(actions: zipper.Zipper(Nil))
  WriteLabel(value: String, commit: fn(String) -> a.Node(Nil))
  WriteText(value: String, commit: fn(String) -> a.Node(Nil))
  WriteNumber(value: Int, commit: fn(Int) -> a.Node(Nil))
  WriteTerm(value: String, commit: fn(a.Node(Nil)) -> a.Node(Nil))
}

pub type Action {
  Keypress(key: String)
  Change(value: String)
  Commit
  SelectNode(path: List(Int))
  ClickOption(chosen: a.Node(Nil))
}

pub fn init(source) {
  let assert Ok(act) = prepare(source, [])
  let mode = Navigate(act)
  // Have inference work once for showing elements but need to also background this
  let types = do_infer(source)
  WorkSpace([], source, Some(types), mode, None, None, #([], []))
}

fn do_infer(source) {
  //  real types should be used here if this editor is salvaged
  let required = t.Var(-1)
  let #(state, _envs) = tree.infer(source, required, t.Var(-2))
  state
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
              let assert Ok(number) = int.parse(value)
              WriteNumber(number, commit)
            }
          }
        WriteText(_, commit) -> WriteText(value, commit)
        WriteTerm(_, commit) -> WriteTerm(value, commit)
        m -> m
      }
      let state = WorkSpace(..state, mode: mode)
      #(state, cmd.none())
    }
    Commit -> {
      let assert WriteText(current, commit) = state.mode
      let source = commit(current)
      let assert Ok(workspace) = update_source(state, source)
      #(workspace, cmd.none())
    }
    ClickOption(new) -> {
      let assert WriteTerm(_, commit) = state.mode
      let source = commit(new)
      let assert Ok(workspace) = update_source(state, source)
      #(workspace, cmd.none())
    }
    SelectNode(path) -> select_node(state, path)
  }
  // TypesChecked(inferred) -> {
  //   let state = WorkSpace(..state, inferred: Some(inferred))
  //   #(state, cmd.none())
  // }
}

pub fn select_node(state, path) {
  let WorkSpace(source: source, ..) = state
  let assert Ok(act) = prepare(source, path)
  let mode = Navigate(act)
  let state = WorkSpace(..state, source: source, selection: path, mode: mode)

  #(state, cmd.none())
}

// select node is desired action specific but keypress is user action specific.
// is this a problem?
// call click_node and then switch by state
// clicking a variable could use it in place
pub fn keypress(key, state: WorkSpace) {
  // save in this state only because q is a normal letter needed when entering text
  let r = case state.mode, key {
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
    Navigate(_act), "a" -> increase(state)
    Navigate(act), "s" -> decrease(act, state)
    Navigate(act), "d" -> delete(act, state)
    Navigate(act), "f" -> Ok(abstract(act, state))
    Navigate(act), "g" -> select(act, state)
    Navigate(act), "h" -> handle(act, state)
    // Navigate(act), "j" -> ("down probably not")
    // Navigate(act), "k" -> ("up probably not")
    // Navigate(act), "l" -> ("right probably not")
    Navigate(_act), "z" -> undo(state)
    Navigate(_act), "Z" -> redo(state)
    Navigate(act), "x" -> list(act, state)
    Navigate(act), "c" -> call(act, state)
    Navigate(act), "v" -> Ok(variable(act, state))
    Navigate(act), "b" -> Ok(binary(act, state))
    Navigate(act), "n" -> Ok(number(act, state))
    Navigate(act), "m" -> match(act, state)
    Navigate(act), "M" -> nocases(act, state)
    Navigate(_act), " " -> Ok(infer(state))
    Navigate(_), _ -> Error("no action for keypress")
    // Other mode
    WriteLabel(text, commit), k if k == "Enter" -> {
      let source = commit(text)
      update_source(state, source)
    }
    WriteLabel(_, _), _k -> Ok(state)
    WriteNumber(text, commit), k if k == "Enter" -> {
      let source = commit(text)
      update_source(state, source)
    }
    WriteNumber(_, _), _k -> Ok(state)
    WriteText(_, _), _k -> Ok(state)
    WriteTerm(new, commit), k if k == "Enter" -> {
      let assert [var, ..selects] = string.split(new, ".")
      let expression =
        list.fold(selects, a.variable(var), fn(acc, select) {
          a.apply(a.select(select), acc)
        })
      let source = commit(expression)
      update_source(state, source)
    }
    WriteTerm(_, _), _k -> Ok(state)
  }

  case r {
    // Always clear message on new keypress
    Ok(state) -> #(WorkSpace(..state, error: None), cmd.none())
    // cmd.from(fn(dispatch) {
    //   infer(state.source)
    //   |> TypesChecked
    //   |> dispatch()
    // }),
    Error(message) -> #(WorkSpace(..state, error: Some(message)), cmd.none())
  }
}

fn call_with(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.1(a.apply(a.vacant(), zipper.0))
  update_source(state, source)
}

// e is essentially line above on a let statement.
// nested lets can only be created from the value on the right.
// moving something to a module might just have to be copy paste
fn assign_to(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  let commit = case source.0 {
    a.Let(_, _, _) -> fn(text) { zipper.1(a.let_(text, a.vacant(), zipper.0)) }
    // normally I want to add something above
    _ -> fn(text) { zipper.1(a.let_(text, a.vacant(), source)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn record(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  case source.0 {
    a.Vacant ->
      zipper.1(a.empty())
      |> update_source(state, _)
    a.Empty | a.Apply(#(a.Apply(#(a.Extend(_), _), _), _), _) -> {
      let commit = fn(text) {
        zipper.1(a.apply(a.apply(a.extend(text), a.vacant()), source))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
    _ -> {
      let commit = fn(text) {
        zipper.1(a.apply(a.apply(a.extend(text), source), a.empty()))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn tag(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  let commit = case source.0 {
    a.Vacant -> fn(text) { zipper.1(a.tag(text)) }
    _ -> fn(text) { zipper.1(a.apply(a.tag(text), source)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn copy(zipper: zipper.Zipper(Nil), state) {
  WorkSpace(..state, yanked: Some(zipper.0))
}

fn paste(zipper: zipper.Zipper(Nil), state: WorkSpace) {
  case state.yanked {
    Some(snippet) -> {
      let source = zipper.1(snippet)
      update_source(state, source)
    }
    None -> Error("nothing on clipboard")
  }
}

fn unwrap(_zipper: zipper.Zipper(Nil), _state) {
  // I'm not really missing this
  panic as "zipper needs to expose parent"
  // case act.parent {
  //   None -> Error("top level")
  //   Some(#(_i, _list, _, parent_update)) -> {
  //     let source = parent_update(zipper.0)
  //     update_source(state, source)
  //   }
  // }
}

fn insert(zipper: zipper.Zipper(Nil), state) {
  let write = fn(text, build) {
    WriteLabel(text, fn(new) { zipper.1(build(new)) })
  }
  let source = zipper.0
  use mode <- result.then(case source.0 {
    a.Variable(value) -> Ok(write(value, a.variable(_)))
    a.Lambda(param, body) -> Ok(write(param, a.lambda(_, body)))
    a.Apply(_, _) -> Error("no insert option for apply")
    a.Let(var, body, then) -> Ok(write(var, a.let_(_, body, then)))

    a.Binary(_value) -> Error("no insert option for binary")
    a.String(value) -> Ok(WriteText(value, fn(new) { zipper.1(a.string(new)) }))
    a.Integer(value) ->
      Ok(WriteNumber(value, fn(new) { zipper.1(a.integer(new)) }))
    a.Tail | a.Cons -> Error("there is no insert for lists")
    a.Vacant -> Error("vacant no insert")
    a.Empty -> Error("empty record no insert")
    a.Extend(label) -> Ok(write(label, a.extend))
    a.Select(label) -> Ok(write(label, a.select))
    a.Overwrite(label) -> Ok(write(label, a.overwrite))
    a.Tag(label) -> Ok(write(label, a.tag))
    a.Case(label) -> Ok(write(label, a.case_))
    a.NoCases -> Error("no cases")
    a.Perform(label) -> Ok(write(label, a.perform))
    a.Handle(label) -> Ok(write(label, a.handle))
    a.Builtin(_) -> Error("no insert option for builtin, use stdlib references")
    a.Reference(_) ->
      Error("no insert option for reference, use stdlib references")
    a.NamedReference(_, _) ->
      Error("no insert option for reference, use stdlib references")
  })

  Ok(WorkSpace(..state, mode: mode))
}

fn overwrite(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  case source.0 {
    a.Apply(#(a.Apply(#(a.Overwrite(_), _), _), _), _) -> {
      let commit = fn(text) {
        zipper.1(a.apply(a.apply(a.overwrite(text), a.vacant()), source))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
    _ -> {
      let commit = fn(text) {
        // This is the same as above
        zipper.1(a.apply(a.apply(a.overwrite(text), a.vacant()), source))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn increase(state: WorkSpace) {
  use selection <- result.then(case list.reverse(state.selection) {
    [_, ..rest] -> Ok(list.reverse(rest))
    [] -> Error("no increase")
  })
  let assert Ok(act) = prepare(state.source, selection)
  Ok(WorkSpace(..state, selection: selection, mode: Navigate(act)))
}

fn decrease(_act, state: WorkSpace) {
  let selection = list.append(state.selection, [0])
  use act <- result.then(prepare(state.source, selection))
  Ok(WorkSpace(..state, selection: selection, mode: Navigate(act)))
}

fn delete(zipper: zipper.Zipper(Nil), state) {
  // an assignment vacant or not is always deleted.
  // when deleting with a vacant as a target there is no change
  // we can instead bump up the path
  let source = case zipper.0.0 {
    a.Let(_label, _, then) -> zipper.1(then)
    _ -> zipper.1(a.vacant())
  }
  update_source(state, source)
}

fn abstract(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  let commit = case source.0 {
    a.Let(label, value, then) -> fn(text) {
      zipper.1(a.let_(label, a.lambda(text, value), then))
    }
    _ -> fn(text) { zipper.1(a.lambda(text, source)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn select(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  case source.0 {
    a.Let(_label, _value, _then) -> Error("can't get on let")
    _ -> {
      let commit = fn(text) { zipper.1(a.apply(a.select(text), source)) }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn handle(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  case source.0 {
    a.Let(_label, _value, _then) -> Error("can't handle on let")
    _ -> {
      let commit = fn(text) {
        zipper.1(a.apply(a.apply(a.handle(text), a.vacant()), source))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn perform(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  let commit = case source.0 {
    a.Let(label, _value, then) -> fn(text) {
      zipper.1(a.let_(label, a.perform(text), then))
    }
    _ -> fn(text) { zipper.1(a.perform(text)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn undo(state: WorkSpace) {
  case state.history {
    #([], _) -> Error("No history")
    #([#(source, selection), ..rest], forward) -> {
      let history = #(rest, [#(state.source, state.selection), ..forward])
      use act <- result.then(prepare(source, selection))

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

fn redo(state: WorkSpace) {
  case state.history {
    #(_, []) -> Error("No redo")
    #(backward, [#(source, selection), ..rest]) -> {
      let history = #([#(state.source, state.selection), ..backward], rest)
      use act <- result.then(prepare(source, selection))
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

fn list(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  let new = case source.0 {
    a.Vacant -> a.tail()
    a.Tail | a.Apply(#(a.Apply(#(a.Cons, _), _), _), _) ->
      a.apply(a.apply(a.cons(), a.vacant()), zipper.0)
    _ -> a.apply(a.apply(a.cons(), zipper.0), a.tail())
  }
  let source = zipper.1(new)
  update_source(state, source)
}

fn call(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.1(a.apply(zipper.0, a.vacant()))
  update_source(state, source)
}

fn variable(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  let commit = case source.0 {
    a.Let(label, _value, then) -> fn(term) {
      zipper.1(a.let_(label, term, then))
    }
    _exp -> fn(term) { zipper.1(term) }
  }
  WorkSpace(..state, mode: WriteTerm("", commit))
}

fn binary(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  let commit = case source.0 {
    a.Let(label, _value, then) -> fn(text) {
      zipper.1(a.let_(label, a.string(text), then))
    }
    _exp -> fn(text) { zipper.1(a.string(text)) }
  }
  WorkSpace(..state, mode: WriteText("", commit))
}

fn number(zipper: zipper.Zipper(Nil), state) {
  let source = zipper.0
  let #(v, commit) = case source.0 {
    a.Let(label, _value, then) -> #(0, fn(value) {
      zipper.1(a.let_(label, a.integer(value), then))
    })
    a.Integer(value) -> #(value, fn(value) { zipper.1(a.integer(value)) })
    _exp -> #(0, fn(value) { zipper.1(a.integer(value)) })
  }
  WorkSpace(..state, mode: WriteNumber(v, commit))
}

fn match(zipper: zipper.Zipper(Nil), state) {
  let commit = case zipper.0 {
    // e.Let(label, value, then) -> fn(text) {
    //   zipper.1(e.Let(label, e.String(text), then))
    // }
    // Match on original value should maybe be the arg? but I like promoting first class everything
    exp -> fn(text) {
      zipper.1(a.apply(a.apply(a.case_(text), a.vacant()), exp))
    }
  }
  Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
}

fn nocases(zipper: zipper.Zipper(Nil), state) {
  update_source(state, zipper.1(a.nocases()))
}

fn infer(state: WorkSpace) {
  case state.inferred {
    // already inferred
    Some(_) -> state
    None -> {
      let inferred = do_infer(state.source)
      let state = WorkSpace(..state, inferred: Some(inferred))
      state
    }
  }
}

pub fn prepare(exp, selection) {
  zipper.at(exp, selection)
  |> result.map_error(fn(_: Nil) { "invalid_path" })
}

// app state actions maybe separate from ui but maybe ui files organised by mode
// update source also ends the entry state
fn update_source(state: WorkSpace, source) {
  use act <- result.then(prepare(source, state.selection))
  let mode = Navigate(act)
  let #(history, inferred) = case source == state.source {
    True -> #(state.history, state.inferred)
    False -> {
      let #(backwards, _forwards) = state.history
      let history = #([#(state.source, state.selection), ..backwards], [])
      #(history, None)
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
