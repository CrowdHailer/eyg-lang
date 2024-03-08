import gleam/io
import gleam/option.{None}
import lustre/effect
import morph/editable as e
import morph/projection
import morph/action

pub type Mode {
  Command
  Insert(String, fn(String) -> projection.Zip)
}

pub type State {
  State(content: String, zip: projection.Zip, mode: Mode)
}

pub fn init(_) {
  let source =
    e.Block(
      [
        #(e.Bind("x"), e.Integer(5)),
        #(e.Destructure([#("x", "x"), #("y", "a")]), e.Integer(5)),
      ],
      e.List(
        [e.Call(e.Variable("f"), [e.String("hello"), e.String("world")])],
        None,
      ),
    )
  let zip = projection.focus_at(source, [2, 0, 1], [])
  #(State("hello", zip, Command), effect.none())
}

pub type TextInput {
  TextInput(String)
  KeyDown(String)
  TextChange(String)
  ApplyChange
}

pub fn update(state, message) {
  case message {
    TextInput(content) -> #(State(..state, content: content), effect.none())
    KeyDown(k) -> {
      let state = case k {
        "e" -> {
          let rebuild = action.assign(state.zip)
          let rebuild = fn(new) { rebuild(e.Bind(new)) }
          State(..state, mode: Insert("", rebuild))
        }
        "i" ->
          case projection.text(state.zip) {
            Ok(#(text, apply)) -> State(..state, mode: Insert(text, apply))
          }
        "p" -> {
          let apply = action.perform(state.zip)
          State(..state, mode: Insert("", apply))
        }
        "f" -> {
          let rebuild = action.function(state.zip)
          State(..state, mode: Insert("", rebuild))
        }
        _ -> {
          let zip = action.apply_key(k, state.zip)
          State(..state, zip: zip)
        }
      }
      #(state, effect.none())
    }
    TextChange(n) -> {
      let assert Insert(_, apply) = state.mode
      let mode = Insert(n, apply)
      let state = State(..state, mode: mode)
      #(state, effect.none())
    }
    ApplyChange -> {
      let assert Insert(v, apply) = state.mode
      let state = State(..state, mode: Command, zip: apply(v))
      #(state, effect.none())
    }
  }
}
