import gleam/dynamic
import gleam/io
import gleam/list
import gleam/listx
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import lustre/attribute as a
import lustre/element/html as h
import lustre/event

pub type State(t) {
  State(
    items: List(t),
    to_identifier: fn(t) -> String,
    query: String,
    scroll_position: Option(Int),
  )
}

pub fn remaining_items(state) {
  let State(items:, to_identifier:, query:, ..) = state
  list.filter(items, fn(item) {
    let haystack = string.lowercase(to_identifier(item))
    let needle = string.lowercase(query)
    string.starts_with(haystack, needle)
  })
}

pub type Event(t) {
  Nothing
  ItemSelected(t)
  Dismiss
}

pub fn init(items, to_identifier) {
  State(items, to_identifier, "", None)
}

pub type Message {
  UserChangedQuery(query: String)
  // Could change to item but is it nice that message is not parameterised
  UserPressedUp
  UserPressedDown
  UserPressedEnter
  UserPressedEscape
  UserClickedOption(item: Int)
}

pub fn update(state, message) {
  case message {
    UserChangedQuery(new) -> {
      let state = State(..state, query: new, scroll_position: None)
      #(state, Nothing)
    }
    UserPressedUp -> {
      let remaining = remaining_items(state) |> list.length
      let scroll = case remaining, state.scroll_position {
        0, _ -> None
        _, Some(index) -> Some({ index - 1 + remaining } % remaining)
        _, None -> Some(remaining - 1)
      }
      let state = State(..state, scroll_position: scroll)
      #(state, Nothing)
    }
    UserPressedDown -> {
      let remaining = remaining_items(state) |> list.length
      let scroll = case remaining, state.scroll_position {
        0, _ -> None
        _, Some(index) -> Some({ index + 1 } % remaining)
        _, None -> Some(0)
      }
      let state = State(..state, scroll_position: scroll)
      #(state, Nothing)
    }
    UserPressedEnter -> {
      let remaining = remaining_items(state)
      case state.scroll_position {
        Some(i) ->
          case listx.at(remaining, i) {
            Ok(item) -> #(state, ItemSelected(item))
            Error(Nil) -> {
              io.debug("there should be a selection")
              #(state, Nothing)
            }
          }
        None ->
          case listx.at(remaining, 0) {
            Ok(item) -> {
              let query = state.to_identifier(item)
              let state = State(..state, query:, scroll_position: Some(0))
              #(state, Nothing)
            }
            Error(Nil) -> {
              io.debug("there should be a selection")
              #(state, Nothing)
            }
          }
      }
    }
    UserPressedEscape -> {
      let state = State(..state, scroll_position: None)
      #(state, Dismiss)
    }
    UserClickedOption(index) -> {
      case listx.at(remaining_items(state), index) {
        Ok(item) -> #(state, ItemSelected(item))
        Error(Nil) -> {
          io.debug("there should be a selection")
          #(state, Nothing)
        }
      }
    }
  }
}

pub fn render(state: State(_), item_render) {
  let query = state.query
  h.div(
    [
      a.style([
        #(
          "font-family",
          "ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, \"Liberation Mono\", \"Courier New\", monospace",
        ),
      ]),
    ],
    [
      h.input([
        a.style([
          #("line-height", "inherit"),
          #("color", "inherit"),
          #("font-family", "inherit"),
          #("font-size", "100%"),
          #("margin", "0"),
          #("outline", "2px solid transparent"),
          #("outline-offset", "2px"),
          #("padding", ".25rem"),
          #("background-color", "transparent"),
          #("border-style", "solid"),
          #("border-color", "rgb(55, 65, 81)"),
          #("border-width", "0"),
          #("border-left-width", "8px"),
          #("width", "100%"),
          #("display", "block"),
        ]),
        a.id("focus-input"),
        a.value(query),
        a.attribute("autocomplete", "off"),
        a.attribute("autofocus", "true"),
        a.required(True),
        event.on("keydown", fn(event) {
          // waiting for lustre 5.0 that uses the decode API
          use key <- result.try(dynamic.field("key", dynamic.string)(event))
          case key {
            "ArrowDown" -> Ok(UserPressedDown)
            "ArrowUp" -> Ok(UserPressedUp)
            "Enter" -> Ok(UserPressedEnter)
            "Escape" -> Ok(UserPressedEscape)
            _ -> Error([])
          }
        }),
        event.on_input(UserChangedQuery),
      ]),
      h.hr([
        a.style([
          #("border-color", "rgb(55, 65, 81)"),
          #("margin-top", ".25rem"),
          #("margin-bottom", ".25rem"),
          #("margin-left", "10rem"),
          #("margin-right", "10rem"),
          #("border-top-width", "1px"),
        ]),
      ]),
      ..list.index_map(remaining_items(state), fn(item, i) {
        let highlighted = case state.scroll_position {
          Some(j) if i == j -> True
          _ -> False
        }
        h.div(
          [
            a.style([
              #("padding-top", ".25rem"),
              #("padding-bottom", ".25rem"),
              #("padding-left", ".75rem"),
              #("padding-right", ".75rem"),
              #("display", "flex"),
              ..case highlighted {
                False -> []
                True -> [
                  #("background-color", "rgb(31, 41, 55)"),
                  #("color", "rgb(255, 255, 255)"),
                ]
              }
            ]),
            event.on_click(UserClickedOption(i)),
          ],
          item_render(item),
        )
      })
    ],
  )
}
