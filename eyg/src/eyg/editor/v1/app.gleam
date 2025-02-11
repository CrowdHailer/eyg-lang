import eygir/annotated
import gleam/result

// this can define state and UI maybe UI should be separate
import easel/expression/zipper
import eyg/analysis/jm/tree
import eyg/analysis/jm/type_ as t
import eygir/expression as e
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/effect as cmd

pub type WorkSpace {
  WorkSpace(
    selection: List(Int),
    source: e.Expression,
    inferred: Option(tree.State),
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
  Navigate(actions: zipper.Zipper)
  WriteLabel(value: String, commit: fn(String) -> e.Expression)
  WriteText(value: String, commit: fn(String) -> e.Expression)
  WriteNumber(value: Int, commit: fn(Int) -> e.Expression)
  WriteTerm(value: String, commit: fn(e.Expression) -> e.Expression)
}

pub type Action {
  Keypress(key: String)
  Change(value: String)
  Commit
  SelectNode(path: List(Int))
  ClickOption(chosen: e.Expression)
}

pub fn init(source) {
  let assert Ok(act) = prepare(source, [])
  let mode = Navigate(act)
  // Have inference work once for showing elements but need to also background this
  let types = do_infer(source |> annotated.add_annotation(Nil))
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
        list.fold(selects, e.Variable(var), fn(acc, select) {
          e.Apply(e.Select(select), acc)
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

fn call_with(zipper: zipper.Zipper, state) {
  let source = zipper.1(e.Apply(e.Vacant, zipper.0))
  update_source(state, source)
}

// e is essentially line above on a let statement.
// nested lets can only be created from the value on the right.
// moving something to a module might just have to be copy paste
fn assign_to(zipper: zipper.Zipper, state) {
  let commit = case zipper.0 {
    e.Let(_, _, _) -> fn(text) { zipper.1(e.Let(text, e.Vacant, zipper.0)) }
    // normally I want to add something above
    exp -> fn(text) { zipper.1(e.Let(text, e.Vacant, exp)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn record(zipper: zipper.Zipper, state) {
  case zipper.0 {
    e.Vacant ->
      zipper.1(e.Empty)
      |> update_source(state, _)
    e.Empty as exp | e.Apply(e.Apply(e.Extend(_), _), _) as exp -> {
      let commit = fn(text) {
        zipper.1(e.Apply(e.Apply(e.Extend(text), e.Vacant), exp))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
    exp -> {
      let commit = fn(text) {
        zipper.1(e.Apply(e.Apply(e.Extend(text), exp), e.Empty))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn tag(zipper: zipper.Zipper, state) {
  let commit = case zipper.0 {
    e.Vacant -> fn(text) { zipper.1(e.Tag(text)) }
    exp -> fn(text) { zipper.1(e.Apply(e.Tag(text), exp)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn copy(zipper: zipper.Zipper, state) {
  WorkSpace(..state, yanked: Some(zipper.0))
}

fn paste(zipper: zipper.Zipper, state: WorkSpace) {
  case state.yanked {
    Some(snippet) -> {
      let source = zipper.1(snippet)
      update_source(state, source)
    }
    None -> Error("nothing on clipboard")
  }
}

fn unwrap(_zipper: zipper.Zipper, _state) {
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

fn insert(zipper: zipper.Zipper, state) {
  let write = fn(text, build) {
    WriteLabel(text, fn(new) { zipper.1(build(new)) })
  }
  use mode <- result.then(case zipper.0 {
    e.Variable(value) -> Ok(write(value, e.Variable(_)))
    e.Lambda(param, body) -> Ok(write(param, e.Lambda(_, body)))
    e.Apply(_, _) -> Error("no insert option for apply")
    e.Let(var, body, then) -> Ok(write(var, e.Let(_, body, then)))

    e.Binary(_value) -> Error("no insert option for binary")
    e.Str(value) -> Ok(WriteText(value, fn(new) { zipper.1(e.Str(new)) }))
    e.Integer(value) ->
      Ok(WriteNumber(value, fn(new) { zipper.1(e.Integer(new)) }))
    e.Tail | e.Cons -> Error("there is no insert for lists")
    e.Vacant -> Error("vacant no insert")
    e.Empty -> Error("empty record no insert")
    e.Extend(label) -> Ok(write(label, e.Extend))
    e.Select(label) -> Ok(write(label, e.Select))
    e.Overwrite(label) -> Ok(write(label, e.Overwrite))
    e.Tag(label) -> Ok(write(label, e.Tag))
    e.Case(label) -> Ok(write(label, e.Case))
    e.NoCases -> Error("no cases")
    e.Perform(label) -> Ok(write(label, e.Perform))
    e.Handle(label) -> Ok(write(label, e.Handle))
    e.Builtin(_) -> Error("no insert option for builtin, use stdlib references")
    e.Reference(_) ->
      Error("no insert option for reference, use stdlib references")
    e.NamedReference(_, _) ->
      Error("no insert option for reference, use stdlib references")
  })

  Ok(WorkSpace(..state, mode: mode))
}

fn overwrite(zipper: zipper.Zipper, state) {
  case zipper.0 {
    e.Apply(e.Apply(e.Overwrite(_), _), _) as exp -> {
      let commit = fn(text) {
        zipper.1(e.Apply(e.Apply(e.Overwrite(text), e.Vacant), exp))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
    exp -> {
      let commit = fn(text) {
        // This is the same as above
        zipper.1(e.Apply(e.Apply(e.Overwrite(text), e.Vacant), exp))
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

fn delete(zipper: zipper.Zipper, state) {
  // an assignment vacant or not is always deleted.
  // when deleting with a vacant as a target there is no change
  // we can instead bump up the path
  let source = case zipper.0 {
    e.Let(_label, _, then) -> zipper.1(then)
    _ -> zipper.1(e.Vacant)
  }
  update_source(state, source)
}

fn abstract(zipper: zipper.Zipper, state) {
  let commit = case zipper.0 {
    e.Let(label, value, then) -> fn(text) {
      zipper.1(e.Let(label, e.Lambda(text, value), then))
    }
    exp -> fn(text) { zipper.1(e.Lambda(text, exp)) }
  }
  WorkSpace(..state, mode: WriteLabel("", commit))
}

fn select(zipper: zipper.Zipper, state) {
  case zipper.0 {
    e.Let(_label, _value, _then) -> Error("can't get on let")
    exp -> {
      let commit = fn(text) { zipper.1(e.Apply(e.Select(text), exp)) }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn handle(zipper: zipper.Zipper, state) {
  case zipper.0 {
    e.Let(_label, _value, _then) -> Error("can't handle on let")
    exp -> {
      let commit = fn(text) {
        zipper.1(e.Apply(e.Apply(e.Handle(text), e.Vacant), exp))
      }
      Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
    }
  }
}

fn perform(zipper: zipper.Zipper, state) {
  let commit = case zipper.0 {
    e.Let(label, _value, then) -> fn(text) {
      zipper.1(e.Let(label, e.Perform(text), then))
    }
    _exp -> fn(text) { zipper.1(e.Perform(text)) }
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

fn list(zipper: zipper.Zipper, state) {
  let new = case zipper.0 {
    e.Vacant -> e.Tail
    e.Tail | e.Apply(e.Apply(e.Cons, _), _) ->
      e.Apply(e.Apply(e.Cons, e.Vacant), zipper.0)
    _ -> e.Apply(e.Apply(e.Cons, zipper.0), e.Tail)
  }
  let source = zipper.1(new)
  update_source(state, source)
}

fn call(zipper: zipper.Zipper, state) {
  let source = zipper.1(e.Apply(zipper.0, e.Vacant))
  update_source(state, source)
}

fn variable(zipper: zipper.Zipper, state) {
  let commit = case zipper.0 {
    e.Let(label, _value, then) -> fn(term) {
      zipper.1(e.Let(label, term, then))
    }
    _exp -> fn(term) { zipper.1(term) }
  }
  WorkSpace(..state, mode: WriteTerm("", commit))
}

fn binary(zipper: zipper.Zipper, state) {
  let commit = case zipper.0 {
    e.Let(label, _value, then) -> fn(text) {
      zipper.1(e.Let(label, e.Str(text), then))
    }
    _exp -> fn(text) { zipper.1(e.Str(text)) }
  }
  WorkSpace(..state, mode: WriteText("", commit))
}

fn number(zipper: zipper.Zipper, state) {
  let #(v, commit) = case zipper.0 {
    e.Let(label, _value, then) -> #(0, fn(value) {
      zipper.1(e.Let(label, e.Integer(value), then))
    })
    e.Integer(value) -> #(value, fn(value) { zipper.1(e.Integer(value)) })
    _exp -> #(0, fn(value) { zipper.1(e.Integer(value)) })
  }
  WorkSpace(..state, mode: WriteNumber(v, commit))
}

fn match(zipper: zipper.Zipper, state) {
  let commit = case zipper.0 {
    // e.Let(label, value, then) -> fn(text) {
    //   zipper.1(e.Let(label, e.Str(text), then))
    // }
    // Match on original value should maybe be the arg? but I like promoting first class everything
    exp -> fn(text) { zipper.1(e.Apply(e.Apply(e.Case(text), e.Vacant), exp)) }
  }
  Ok(WorkSpace(..state, mode: WriteLabel("", commit)))
}

fn nocases(zipper: zipper.Zipper, state) {
  update_source(state, zipper.1(e.NoCases))
}

fn infer(state: WorkSpace) {
  case state.inferred {
    // already inferred
    Some(_) -> state
    None -> {
      let inferred = do_infer(state.source |> annotated.add_annotation(Nil))
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
