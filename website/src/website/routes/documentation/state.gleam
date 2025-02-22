import eyg/ir/dag_json
import eyg/sync/browser
import eyg/sync/sync
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option, None, Some}
import harness/impl/browser as harness
import lustre/effect
import morph/editable as e
import website/components/auth_panel
import website/components/snippet

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

const references_example = "{\"0\":\"l\",\"l\":\"std\",\"v\":{\"0\":\"@\",\"l\":{\"/\":\"baguqeeralt3s7yi53wf6hhlbtppwo4ebzgshdd7nr2onw7jlr3e2zkl4bxda\"},\"p\":\"std\",\"r\":1},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"contains\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"list\"},\"a\":{\"0\":\"v\",\"l\":\"std\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"i\",\"v\":1}},\"a\":{\"0\":\"ta\"}}},\"a\":{\"0\":\"i\",\"v\":0}}}"

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

pub const multiple_resume_example = "{\"0\":\"l\",\"l\":\"std\",\"v\":{\"0\":\"@\",\"l\":{\"/\":\"baguqeeralt3s7yi53wf6hhlbtppwo4ebzgshdd7nr2onw7jlr3e2zkl4bxda\"},\"p\":\"std\",\"r\":1},\"t\":{\"0\":\"l\",\"l\":\"capture\",\"v\":{\"0\":\"f\",\"l\":\"exec\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"h\",\"l\":\"Flip\"},\"a\":{\"0\":\"f\",\"l\":\"value\",\"b\":{\"0\":\"f\",\"l\":\"resume\",\"b\":{\"0\":\"l\",\"l\":\"truthy\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"resume\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"True\"},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"l\",\"l\":\"falsy\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"resume\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"False\"},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"flatten\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"list\"},\"a\":{\"0\":\"v\",\"l\":\"std\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"v\",\"l\":\"truthy\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"v\",\"l\":\"falsy\"}},\"a\":{\"0\":\"ta\"}}}}}}}}},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"exec\"},\"a\":{\"0\":\"u\"}}},\"a\":{\"0\":\"ta\"}}}}},\"t\":{\"0\":\"l\",\"l\":\"run\",\"v\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"first\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Flip\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"l\",\"l\":\"second\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Flip\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"second\"},\"a\":{\"0\":\"v\",\"l\":\"second\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"first\"},\"a\":{\"0\":\"v\",\"l\":\"first\"}},\"a\":{\"0\":\"u\"}}}}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"capture\"},\"a\":{\"0\":\"v\",\"l\":\"run\"}}}}}"

pub const capture_key = "capture"

const capture_example = "{\"0\":\"l\",\"l\":\"greeting\",\"v\":{\"0\":\"s\",\"v\":\"hey\"},\"t\":{\"0\":\"l\",\"l\":\"ignored\",\"v\":{\"0\":\"s\",\"v\":\"this string doesn't get transpiled\"},\"t\":{\"0\":\"l\",\"l\":\"func\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"to_javascript\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"v\",\"l\":\"greeting\"}},\"a\":{\"0\":\"s\",\"v\":\"Alice\"}}}},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"v\",\"l\":\"func\"}}}}"

pub type State {
  State(
    auth: auth_panel.State,
    cache: sync.Sync,
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
  let cache = sync.init(browser.get_origin())
  let snippets = [
    #(int_key, snippet.init(int_example, [], harness.effects(), cache)),
    #(text_key, snippet.init(text_example, [], harness.effects(), cache)),
    #(lists_key, snippet.init(lists_example, [], harness.effects(), cache)),
    #(records_key, snippet.init(records_example, [], harness.effects(), cache)),
    #(
      overwrite_key,
      snippet.init(overwrite_example, [], harness.effects(), cache),
    ),
    #(unions_key, snippet.init(unions_example, [], harness.effects(), cache)),
    #(
      open_case_key,
      snippet.init(open_case_example, [], harness.effects(), cache),
    ),
    #(
      externals_key,
      snippet.init(externals_example, [], harness.effects(), cache),
    ),
    #(
      functions_key,
      snippet.init(functions_example, [], harness.effects(), cache),
    ),
    #(fix_key, snippet.init(fix_example, [], harness.effects(), cache)),
    #(builtins_key, init_example(builtins_example, cache)),
    #(references_key, init_example(references_example, cache)),
    #(perform_key, init_example(perform_example, cache)),
    #(handle_key, init_example(handle_example, cache)),
    #(multiple_resume_key, init_example(multiple_resume_example, cache)),
    #(capture_key, init_example(capture_example, cache)),
  ]
  let #(auth, task) = auth_panel.init(Nil)
  let state = State(auth, cache, Nothing, dict.from_list(snippets))
  let assert Ok(storage) = auth_panel.local_storage("session")
  #(
    state,
    effect.batch([
      auth_panel.dispatch(task, AuthMessage, storage),
      effect.from(browser.do_load(SyncMessage)),
    ]),
  )
}

fn fetch_missing(state) {
  let State(snippets: snippets, ..) = state
  let refs =
    dict.fold(snippets, [], fn(acc, _key, snippet) {
      snippet.references(snippet)
      |> list.append(acc)
      |> list.unique
    })
  let #(cache, tasks) = sync.fetch_missing(state.cache, refs)
  let state = State(..state, cache: cache)
  #(state, tasks)
}

pub type Message {
  SnippetMessage(String, snippet.Message)
  SyncMessage(sync.Message)
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

        snippet.AwaitRunningEffect(p) -> #(
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
      let #(state, tasks) = fetch_missing(state)
      let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      #(state, effect.batch([snippet_effect, sync_effect]))
    }
    SyncMessage(message) -> {
      let State(cache: cache, ..) = state
      let cache = sync.task_finish(cache, message)
      let snippets =
        dict.map_values(state.snippets, fn(_, v) {
          snippet.set_references(v, cache)
        })
      let state = State(..state, cache: cache, snippets: snippets)
      let #(state, tasks) = fetch_missing(state)
      let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      #(state, sync_effect)
    }
  }
}
