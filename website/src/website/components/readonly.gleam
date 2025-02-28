import eyg/ir/dag_json
import gleam/bit_array

// TODO remove
import gleam/dynamicx
import gleam/int
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element/html as h
import lustre/event
import morph/editable as e
import morph/lustre/frame
import morph/lustre/render
import morph/navigation
import morph/projection as p
import morph/utils
import plinth/browser/clipboard
import plinth/browser/element as dom_element
import plinth/browser/event as pevent
import plinth/javascript/console

pub type Status {
  Idle
  Selecting
}

pub type Readonly {
  Readonly(
    status: Status,
    expanding: Option(List(Int)),
    projection: p.Projection,
    source: e.Expression,
  )
}

pub fn new(source) {
  Readonly(Idle, None, p.focus_at(source, []) |> navigation.next, source)
}

pub fn init(editable) {
  let editable = e.open_all(editable)
  let projection = navigation.first(editable)
  Readonly(Idle, None, projection, editable)
}

pub type Message {
  UserFocusedOnCode
  UserPressedCommandKey(String)
  UserClickedCode(List(Int))
  ClipboardWriteCompleted(Result(Nil, String))
}

pub fn write_to_clipboard(text) {
  promise.map(clipboard.write_text(text), ClipboardWriteCompleted)
}

pub type Effect {
  Nothing
  MoveAbove
  MoveBelow
  WriteToClipboard(String)
  Fail(String)
}

pub fn update(state, message) {
  let Readonly(
    status: status,
    expanding: expanding,
    projection: projection,
    source: source,
  ) = state
  case message, status {
    UserFocusedOnCode, _ -> #(Readonly(..state, status: Selecting), Nothing)
    UserPressedCommandKey(key), Selecting -> {
      case key {
        "ArrowRight" -> #(
          Readonly(..state, projection: navigation.next(projection)),
          Nothing,
        )
        "ArrowLeft" -> #(
          Readonly(..state, projection: navigation.previous(projection)),
          Nothing,
        )
        "ArrowUp" ->
          case navigation.move_up(projection) {
            Ok(projection) -> #(Readonly(..state, projection:), Nothing)
            Error(Nil) -> #(state, MoveAbove)
          }
        "ArrowDown" ->
          case navigation.move_down(projection) {
            Ok(projection) -> #(Readonly(..state, projection:), Nothing)
            Error(Nil) -> #(state, MoveAbove)
          }
        // "Q" -> copy_escaped(state)
        "y" -> copy(state)
        "a" -> increase(state)
        "k" -> toggle_open(state)

        _ -> #(state, Fail("no action for " <> key))
      }
    }
    UserPressedCommandKey(_), _ -> panic as "should never get a buffer message"

    UserClickedCode(path), _ ->
      case projection, p.path(projection) == path {
        #(p.Assign(p.AssignStatement(_), _, _, _, _), _), True ->
          toggle_open(state)
        _, _ ->
          case
            // listx.starts_with(path, p.path(proj))
            // path expanding real just means it was the last thing clicked
            Some(path) == expanding && p.path(projection) != []
          {
            True -> increase(state)
            False -> {
              let state = Readonly(..state, expanding: Some(path))
              let projection = p.focus_at(source, path)
              #(Readonly(..state, projection: projection), Nothing)
            }
          }
      }

    ClipboardWriteCompleted(return), _ ->
      case return {
        Ok(Nil) -> #(state, Nothing)
        Error(_) -> #(state, Fail("failed to paste"))
      }
  }
}

fn toggle_open(state) {
  let Readonly(projection: projection, ..) = state

  let projection = navigation.toggle_open(projection)
  #(Readonly(..state, projection: projection), Nothing)
}

fn increase(state) {
  let Readonly(projection: projection, ..) = state

  case navigation.increase(projection) {
    Ok(new) -> #(Readonly(..state, projection: new), Nothing)
    Error(Nil) -> #(state, Fail("already fully selected"))
  }
}

fn copy(state) {
  let Readonly(projection: projection, ..) = state

  case projection {
    #(p.Exp(expression), _) -> {
      let assert Ok(text) =
        e.to_annotated(expression, [])
        |> dag_json.to_block()
        |> bit_array.to_string()
      #(state, WriteToClipboard(text))
    }
    _ -> #(state, Fail("can only copy expressions"))
  }
}

pub fn render(state) {
  let Readonly(status: status, projection: projection, source: source, ..) =
    state

  // There is no analysis on readonly so no errors It might be useful to have them but I also want to get rid of readonly so it's closer to regular projection
  let errors = []
  case status {
    Selecting -> {
      let #(_focus, zoom) = projection

      //   actual_render_projection(proj, autofocus)
      let frame =
        render.projection_frame(projection, render.ReadonlyStatements, errors)
      let projection_rendered =
        render.push_render(frame, zoom, render.ReadonlyStatements, errors)
        |> frame.to_fat_line
      h.div(
        [
          a.class("outline-none"),
          a.attribute("tabindex", "0"),
          // a.autofocus(True),
          event.on("click", fn(event) {
            let assert Ok(e) = pevent.cast_event(event)
            let target = pevent.target(e)
            let rev =
              target
              |> dynamicx.unsafe_coerce
              |> dom_element.dataset_get("rev")
            case rev {
              Ok(rev) -> {
                let assert Ok(rev) = case rev {
                  "" -> Ok([])
                  _ ->
                    string.split(rev, ",")
                    |> list.try_map(int.parse)
                }
                Ok(UserClickedCode(list.reverse(rev)))
              }
              Error(_) -> {
                console.log(target)
                Error([])
              }
            }
          }),
          utils.on_hotkey(UserPressedCommandKey),
        ],
        [projection_rendered],
      )
    }
    Idle ->
      h.div(
        [
          a.class("outline-none whitespace-nowrap overflow-auto"),
          a.attribute("tabindex", "0"),
          event.on_focus(UserFocusedOnCode),
        ],
        render.statements(source, errors),
      )
  }
}
