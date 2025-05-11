import eyg/ir/dag_json
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect
import morph/editable as e
import website/components/auth_panel
import website/components/example.{type Example}
import website/components/runner
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
    show_help: Bool,
    auth: auth_panel.State,
    cache: client.Client,
    active: Active,
    examples: Dict(String, Example),
  )
}

pub type Active {
  Editing(String, Option(snippet.Failure))
  Nothing
}

pub fn get_example(state: State, id) {
  let assert Ok(snippet) = dict.get(state.examples, id)
  snippet
}

pub fn set_example(state: State, id, snippet) {
  State(..state, examples: dict.insert(state.examples, id, snippet))
}

fn to_bytes(editable) {
  e.to_annotated(editable, [])
  |> dag_json.to_block
}

// snippet failure goes at top level
pub fn init(_) {
  let #(sync, init_task) = client.default()
  let examples = [
    #(int_key, to_bytes(int_example)),
    #(text_key, to_bytes(text_example)),
    #(lists_key, to_bytes(lists_example)),
    #(records_key, to_bytes(records_example)),
    #(overwrite_key, to_bytes(overwrite_example)),
    #(unions_key, to_bytes(unions_example)),
    #(open_case_key, to_bytes(open_case_example)),
    #(externals_key, to_bytes(externals_example)),
    #(functions_key, to_bytes(functions_example)),
    #(fix_key, to_bytes(fix_example)),
    #(builtins_key, bit_array.from_string(builtins_example)),
    #(references_key, bit_array.from_string(references_example)),
    #(perform_key, bit_array.from_string(perform_example)),
    #(handle_key, bit_array.from_string(handle_example)),
    #(multiple_resume_key, bit_array.from_string(multiple_resume_example)),
    #(capture_key, bit_array.from_string(capture_example)),
  ]
  let #(auth, task) = auth_panel.init(Nil)
  let assert Ok(storage) = auth_panel.local_storage("session")
  // TODO refs 
  // TODO make snippet update edit refs
  let missing_cids = []
  let examples =
    list.map(examples, fn(entry) {
      let #(key, bytes) = entry
      #(key, example.from_block(bytes, sync.cache, harness.effects()))
    })
  let examples = dict.from_list(examples)
  // let missing_cids = missing_refs(examples)
  let #(sync, sync_task) = client.fetch_fragments(sync, missing_cids)
  let state = State(False, auth, sync, Nothing, examples)
  #(
    state,
    effect.batch([
      auth_panel.dispatch(task, AuthMessage, storage),
      client.lustre_run(list.append(init_task, sync_task), SyncMessage),
    ]),
  )
}

pub type Message {
  ExampleMessage(String, example.Message)
  SyncMessage(client.Message)
  AuthMessage(auth_panel.Message)
}

fn dispatch_to_snippet(id, promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) {
      d(ExampleMessage(id, example.SnippetMessage(message)))
    })
  })
}

fn dispatch_to_runner(id, promise) {
  effect.from(fn(d) {
    promisex.aside(promise, fn(message) {
      d(ExampleMessage(id, example.RunnerMessage(message)))
    })
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
    ExampleMessage(identifier, message) -> {
      let state = case state.active {
        Editing(current, _) if current != identifier -> {
          let example = get_example(state, current)
          let example = example.finish_editing(example)
          set_example(state, current, example)
        }
        _ -> state
      }
      let example = get_example(state, identifier)
      let #(example, action) = example.update(example, message)
      let State(show_help:, ..) = state
      let #(show_help, failure, snippet_effect) = case action {
        example.Nothing -> #(show_help, None, effect.none())
        example.Failed(failure) -> #(show_help, Some(failure), effect.none())
        example.ReturnToCode -> #(
          show_help,
          None,
          dispatch_nothing(snippet.focus_on_buffer()),
        )
        example.FocusOnInput -> #(
          show_help,
          None,
          dispatch_nothing(snippet.focus_on_input()),
        )
        example.ToggleHelp -> #(!show_help, None, effect.none())
        example.ReadFromClipboard -> #(
          show_help,
          None,
          dispatch_to_snippet(identifier, snippet.read_from_clipboard()),
        )
        example.WriteToClipboard(text) -> #(
          show_help,
          None,
          dispatch_to_snippet(identifier, snippet.write_to_clipboard(text)),
        )
        example.RunExternalHandler(reference, thunk) -> #(
          show_help,
          None,
          dispatch_to_runner(identifier, runner.run_thunk(reference, thunk)),
        )
      }
      let state = set_example(state, identifier, example)
      let state =
        State(..state, show_help:, active: Editing(identifier, failure))
      #(state, effect.batch([snippet_effect]))
    }
    SyncMessage(message) -> {
      let State(cache: sync_client, ..) = state
      let #(sync_client, effect) = client.update(sync_client, message)
      let #(effects, entries) =
        dict.fold(state.examples, #([], []), fn(acc, key, example) {
          let #(effects, entries) = acc
          let #(example, action) =
            example.update_cache(example, sync_client.cache)
          let entries = [#(key, example), ..entries]
          let effects = case action {
            runner.Nothing -> effects
            runner.RunExternalHandler(reference, thunk) -> [
              dispatch_to_runner(key, runner.run_thunk(reference, thunk)),
              ..effects
            ]
            runner.Conclude(_return) -> effects
          }
          #(effects, entries)
        })
      let examples = dict.from_list(entries)
      let state = State(..state, cache: sync_client, examples: examples)
      let effects = [client.lustre_run(effect, SyncMessage), ..effects]
      #(state, effect.batch(effects))
    }
  }
}
