import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import gleam/dict.{type Dict}
import gleam/list
import gleam/option.{None, Some}
import harness/fetch
import harness/impl/browser/abort
import harness/impl/browser/alert
import harness/impl/browser/copy
import harness/impl/browser/download
import harness/impl/browser/paste
import harness/impl/browser/prompt
import lustre/effect
import morph/editable as e

pub type State {
  State(
    cache: sync.Sync,
    active: Active,
    snippets: Dict(String, snippet.Snippet),
  )
}

pub type Active {
  Editing(String)
  Running(String)
  Nothing
}

fn effects() {
  [
    #(abort.l, #(abort.lift, abort.reply, abort.blocking)),
    #(alert.l, #(alert.lift, alert.reply, alert.blocking)),
    #(copy.l, #(copy.lift, copy.reply(), copy.blocking)),
    #(download.l, #(download.lift, download.reply(), download.blocking)),
    #(fetch.l, #(fetch.lift(), fetch.lower(), fetch.blocking)),
    #(paste.l, #(paste.lift, paste.reply(), paste.blocking)),
    #(prompt.l, #(prompt.lift, prompt.reply(), prompt.blocking)),
  ]
}

pub const closure_serialization_key = "closure_serialization"

const closure_serialization = e.Block(
  [
    #(
      e.Bind("script"),
      e.Function(
        [e.Bind("closure")],
        e.Block(
          [
            #(
              e.Bind("js"),
              e.Call(e.Builtin("to_javascript"), [e.Variable("closure")]),
            ),
          ],
          e.Call(
            e.Builtin("string_append"),
            [
              e.String("<script>"),
              e.Call(
                e.Builtin("string_append"),
                [e.Variable("js"), e.String("</script>")],
              ),
            ],
          ),
          True,
        ),
      ),
    ),
    #(
      e.Bind("name"),
      e.Case(
        e.Call(e.Perform("Prompt"), [e.String("What is your name?")]),
        [
          #("Ok", e.Function([e.Bind("value")], e.Variable("value"))),
          #("Error", e.Function([e.Bind("_")], e.String("Alice"))),
        ],
        None,
      ),
    ),
    #(
      e.Bind("client"),
      e.Function(
        [e.Bind("_")],
        e.Block(
          [
            #(
              e.Bind("message"),
              e.Call(
                e.Builtin("string_append"),
                [e.String("Hello, "), e.Variable("name")],
              ),
            ),
            // perform can't be last effect
            #(e.Bind("_"), e.Call(e.Perform("Alert"), [e.Variable("message")])),
          ],
          e.Record([], None),
          True,
        ),
      ),
    ), #(e.Bind("page"), e.Call(e.Variable("script"), [e.Variable("client")])),
    #(
      e.Bind("page"),
      e.Call(e.Builtin("string_to_binary"), [e.Variable("page")]),
    ),
  ],
  e.Call(
    e.Perform("Download"),
    [
      e.Record(
        [#("name", e.String("index.html")), #("content", e.Variable("page"))],
        None,
      ),
    ],
  ),
  True,
)

pub const fetch_key = "fetch"

const catfact = e.Block(
  [
    #(e.Bind("http"), e.Reference("he6fd05f0")),
    // #(e.Bind("json"), e.Reference("hbe004c96")),
    #(
      e.Bind("expect"),
      e.Function(
        [e.Bind("result"), e.Bind("reason")],
        e.Case(
          e.Variable("result"),
          [
            #("Ok", e.Function([e.Bind("value")], e.Variable("value"))),
            #(
              "Error",
              e.Function(
                [e.Bind("_")],
                // e.Call(e.Perform("Abort"), [e.Variable("reason")]),
                e.Vacant(""),
              ),
            ),
          ],
          None,
        ),
      ),
    ),
    #(
      e.Bind("request"),
      e.Call(
        e.Select(e.Variable("http"), "get"),
        [
          e.String("catfact.ninja"), e.String("/fact"),
          e.Call(e.Tag("None"), [e.Record([], None)]),
        ],
      ),
    ),
    // #(
    //   e.Bind("decoder"),
    //   e.Call(
    //     e.Select(e.Variable("json"), "object"),
    //     [
    //       e.Call(
    //         e.Select(e.Variable("json"), "field"),
    //         [
    //           e.String("fact"), e.Select(e.Variable("json"), "string"),
    //           e.Select(e.Variable("json"), "done"),
    //         ],
    //       ), e.Function([e.Bind("x")], e.Variable("x")),
    //     ],
    //   ),
    // ),
    #(
      e.Destructure([#("body", "body")]),
      e.Call(
        e.Variable("expect"),
        [
          e.Call(e.Perform("Fetch"), [e.Variable("request")]),
          e.String("Failed to fetch"),
        ],
      ),
    ),
  ],
  e.Call(e.Builtin("binary_to_string"), [e.Variable("body")]),
  True,
)

pub const hash_key = "hash"

pub fn init(_) {
  let cache = sync.init(browser.get_origin())
  let snippets = [
    #(
      closure_serialization_key,
      snippet.init(closure_serialization, effects(), cache),
    ),
    #(fetch_key, snippet.init(catfact, effects(), cache)),
    #(hash_key, snippet.init(e.Reference("he1727f8f"), effects(), cache)),
  ]
  let references =
    list.flat_map(snippets, fn(snippet) {
      let #(_, snippet) = snippet
      snippet.references(snippet)
    })
  let #(cache, tasks) = sync.fetch_missing(cache, references)
  let state = State(cache, Nothing, dict.from_list(snippets))
  #(state, effect.from(browser.do_sync(tasks, SyncMessage)))
}

// Dont abstact as is useful because it uses the specific page State
pub fn get_snippet(state: State, id) {
  let assert Ok(snippet) = dict.get(state.snippets, id)
  snippet
}

pub fn set_snippet(state: State, id, snippet) {
  State(..state, snippets: dict.insert(state.snippets, id, snippet))
}

pub type Message {
  SnippetMessage(String, snippet.Message)
  SyncMessage(sync.Message)
}

pub fn update(state: State, message) {
  case message {
    SnippetMessage(id, message) -> {
      let state = case state.active {
        Editing(current) if current != id -> {
          let snippet = get_snippet(state, current)
          let snippet = snippet.finish_editing(snippet)
          set_snippet(state, current, snippet)
        }
        Running(_current) -> panic as "should not click around when running"
        _ -> state
      }
      let snippet = get_snippet(state, id)
      let #(snippet, eff) = snippet.update(snippet, message)
      let state = set_snippet(state, id, snippet)
      let state = State(..state, active: Editing(id))
      #(state, case eff {
        None -> effect.none()
        Some(f) ->
          effect.from(fn(d) {
            let d = fn(m) { d(SnippetMessage(id, m)) }
            f(d)
          })
      })
    }
    SyncMessage(message) -> {
      let cache = sync.task_finish(state.cache, message)
      let #(cache, tasks) = sync.fetch_all_missing(cache)
      let snippets =
        dict.map_values(state.snippets, fn(_, v) {
          snippet.set_references(v, cache)
        })
      #(
        State(..state, snippets: snippets, cache: cache),
        effect.from(browser.do_sync(tasks, SyncMessage)),
      )
    }
  }
}
