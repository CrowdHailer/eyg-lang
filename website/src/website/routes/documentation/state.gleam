import eyg/ir/dag_json
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/javascript/promisex
import gleam/option.{type Option, None, Some}
import lustre/effect
import morph/editable as e
import website/components/auth_panel
import website/components/snippet
import website/harness/browser as harness
import website/sync/client

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
    ),
    #(e.Bind("inc2"), e.Call(e.Variable("twice"), [e.Variable("inc")])),
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
                ),
                #("Error", e.Function([e.Bind("_")], e.Variable("total"))),
              ],
              None,
            ),
          ),
        ],
      ),
    ),
    #(e.Bind("count"), e.Call(e.Variable("count"), [e.Integer(0)])),
  ],
  e.Call(e.Variable("count"), [e.List([e.Integer(5)], None)]),
  False,
)

pub const builtins_key = "builtins"

const builtins_example = "{\"0\":\"l\",\"l\":\"total\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"int_multiply\"},\"a\":{\"0\":\"i\",\"v\":90}},\"a\":{\"0\":\"i\",\"v\":3}},\"t\":{\"0\":\"l\",\"l\":\"total\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"int_to_string\"},\"a\":{\"0\":\"v\",\"l\":\"total\"}},\"t\":{\"0\":\"l\",\"l\":\"notice\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"s\",\"v\":\"The total is: \"}},\"a\":{\"0\":\"v\",\"l\":\"total\"}},\"t\":{\"0\":\"v\",\"l\":\"notice\"}}}}"

pub const references_key = "references"

const references_example = "{\"0\":\"l\",\"l\":\"std\",\"v\":{\"0\":\"@\",\"l\":{\"/\":\"baguqeeragtrji4oxi2ro6bpuo6bqiogjrwhvnmung3d7z5uf4hriebz5ujua\"},\"p\":\"standard\",\"r\":1},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"contains\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"list\"},\"a\":{\"0\":\"v\",\"l\":\"std\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"i\",\"v\":1}},\"a\":{\"0\":\"ta\"}}},\"a\":{\"0\":\"i\",\"v\":0}}}"

pub const externals_key = "externals"

const externals_example = e.Block(
  [],
  e.Call(e.Perform("Alert"), [e.String("What's up?")]),
  False,
)

pub const perform_key = "perform"

const perform_example = "{\"0\":\"l\",\"l\":\"question\",\"v\":{\"0\":\"s\",\"v\":\"Hello, What is your name?\"},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"name\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Alert\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"s\",\"v\":\"hello,\"}},\"a\":{\"0\":\"v\",\"l\":\"name\"}}}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Alert\"},\"a\":{\"0\":\"s\",\"v\":\"I didn't catch your name.\"}}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Prompt\"},\"a\":{\"0\":\"v\",\"l\":\"question\"}}}}"

pub const handle_key = "handle"

pub const handle_example = "{\"0\":\"l\",\"l\":\"capture\",\"v\":{\"0\":\"f\",\"l\":\"exec\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"h\",\"l\":\"Alert\"},\"a\":{\"0\":\"f\",\"l\":\"value\",\"b\":{\"0\":\"f\",\"l\":\"resume\",\"b\":{\"0\":\"l\",\"l\":\"$\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"resume\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"l\",\"l\":\"return\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"return\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"l\",\"l\":\"alerts\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"alerts\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"return\"},\"a\":{\"0\":\"v\",\"l\":\"return\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"alerts\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"v\",\"l\":\"value\"}},\"a\":{\"0\":\"v\",\"l\":\"alerts\"}}},\"a\":{\"0\":\"u\"}}}}}}}}},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"alerts\"},\"a\":{\"0\":\"ta\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"return\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"exec\"},\"a\":{\"0\":\"u\"}}},\"a\":{\"0\":\"u\"}}}}}},\"t\":{\"0\":\"l\",\"l\":\"run\",\"v\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"_\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Alert\"},\"a\":{\"0\":\"s\",\"v\":\"first\"}},\"t\":{\"0\":\"l\",\"l\":\"_\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Alert\"},\"a\":{\"0\":\"s\",\"v\":\"second\"}},\"t\":{\"0\":\"u\"}}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"capture\"},\"a\":{\"0\":\"v\",\"l\":\"run\"}}}}"

pub const multiple_resume_key = "multiple_resume"

pub const multiple_resume_example = "{\"0\":\"l\",\"l\":\"std\",\"v\":{\"0\":\"@\",\"l\":{\"/\":\"baguqeeragtrji4oxi2ro6bpuo6bqiogjrwhvnmung3d7z5uf4hriebz5ujua\"},\"p\":\"standard\",\"r\":1},\"t\":{\"0\":\"l\",\"l\":\"capture\",\"v\":{\"0\":\"f\",\"l\":\"exec\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"h\",\"l\":\"Flip\"},\"a\":{\"0\":\"f\",\"l\":\"value\",\"b\":{\"0\":\"f\",\"l\":\"resume\",\"b\":{\"0\":\"l\",\"l\":\"truthy\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"resume\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"True\"},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"l\",\"l\":\"falsy\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"resume\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"False\"},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"flatten\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"list\"},\"a\":{\"0\":\"v\",\"l\":\"std\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"v\",\"l\":\"truthy\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"v\",\"l\":\"falsy\"}},\"a\":{\"0\":\"ta\"}}}}}}}}},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"exec\"},\"a\":{\"0\":\"u\"}}},\"a\":{\"0\":\"ta\"}}}}},\"t\":{\"0\":\"l\",\"l\":\"run\",\"v\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"first\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Flip\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"l\",\"l\":\"second\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Flip\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"second\"},\"a\":{\"0\":\"v\",\"l\":\"second\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"first\"},\"a\":{\"0\":\"v\",\"l\":\"first\"}},\"a\":{\"0\":\"u\"}}}}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"capture\"},\"a\":{\"0\":\"v\",\"l\":\"run\"}}}}}"

pub const capture_key = "capture"

const capture_example = "{\"0\":\"l\",\"l\":\"greeting\",\"v\":{\"0\":\"s\",\"v\":\"hey\"},\"t\":{\"0\":\"l\",\"l\":\"ignored\",\"v\":{\"0\":\"s\",\"v\":\"this string doesn't get transpiled\"},\"t\":{\"0\":\"l\",\"l\":\"func\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"to_javascript\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"v\",\"l\":\"greeting\"}},\"a\":{\"0\":\"s\",\"v\":\"Alice\"}}}},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"v\",\"l\":\"func\"}}}}"

pub type State {
  State(
    auth: auth_panel.State,
    cache: client.Client,
    active: Active,
    snippets: Dict(String, snippet.Snippet),
  )
}

pub type Active {
  Editing(String, Option(snippet.Failure))
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

fn init_example(json, cache) {
  let assert Ok(source) = dag_json.from_block(bit_array.from_string(json))
  let source =
    e.from_annotated(source)
    |> e.open_all
  snippet.init(source, [], harness.effects(), cache)
}

pub fn init(_) {
  let sync = client.init()
  let snippets = [
    #(int_key, snippet.init(int_example, [], harness.effects(), sync.cache)),
    #(text_key, snippet.init(text_example, [], harness.effects(), sync.cache)),
    #(lists_key, snippet.init(lists_example, [], harness.effects(), sync.cache)),
    #(
      records_key,
      snippet.init(records_example, [], harness.effects(), sync.cache),
    ),
    #(
      overwrite_key,
      snippet.init(overwrite_example, [], harness.effects(), sync.cache),
    ),
    #(
      unions_key,
      snippet.init(unions_example, [], harness.effects(), sync.cache),
    ),
    #(
      open_case_key,
      snippet.init(open_case_example, [], harness.effects(), sync.cache),
    ),
    #(
      externals_key,
      snippet.init(externals_example, [], harness.effects(), sync.cache),
    ),
    #(
      functions_key,
      snippet.init(functions_example, [], harness.effects(), sync.cache),
    ),
    #(fix_key, snippet.init(fix_example, [], harness.effects(), sync.cache)),
    #(builtins_key, init_example(builtins_example, sync.cache)),
    #(references_key, init_example(references_example, sync.cache)),
    #(perform_key, init_example(perform_example, sync.cache)),
    #(handle_key, init_example(handle_example, sync.cache)),
    #(multiple_resume_key, init_example(multiple_resume_example, sync.cache)),
    #(capture_key, init_example(capture_example, sync.cache)),
  ]
  let #(auth, task) = auth_panel.init(Nil)
  let state = State(auth, sync, Nothing, dict.from_list(snippets))
  let assert Ok(storage) = auth_panel.local_storage("session")
  #(
    state,
    effect.batch([
      auth_panel.dispatch(task, AuthMessage, storage),
      client.fetch_index_effect(SyncMessage),
      client.fetch_missing(state.snippets, SyncMessage),
    ]),
  )
}

pub type RunMessage {
  Start
}

pub type Message {
  SnippetMessage(String, snippet.Message)
  RunMessage(String, RunMessage)
  SyncMessage(client.Message)
  AuthMessage(auth_panel.Message)
}

fn dispatch_to_snippet(id, promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) { d(SnippetMessage(id, message)) })
  })
}

fn dispatch_nothing(_promise) {
  effect.none()
}

pub fn update(state: State, message) {
  case message {
    AuthMessage(message) -> {
      let #(auth, task) = auth_panel.update(state.auth, message)
      let state = State(..state, auth: auth)
      let assert Ok(storage) = auth_panel.local_storage("session")
      #(state, auth_panel.dispatch(task, AuthMessage, storage))
    }
    SnippetMessage(identifier, message) -> {
      let state = case state.active {
        Editing(current, _) if current != identifier -> {
          let snippet = get_example(state, current)
          let snippet = snippet.finish_editing(snippet)
          set_example(state, current, snippet)
        }
        Running(_current) -> panic as "should not click around when running"
        _ -> state
      }
      let snippet = get_example(state, identifier)
      let #(snippet, eff) = snippet.update(snippet, message)
      let #(failure, snippet_effect) = case eff {
        snippet.Nothing -> #(None, effect.none())
        snippet.Failed(failure) -> #(Some(failure), effect.none())

        snippet.RunEffect(p) -> #(
          None,
          dispatch_to_snippet(identifier, snippet.await_running_effect(p)),
        )
        snippet.FocusOnCode -> #(
          None,
          dispatch_nothing(snippet.focus_on_buffer()),
        )
        snippet.FocusOnInput -> #(
          None,
          dispatch_nothing(snippet.focus_on_input()),
        )
        snippet.ToggleHelp -> #(None, effect.none())
        snippet.MoveAbove -> #(None, effect.none())
        snippet.MoveBelow -> #(None, effect.none())
        snippet.ReadFromClipboard -> #(
          None,
          dispatch_to_snippet(identifier, snippet.read_from_clipboard()),
        )
        snippet.WriteToClipboard(text) -> #(
          None,
          dispatch_to_snippet(identifier, snippet.write_to_clipboard(text)),
        )
        snippet.Conclude(_, _, _) -> #(None, effect.none())
      }
      let state = set_example(state, identifier, snippet)
      let state = State(..state, active: Editing(identifier, failure))
      // let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      #(state, effect.batch([snippet_effect]))
    }
    RunMessage(identifier, message) -> {
      todo
    }
    SyncMessage(message) -> {
      let State(cache: sync_client, ..) = state
      let #(sync_client, effect) = client.update(sync_client, message)
      let snippets =
        dict.map_values(state.snippets, fn(_, v) {
          snippet.set_references(v, sync_client.cache)
        })
      // TODO I think effects of running tasks should happen here.
      // Would be one nice reason to not have them per snippet
      let state = State(..state, cache: sync_client, snippets: snippets)
      #(state, client.do(effect, SyncMessage))
    }
  }
}
