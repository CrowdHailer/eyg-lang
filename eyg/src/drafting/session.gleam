import gleam/dict
import gleam/int
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result.{try}
import gleam/string
import morph/projection.{type Projection}
import drafting/view/utilities
import harness/stdlib

pub type Mode {
  Navigate
  SelectAction(search: String, suggestions: List(Binding), index: Int)
  SelectVariable(search: String, index: Int, rebuild: fn(String) -> Projection)
  SelectBuiltin(
    search: String,
    suggestions: List(String),
    index: Int,
    rebuild: fn(String) -> Projection,
  )
  EditInteger(Int, fn(Int) -> Projection)
  EditString(String, fn(String) -> Projection)
}

pub type Binding {
  Binding(
    title: String,
    action: fn(Projection) -> Result(#(Projection, Mode), Nil),
    short_key: Option(String),
  )
}

pub type Session {
  Session(bindings: List(Binding), projection: Projection, mode: Mode)
}

pub fn new(bindings, source) {
  let projection = projection.focus_at(source, [], [])
  Session(bindings, projection, Navigate)
}

pub type Message {
  KeyDown(String)
  // Update input handles all focused overlays
  UpdateInput(String)
  DoIt
}

pub fn handle_key(bindings, key, projection) {
  let result =
    list.find_map(bindings, fn(binding) {
      case binding {
        Binding(_, action, Some(k)) if k == key -> Ok(action)
        _ -> Error(Nil)
      }
    })
  use action <- try(result)
  use #(projection, mode) <- try(action(projection))
  Ok(Session(bindings, projection, mode))
}

pub fn handle(session, message, get_vars) {
  let Session(bindings, projection, mode) = session
  utilities.update_focus()
  utilities.scroll_to()
  case mode, message {
    Navigate, KeyDown(" ") ->
      Ok(Session(..session, mode: SelectAction("", bindings, 0)))

    Navigate, KeyDown(key) -> handle_key(bindings, key, projection)
    // TODO use slice with pre and post, doesn't work for click maybe never do click
    SelectAction(search, actions, index), KeyDown("ArrowUp") ->
      Ok(Session(..session, mode: move_selection(search, actions, index, -1)))
    SelectAction(search, actions, index), KeyDown("ArrowDown") ->
      Ok(Session(..session, mode: move_selection(search, actions, index, 1)))
    // TODO select action enter
    _, KeyDown("Escape") -> Ok(Session(..session, mode: Navigate))
    SelectAction(_, _, _), KeyDown(_) -> Ok(session)

    Navigate, UpdateInput(_) -> panic as "this state should never arrise"
    SelectAction(_, suggestions, index), UpdateInput(value) ->
      Ok(Session(..session, mode: SelectAction(value, suggestions, index)))
    EditString(_, rebuild), UpdateInput(value) ->
      Ok(Session(..session, mode: EditString(value, rebuild)))
    SelectAction(_, actions, index), DoIt -> {
      let assert Ok(Binding(_, action, _)) = list.at(actions, index)
      use #(projection, mode) <- try(action(projection))
      Ok(Session(bindings, projection, mode))
    }

    // suggestions from previous are not used maybe don't store
    // but how does the index stay in sync
    // Note if no suggest cleave can't exist
    SelectBuiltin(_, suggestions, index, rebuild), UpdateInput(value) -> {
      let suggestions =
        stdlib.env().builtins
        |> dict.keys()
        |> list.filter(string.contains(_, value))

      let mode = SelectBuiltin(value, suggestions, 0, rebuild)
      Ok(Session(..session, mode: mode))
    }
    SelectBuiltin(search, suggestions, index, rebuild), KeyDown("ArrowUp") -> {
      let index = int.clamp(index - 1, 0, list.length(suggestions))
      let mode = SelectBuiltin(search, suggestions, index, rebuild)
      Ok(Session(..session, mode: mode))
    }
    SelectBuiltin(search, suggestions, index, rebuild), KeyDown("ArrowDown") -> {
      let index = int.clamp(index + 1, 0, list.length(suggestions))
      let mode = SelectBuiltin(search, suggestions, index, rebuild)
      Ok(Session(..session, mode: mode))
    }
    SelectBuiltin(_, _, _, _), KeyDown(_) -> Ok(session)
    SelectBuiltin(_, suggestions, index, rebuild), DoIt -> {
      let assert Ok(builtin) = list.at(suggestions, index)
      let projection = rebuild(builtin)
      Ok(Session(bindings, projection, Navigate))
    }

    SelectVariable(_, index, rebuild), UpdateInput(value) -> {
      let mode = SelectVariable(value, 0, rebuild)
      Ok(Session(..session, mode: mode))
    }
    SelectVariable(search, index, rebuild), KeyDown("ArrowUp") -> {
      let mode = SelectVariable(search, index - 1, rebuild)
      Ok(Session(..session, mode: mode))
    }
    SelectVariable(search, index, rebuild), KeyDown("ArrowDown") -> {
      let mode = SelectVariable(search, index + 1, rebuild)

      Ok(Session(..session, mode: mode))
    }
    SelectVariable(_, _, _), KeyDown(_) -> Ok(session)
    SelectVariable(value, index, rebuild), DoIt -> {
      // let assert Ok(builtin) = list.at(suggestions, index)
      // let projection = rebuild(builtin)
      // Ok(Session(bindings, projection, Navigate))

      // TODO what is the best way to pass suggestions around
      let vars = get_vars()
      let vars = list.filter(vars, string.contains(_, value))
      let index = index % list.length(vars)
      let assert Ok(variable) = list.at(vars, index)
      let projection = rebuild(variable)
      Ok(Session(bindings, projection, Navigate))
    }

    EditString(value, rebuild), KeyDown(_) -> Ok(session)
    EditString(value, rebuild), DoIt ->
      Ok(Session(bindings, rebuild(value), Navigate))
    EditInteger(value, rebuild), KeyDown(_) -> Ok(session)
    EditInteger(_, rebuild), UpdateInput(value) -> {
      let assert Ok(value) = int.parse(value)
      Ok(Session(..session, mode: EditInteger(value, rebuild)))
    }
    EditInteger(value, rebuild), DoIt ->
      Ok(Session(bindings, rebuild(value), Navigate))
    EditInteger(value, rebuild), _ ->
      panic as "why would there be an int update"

    Navigate, DoIt -> panic as "nothing to do in navigate mode"
  }
}

fn move_selection(search, actions, index, change) {
  let new = index + change
  let index = case 0 <= new && new < list.length(actions) {
    True -> new
    False -> index
  }
  SelectAction(search, actions, index)
}
