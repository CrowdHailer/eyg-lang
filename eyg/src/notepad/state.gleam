import gleam/option.{None}
import lustre/effect
import morph/editable as e
import morph/transform
import morph/action

pub type State {
  State(content: String, zip: transform.Zip)
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
  let zip = transform.focus_at(source, [1], [])
  #(State("hello", zip), effect.none())
}

pub type TextInput {
  TextInput(String)
  KeyDown(String)
}

pub fn update(state, message) {
  case message {
    TextInput(content) -> #(State(..state, content: content), effect.none())
    KeyDown(k) -> {
      let zip = action.apply_key(k, state.zip)
      #(State(..state, zip: zip), effect.none())
    }
  }
}
