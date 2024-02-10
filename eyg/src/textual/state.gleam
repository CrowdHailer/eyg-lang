import gleam/list
import lustre/effect
import eyg/parse/lexer
import eyg/parse/parser
import eyg/analysis/fast_j as j

pub type State {
  State(source: String)
}

pub fn source(state: State) {
  state.source
}

fn parse(src) {
  src
  |> lexer.lex()
  |> parser.parse()
}

pub fn information(state) {
  case parse(source(state)) {
    Ok(tree) -> {
      let #(acc, subs) = j.infer(tree, j.Empty, j.new_state())
      let acc =
        list.map(acc, fn(node) {
          let #(error, typed, effect, env) = node
          let typed = j.resolve(typed, subs.bindings)

          let effect = j.resolve(effect, subs.bindings)
          #(error, typed, effect)
        })
      Ok(#(tree, acc))
    }
    Error(reason) -> Error(reason)
  }
}

pub fn function_name() -> Nil {
  todo
}

pub fn init(_) {
  #(State(""), effect.none())
}

pub type Update {
  Input(text: String)
}

pub fn update(state, msg) {
  case msg {
    Input(text) -> {
      let state = State(text)
      #(state, effect.none())
    }
  }
}
