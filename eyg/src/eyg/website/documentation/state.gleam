import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import gleam/option.{None, Some}
import harness/impl/browser/alert
import harness/impl/browser/copy
import harness/impl/browser/download
import harness/impl/browser/paste
import lustre/effect
import morph/editable as e

const int_example = e.Block(
  [#(e.Bind("x"), e.Integer(5)), #(e.Bind("y"), e.Integer(7))],
  e.Call(e.Builtin("int_add"), [e.Variable("x"), e.Variable("y")]),
  False,
)

const text_example = e.Block(
  [
    #(e.Bind("greeting"), e.String("Hello ")),
    #(e.Bind("name"), e.String("World!")),
  ],
  e.Call(
    e.Builtin("string_append"),
    [e.Variable("greeting"), e.Variable("name")],
  ),
  False,
)

const lists_example = e.Block(
  [
    #(e.Bind("items"), e.List([e.Integer(1), e.Integer(2)], None)),
    #(e.Bind("items"), e.List([e.Integer(10)], Some(e.Variable("items")))),
    #(
      e.Bind("total"),
      e.Call(
        e.Builtin("list_fold"),
        [e.Variable("items"), e.Integer(0), e.Builtin("int_add")],
      ),
    ),
  ],
  e.Variable("total"),
  False,
)

const records_example = e.Block(
  [
    #(e.Bind("alice"), e.Record([#("name", e.String("Alice"))], None)),
    #(
      e.Bind("bob"),
      e.Record([#("name", e.String("Bob")), #("height", e.Integer(192))], None),
    ),
  ],
  e.Select(e.Variable("alice"), "name"),
  False,
)

const overwrite_example = e.Block(
  [
    #(
      e.Bind("bob"),
      e.Record([#("name", e.String("Bob")), #("height", e.Integer(192))], None),
    ),
  ],
  e.Record([#("height", e.Integer(100))], Some(e.Variable("bob"))),
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

const open_case_example = e.Block(
  [],
  e.Case(
    e.Call(e.Tag("Cat"), [e.String("Felix")]),
    [#("Cat", e.Function([e.Bind("name")], e.Variable("name")))],
    Some(e.Function([e.Bind("_")], e.String("wild"))),
  ),
  False,
)

const functions_example = e.Block(
  [
    #(e.Bind("inc"), e.Call(e.Builtin("int_add"), [e.Integer(1)])),
    #(
      e.Bind("twice"),
      e.Function(
        [e.Bind("f"), e.Bind("x")],
        e.Call(e.Variable("f"), [e.Call(e.Variable("f"), [e.Variable("x")])]),
      ),
    ), #(e.Bind("inc2"), e.Call(e.Variable("twice"), [e.Variable("inc")])),
  ],
  e.Call(e.Variable("inc2"), [e.Integer(5)]),
  False,
)

const fix_example = e.Block(
  [
    #(e.Bind("inc"), e.Call(e.Builtin("int_add"), [e.Integer(1)])),
    #(
      e.Bind("count"),
      e.Call(
        e.Builtin("fix"),
        [
          e.Function(
            [e.Bind("count"), e.Bind("total"), e.Bind("rest")],
            e.Case(
              e.Call(e.Builtin("list_pop"), [e.Variable("rest")]),
              [
                #(
                  "Ok",
                  e.Function(
                    [e.Destructure([#("tail", "rest")])],
                    e.Block(
                      [
                        #(
                          e.Bind("total"),
                          e.Call(e.Variable("inc"), [e.Variable("total")]),
                        ),
                      ],
                      e.Call(
                        e.Variable("count"),
                        [e.Variable("total"), e.Variable("rest")],
                      ),
                      True,
                    ),
                  ),
                ), #("Error", e.Function([e.Bind("_")], e.Variable("total"))),
              ],
              None,
            ),
          ),
        ],
      ),
    ), #(e.Bind("count"), e.Call(e.Variable("count"), [e.Integer(0)])),
  ],
  e.Call(e.Variable("count"), [e.List([e.Integer(5)], None)]),
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
    lists_example: snippet.Snippet,
    records_example: snippet.Snippet,
    overwrite_example: snippet.Snippet,
    unions_example: snippet.Snippet,
    open_case_example: snippet.Snippet,
    externals_example: snippet.Snippet,
    functions_example: snippet.Snippet,
    fix_example: snippet.Snippet,
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
  Lists
  Records
  Overwrite
  Unions
  OpenCase
  Externals
  Functions
  Fix
}

pub fn get_example(state: State, identifier) {
  case identifier {
    Numbers -> state.int_example
    Text -> state.text_example
    Lists -> state.lists_example
    Records -> state.records_example
    Overwrite -> state.overwrite_example
    Unions -> state.unions_example
    OpenCase -> state.open_case_example
    Externals -> state.externals_example
    Functions -> state.functions_example
    Fix -> state.fix_example
  }
}

pub fn set_example(state: State, identifier, new) {
  case identifier {
    Numbers -> State(..state, int_example: new)
    Text -> State(..state, text_example: new)
    Lists -> State(..state, lists_example: new)
    Records -> State(..state, records_example: new)
    Overwrite -> State(..state, overwrite_example: new)
    Unions -> State(..state, unions_example: new)
    OpenCase -> State(..state, open_case_example: new)
    Externals -> State(..state, externals_example: new)
    Functions -> State(..state, functions_example: new)
    Fix -> State(..state, fix_example: new)
  }
}

pub fn effects() {
  [
    #(alert.l, #(alert.lift, alert.reply, alert.blocking)),
    #(copy.l, #(copy.lift, copy.reply(), copy.blocking)),
    #(download.l, #(download.lift, download.reply(), download.blocking)),
    #(paste.l, #(paste.lift, paste.reply(), paste.blocking)),
  ]
}

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  #(
    State(
      Nothing,
      snippet.init(int_example, effects(), cache),
      snippet.init(text_example, effects(), cache),
      snippet.init(lists_example, effects(), cache),
      snippet.init(records_example, effects(), cache),
      snippet.init(overwrite_example, effects(), cache),
      snippet.init(unions_example, effects(), cache),
      snippet.init(open_case_example, effects(), cache),
      snippet.init(externals_example, effects(), cache),
      snippet.init(functions_example, effects(), cache),
      snippet.init(fix_example, effects(), cache),
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
