import gleam/io
import gleam/list
import gleam/option.{None}
import lustre/effect
import plinth/browser/document
import plinth/browser/element
import plinth/browser/window
import morph/editable as e
import morph/transform
import morph/action

pub type Action =
  #(String, fn(transform.Zip) -> State)

pub type Mode {
  Navigate
  Pallet(search: String, suggestions: List(Action), offset: Int)
  RequireString(String, fn(String) -> transform.Zip)
}

pub type State {
  State(zip: transform.Zip, mode: Mode)
}

pub fn new(source) {
  State(transform.focus_at(source, [], []), Navigate)
}

pub fn init(_) {
  let source = e.Vacant
  #(new(source), effect.none())
}

pub type Message {
  KeyDown(String)
  // Update input handles all focused overlays
  UpdateInput(String)
  Do(fn(transform.Zip) -> State)
  DoIt
}

fn actions() {
  [
    #("delete", fn(zip) {
      let zip = action.delete(zip)
      State(zip, Navigate)
    }),
    #("function", fn(zip) {
      let rebuild = action.function(zip)
      update_focus()
      State(zip, RequireString("", rebuild))
    }),
    #("call function", fn(zip) {
      let zip = action.call(zip)
      State(zip, Navigate)
    }),
    #("let", fn(zip) {
      let rebuild = action.assign(zip)
      update_focus()
      State(zip, RequireString("", fn(label) { rebuild(e.Bind(label)) }))
    }),
    #("let above", fn(zip) { todo }),
    #("list", fn(zip) {
      let zip = action.list(zip)
      State(zip, Navigate)
    }),
    #("tag", fn(zip) {
      let rebuild = action.tag(zip)
      update_focus()
      State(zip, RequireString("", fn(label) { rebuild(label) }))
    }),
  ]
  // TODO require text
  // let rebuild = action.line_above(zip)
  // State(zip, RequireString("", fn(label) { rebuild(e.Bind(label)) }))
  // "call as argument",
}

fn update_focus() {
  window.request_animation_frame(fn() {
    case document.query_selector("#focus-input") {
      Ok(el) -> {
        element.focus(el)
      }
      _ -> {
        let assert Ok(el) = document.query_selector("#code")
        element.focus(el)
      }
    }
  })
}

pub fn handle(state, message) {
  let State(mode: mode, zip: zip) = state
  case message {
    KeyDown(k) -> {
      let state = case mode, k {
        Navigate, " " -> {
          update_focus()
          State(..state, mode: Pallet("", actions(), 0))
        }
        Navigate, "a" -> State(action.increase(zip), mode)
        Navigate, "s" -> State(action.decrease(zip), mode)
        Navigate, "ArrowUp" -> State(action.move_up(zip), mode)
        Navigate, "ArrowDown" -> State(action.move_down(zip), mode)
        Navigate, "ArrowLeft" -> State(action.move_left(zip), mode)
        Navigate, "ArrowRight" -> State(action.move_right(zip), mode)

        RequireString(_, _), _ -> state
        Pallet(search, actions, index), "ArrowUp" ->
          State(..state, mode: move_selection(search, actions, index, -1))
        Pallet(search, actions, index), "ArrowDown" ->
          State(..state, mode: move_selection(search, actions, index, 1))
        // let go till submit
        _, "Enter" -> state
      }
    }
    UpdateInput(value) -> update_input(state, value)
    Do(action) -> {
      update_focus()

      action(zip)
    }
    DoIt -> {
      update_focus()
      let assert RequireString(value, rebuild) = mode
      State(rebuild(value), Navigate)
    }
  }
  //     TextInput(content) -> #(State(..state, content: content), effect.none())
  //         "e" -> {
  //           let rebuild = action.assign(state.zip)
  //           let rebuild = fn(new) { rebuild(e.Bind(new)) }
  //           State(..state, mode: Insert("", rebuild))
  //         }
  //         "i" ->
  //           case transform.text(state.zip) {
  //             Ok(#(text, apply)) -> State(..state, mode: Insert(text, apply))
  //           }
  //         "p" -> {
  //           let apply = action.perform(state.zip)
  //           State(..state, mode: Insert("", apply))
  //         }
  //         "f" -> {
  //           let rebuild = action.function(state.zip)
  //           State(..state, mode: Insert("", rebuild))
  //         }
  //         _ -> {
  //           let zip = action.apply_key(k, state.zip)
  //           State(..state, zip: zip)
  //         }
  //       }
  //     TextChange(n) -> {
  //       let assert Insert(_, apply) = state.mode
  //       let mode = Insert(n, apply)
  //       let state = State(..state, mode: mode)
  //       #(state, effect.none())
  //     }
  //     ApplyChange -> {
  //       let assert Insert(v, apply) = state.mode
  //       let state = State(..state, mode: Command, zip: apply(v))
  //       #(state, effect.none())
}

pub fn update(state, message) {
  #(handle(state, message), effect.none())
}

fn update_input(state, value) {
  let State(mode: mode, ..) = state
  case mode {
    Pallet(_, actions, index) -> {
      State(..state, mode: Pallet(value, actions, index))
    }
    RequireString(_, rebuild) ->
      State(..state, mode: RequireString(value, rebuild))
  }
}

fn move_selection(search, actions, index, change) {
  let new = index + change
  let index = case 0 <= new && new < list.length(actions) {
    True -> new
    False -> index
  }
  Pallet(search, actions, index)
}
