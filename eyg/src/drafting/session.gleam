import gleam/list
import gleam/option.{type Option, Some}
import gleam/result.{try}
import morph/projection.{type Projection}
import drafting/view/utilities

pub type Mode {
  Navigate
  SelectAction(search: String, suggestions: List(Binding), index: Int)
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

pub fn handle(session, message) {
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
    _, KeyDown(_) -> Ok(session)

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
    EditString(value, rebuild), DoIt ->
      Ok(Session(bindings, rebuild(value), Navigate))
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
