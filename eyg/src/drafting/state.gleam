import gleam/io
import gleam/list
import gleam/option.{None}
import lustre/effect
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

pub fn init(_) {
  let source = e.Vacant
  let zip = transform.focus_at(source, [], [])
  #(State(zip, Navigate), effect.none())
}

pub type Message {
  KeyDown(String)
  // Update input handles all focused overlays
  UpdateInput(String)
  Do(fn(transform.Zip) -> State)
  DoIt
  //   TextInput(String)
}

//   TextChange(String)
//   ApplyChange

fn actions() {
  [
    #("delete", fn(zip) {
      let zip = action.delete(zip)
      State(zip, Navigate)
    }),
    #("function", fn(zip) {
      let rebuild = action.function(zip)
      State(zip, RequireString("", rebuild))
    }),
    #("let", fn(zip) {
      let rebuild = action.assign(zip)
      State(zip, RequireString("", fn(label) { rebuild(e.Bind(label)) }))
    }),
  ]
  // "call as argument",
  // "call function",
  // "list",
  // "insert above",
}

pub fn update(state, message) {
  let State(mode: mode, zip: zip) = state
  case message {
    KeyDown(k) -> {
      let state = case mode, k {
        Navigate, " " -> #(
          State(..state, mode: Pallet("", actions(), 0)),
          effect.none(),
        )
        RequireString(_, _), _ -> #(state, effect.none())
        Pallet(search, actions, index), "ArrowUp" -> #(
          State(..state, mode: move_selection(search, actions, index, -1)),
          effect.none(),
        )
        Pallet(search, actions, index), "ArrowDown" -> #(
          State(..state, mode: move_selection(search, actions, index, 1)),
          effect.none(),
        )
      }
    }
    UpdateInput(value) -> update_input(state, value)
    Do(action) -> #(action(zip), effect.none())
    DoIt -> {
      let assert RequireString(value, rebuild) = mode
      #(State(rebuild(value), Navigate), effect.none())
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

fn update_input(state, value) {
  let State(mode: mode, ..) = state
  case mode {
    Pallet(_, actions, index) -> {
      #(State(..state, mode: Pallet(value, actions, index)), effect.none())
    }
    RequireString(_, rebuild) -> #(
      State(..state, mode: RequireString(value, rebuild)),
      effect.none(),
    )
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
