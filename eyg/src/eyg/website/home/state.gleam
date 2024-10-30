import eyg/sync/browser
import eyg/sync/sync
import eyg/website/components/snippet
import eygir/decode
import gleam/dict.{type Dict}
import gleam/javascript/promisex
import gleam/list
import gleam/option.{None}
import harness/impl/browser as harness
import harness/impl/spotless
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

pub const closure_serialization_key = "closure_serialization"

const closure_serialization = "{\"0\":\"l\",\"l\":\"script\",\"v\":{\"0\":\"f\",\"l\":\"closure\",\"b\":{\"0\":\"l\",\"l\":\"js\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"to_javascript\"},\"a\":{\"0\":\"v\",\"l\":\"closure\"}},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"s\",\"v\":\"<script>\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"v\",\"l\":\"js\"}},\"a\":{\"0\":\"s\",\"v\":\"</script>\"}}}}},\"t\":{\"0\":\"l\",\"l\":\"name\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"value\",\"b\":{\"0\":\"v\",\"l\":\"value\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"s\",\"v\":\"Alice\"}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Prompt\"},\"a\":{\"0\":\"s\",\"v\":\"What is your name?\"}}},\"t\":{\"0\":\"l\",\"l\":\"client\",\"v\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"message\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"s\",\"v\":\"Hello, \"}},\"a\":{\"0\":\"v\",\"l\":\"name\"}},\"t\":{\"0\":\"l\",\"l\":\"_\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Alert\"},\"a\":{\"0\":\"v\",\"l\":\"message\"}},\"t\":{\"0\":\"u\"}}}},\"t\":{\"0\":\"l\",\"l\":\"page\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"script\"},\"a\":{\"0\":\"v\",\"l\":\"client\"}},\"t\":{\"0\":\"l\",\"l\":\"page\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_to_binary\"},\"a\":{\"0\":\"v\",\"l\":\"page\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Download\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"name\"},\"a\":{\"0\":\"s\",\"v\":\"index.html\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"content\"},\"a\":{\"0\":\"v\",\"l\":\"page\"}},\"a\":{\"0\":\"u\"}}}}}}}}}"

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

pub const predictable_effects_key = "predictable_effects"

pub const predictable_effects_example = "{\"0\":\"l\",\"l\":\"exec\",\"v\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"_\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Alert\"},\"a\":{\"0\":\"s\",\"v\":\"hello world!\"}},\"t\":{\"0\":\"s\",\"v\":\"done\"}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"h\",\"l\":\"Alert\"},\"a\":{\"0\":\"f\",\"l\":\"value\",\"b\":{\"0\":\"f\",\"l\":\"resume\",\"b\":{\"0\":\"l\",\"l\":\"$\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"resume\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"l\",\"l\":\"alerts\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"alerts\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"l\",\"l\":\"return\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"return\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"alerts\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"v\",\"l\":\"value\"}},\"a\":{\"0\":\"v\",\"l\":\"alerts\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"return\"},\"a\":{\"0\":\"v\",\"l\":\"return\"}},\"a\":{\"0\":\"u\"}}}}}}}}},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"return\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"exec\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"alerts\"},\"a\":{\"0\":\"ta\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"return\"},\"a\":{\"0\":\"v\",\"l\":\"return\"}},\"a\":{\"0\":\"u\"}}}}}}}"

pub const type_check_key = "type_check"

pub const type_check_example = "{\"0\":\"l\",\"l\":\"user\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"age\"},\"a\":{\"0\":\"i\",\"v\":71}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"name\"},\"a\":{\"0\":\"s\",\"v\":\"Eve\"}},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"l\",\"l\":\"total\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"int_add\"},\"a\":{\"0\":\"i\",\"v\":10}},\"a\":{\"0\":\"s\",\"v\":\"hello\"}},\"t\":{\"0\":\"l\",\"l\":\"$\",\"v\":{\"0\":\"v\",\"l\":\"user\"},\"t\":{\"0\":\"l\",\"l\":\"address\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"address\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"v\",\"l\":\"sum\"}}}}}"

pub const twitter_key = "twitter"

pub const twitter_example = "{\"0\":\"l\",\"l\":\"message\",\"v\":{\"0\":\"s\",\"v\":\"I've just finished the EYG introduction\"},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"s\",\"v\":\"Tweeted successfully\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"s\",\"v\":\"Failed to send tweet.\"}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Twitter.Tweet\"},\"a\":{\"0\":\"v\",\"l\":\"message\"}}}}"

fn init_example(json, cache, config) {
  let assert Ok(source) = decode.from_json(json)
  let source =
    e.from_expression(source)
    |> e.open_all
  snippet.init(source, [], effects(config), cache)
}

fn effects(config) {
  list.append(harness.effects(), spotless.effects(config))
}

fn all_references(snippets) {
  list.flat_map(snippets, fn(snippet) {
    let #(_, snippet) = snippet
    snippet.references(snippet)
  })
}

pub fn init(config) {
  let cache = sync.init(browser.get_origin())
  let snippets = [
    #(
      closure_serialization_key,
      init_example(closure_serialization, cache, config),
    ),
    #(fetch_key, snippet.init(catfact, [], effects(config), cache)),
    #(twitter_key, init_example(twitter_example, cache, config)),
    #(type_check_key, init_example(type_check_example, cache, config)),
    #(
      predictable_effects_key,
      init_example(predictable_effects_example, cache, config),
    ),
  ]
  let references = all_references(snippets)
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
      let snippet_effect = case eff {
        snippet.Nothing -> effect.none()
        snippet.AwaitRunningEffect(p) ->
          dispatch_to_snippet(id, snippet.await_running_effect(p))
        snippet.FocusOnCode -> dispatch_nothing(snippet.focus_on_buffer())
        snippet.FocusOnInput -> dispatch_nothing(snippet.focus_on_input())
        snippet.ToggleHelp -> effect.none()
        snippet.MoveAbove -> effect.none()
        snippet.MoveBelow -> effect.none()
        snippet.ReadFromClipboard ->
          dispatch_to_snippet(id, snippet.read_from_clipboard())
        snippet.WriteToClipboard(text) ->
          dispatch_to_snippet(id, snippet.write_to_clipboard(text))
        snippet.Conclude(_, _) -> effect.none()
      }
      let state = set_snippet(state, id, snippet)
      let references = all_references(state.snippets |> dict.to_list)
      let #(cache, tasks) = sync.fetch_missing(state.cache, references)

      let state = State(..state, active: Editing(id), cache: cache)
      let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      #(state, effect.batch([snippet_effect, sync_effect]))
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
