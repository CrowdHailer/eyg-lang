import eyg/website/components/snippet
import gleam/option.{None, Some}
import harness/impl/browser/alert
import harness/impl/browser/copy
import harness/impl/browser/paste
import lustre/effect
import morph/editable as e

const int_example = e.Block(
  [#(e.Bind("x"), e.Integer(5)), #(e.Bind("y"), e.Integer(7))],
  e.Call(e.Builtin("int_add"), [e.Variable("x"), e.Variable("y")]),
  False,
)

const text_example = e.Block(
  [#(e.Bind("x"), e.String("Hello ")), #(e.Bind("y"), e.String("World!"))],
  e.Call(e.Builtin("int_add"), [e.Variable("x"), e.Variable("y")]),
  False,
)

const functions_example = e.Block(
  [],
  e.Function([e.Bind("x"), e.Bind("y")], e.Vacant("")),
  False,
)

const lists_example = e.Block([], e.List([e.String("giraffe")], None), False)

const records_example = e.Block(
  [
    #(e.Bind("alice"), e.Record([#("name", e.String("Alice"))], None)),
    #(
      e.Bind("bob"),
      e.Record([#("name", e.String("Bob")), #("height", e.Integer(192))], None),
    ),
    #(
      e.Bind("greet"),
      e.Function(
        [e.Destructure([#("name", "name")])],
        e.Call(
          e.Builtin("string_append"),
          [e.String("Hello "), e.Variable("name")],
        ),
      ),
    ),
  ],
  e.Call(e.Variable("greet"), [e.Variable("alice")]),
  False,
)

const unions_example = e.Block(
  [],
  e.Case(
    e.Call(e.Builtin("int_parse"), [e.String("not a number")]),
    [
      #("Ok", e.Function([e.Bind("value")], e.Variable("value"))),
      #("Error", e.Function([e.Bind("_")], e.Integer(-1))),
    ],
    None,
  ),
  False,
)

const externals_example = e.Block(
  [],
  e.Call(e.Perform("Alert"), [e.String("What's up?")]),
  False,
)

pub type State {
  State(
    active: Active,
    int_example: snippet.Snippet,
    text_example: snippet.Snippet,
    functions_example: snippet.Snippet,
    lists_example: snippet.Snippet,
    records_example: snippet.Snippet,
    unions_example: snippet.Snippet,
    externals_example: snippet.Snippet,
  )
}

pub type Active {
  Editing(Example)
  Running(Example)
  Nothing
}

pub type Example {
  Numbers
  Text
  Functions
  Lists
  Records
  Unions
  Externals
}

pub fn get_example(state: State, identifier) {
  case identifier {
    Numbers -> state.int_example
    Text -> state.text_example
    Functions -> state.functions_example
    Lists -> state.lists_example
    Records -> state.records_example
    Unions -> state.unions_example
    Externals -> state.externals_example
  }
}

pub fn set_example(state: State, identifier, new) {
  case identifier {
    Numbers -> State(..state, int_example: new)
    Text -> State(..state, text_example: new)
    Functions -> State(..state, functions_example: new)
    Lists -> State(..state, lists_example: new)
    Records -> State(..state, records_example: new)
    Unions -> State(..state, unions_example: new)
    Externals -> State(..state, externals_example: new)
  }
}

pub fn effects() {
  [
    #(alert.l, #(alert.lift, alert.reply, alert.blocking)),
    #(copy.l, #(copy.lift, copy.reply(), copy.blocking)),
    #(paste.l, #(paste.lift, paste.reply(), paste.blocking)),
  ]
}

pub fn init(_) {
  #(
    State(
      Nothing,
      snippet.init(int_example, effects()),
      snippet.init(text_example, effects()),
      snippet.init(functions_example, effects()),
      snippet.init(lists_example, effects()),
      snippet.init(records_example, effects()),
      snippet.init(unions_example, effects()),
      snippet.init(externals_example, effects()),
    ),
    effect.none(),
  )
}

pub type Message {
  SnippetMessage(Example, snippet.Message)
}

pub fn update(state: State, message) {
  case message {
    SnippetMessage(identifier, message) -> {
      let state = case state.active {
        Editing(current) if current != identifier -> {
          let snippet = get_example(state, current)
          let snippet = snippet.finish_editing(snippet)
          set_example(state, current, snippet)
        }
        Running(_current) -> panic as "should not click around when running"
        _ -> state
      }
      let snippet = get_example(state, identifier)
      let #(snippet, eff) = snippet.update(snippet, message)
      let state = set_example(state, identifier, snippet)
      let state = State(..state, active: Editing(identifier))
      #(state, case eff {
        None -> effect.none()
        Some(f) ->
          effect.from(fn(d) {
            let d = fn(m) { d(SnippetMessage(identifier, m)) }
            f(d)
          })
      })
    }
  }
}
