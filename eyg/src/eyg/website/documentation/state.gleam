import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import gleam/dict.{type Dict}
import gleam/option.{None, Some}
import harness/impl/browser/alert
import harness/impl/browser/copy
import harness/impl/browser/download
import harness/impl/browser/paste
import lustre/effect
import morph/editable as e

pub const int_key = "int"

const int_example = e.Block(
  [#(e.Bind("x"), e.Integer(5)), #(e.Bind("y"), e.Integer(7))],
  e.Call(e.Builtin("int_add"), [e.Variable("x"), e.Variable("y")]),
  False,
)

pub const text_key = "text"

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

pub const lists_key = "lists"

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

pub const records_key = "records"

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

pub const overwrite_key = "overwrite"

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

pub const unions_key = "unions"

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

pub const open_case_key = "open_case"

const open_case_example = e.Block(
  [],
  e.Case(
    e.Call(e.Tag("Cat"), [e.String("Felix")]),
    [#("Cat", e.Function([e.Bind("name")], e.Variable("name")))],
    Some(e.Function([e.Bind("_")], e.String("wild"))),
  ),
  False,
)

pub const functions_key = "functions"

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

pub const fix_key = "fix"

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

pub const externals_key = "externals"

const externals_example = e.Block(
  [],
  e.Call(e.Perform("Alert"), [e.String("What's up?")]),
  False,
)

pub const capture_key = "capture"

const capture_example = e.Block(
  [],
  e.Call(e.Builtin("capture"), [e.Function([e.Bind("x")], e.Variable("x"))]),
  False,
)

pub type State {
  State(active: Active, snippets: Dict(String, snippet.Snippet))
}

pub type Active {
  Editing(String)
  Running(String)
  Nothing
}

pub fn get_example(state: State, id) {
  let assert Ok(snippet) = dict.get(state.snippets, id)
  snippet
}

pub fn set_example(state: State, id, snippet) {
  State(..state, snippets: dict.insert(state.snippets, id, snippet))
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
  let snippets = [
    #(int_key, snippet.init(int_example, effects(), cache)),
    #(text_key, snippet.init(text_example, effects(), cache)),
    #(lists_key, snippet.init(lists_example, effects(), cache)),
    #(records_key, snippet.init(records_example, effects(), cache)),
    #(overwrite_key, snippet.init(overwrite_example, effects(), cache)),
    #(unions_key, snippet.init(unions_example, effects(), cache)),
    #(open_case_key, snippet.init(open_case_example, effects(), cache)),
    #(externals_key, snippet.init(externals_example, effects(), cache)),
    #(functions_key, snippet.init(functions_example, effects(), cache)),
    #(fix_key, snippet.init(fix_example, effects(), cache)),
    #(capture_key, snippet.init(capture_example, effects(), cache)),
  ]
  #(State(Nothing, dict.from_list(snippets)), effect.none())
}

pub type Message {
  SnippetMessage(String, snippet.Message)
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
