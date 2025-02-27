import eyg/interpreter/state as istate
import eyg/interpreter/value
import eyg/ir/dag_json
import gleam/dict.{type Dict}
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect
import morph/editable as e
import website/components/auth_panel
import website/components/reload
import website/components/snippet
import website/harness/browser as harness
import website/harness/spotless
import website/sync/client

pub type Meta =
  List(Int)

pub type Value =
  value.Value(Meta, #(List(#(istate.Kontinue(Meta), Meta)), istate.Env(Meta)))

pub type State {
  State(
    auth: auth_panel.State,
    sync: client.Client,
    active: Active,
    snippets: Dict(String, snippet.Snippet),
    reload: reload.State(List(Int)),
  )
}

pub type Active {
  Editing(String, Option(snippet.Failure))
  Running(String)
  Nothing
}

pub const closure_serialization_key = "closure_serialization"

const closure_serialization = "{\"0\":\"l\",\"l\":\"script\",\"v\":{\"0\":\"f\",\"l\":\"closure\",\"b\":{\"0\":\"l\",\"l\":\"js\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"to_javascript\"},\"a\":{\"0\":\"v\",\"l\":\"closure\"}},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"s\",\"v\":\"<script>\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"v\",\"l\":\"js\"}},\"a\":{\"0\":\"s\",\"v\":\"</script>\"}}}}},\"t\":{\"0\":\"l\",\"l\":\"name\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"value\",\"b\":{\"0\":\"v\",\"l\":\"value\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"s\",\"v\":\"Alice\"}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Prompt\"},\"a\":{\"0\":\"s\",\"v\":\"What is your name?\"}}},\"t\":{\"0\":\"l\",\"l\":\"client\",\"v\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"message\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"s\",\"v\":\"Hello, \"}},\"a\":{\"0\":\"v\",\"l\":\"name\"}},\"t\":{\"0\":\"l\",\"l\":\"_\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Alert\"},\"a\":{\"0\":\"v\",\"l\":\"message\"}},\"t\":{\"0\":\"u\"}}}},\"t\":{\"0\":\"l\",\"l\":\"page\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"script\"},\"a\":{\"0\":\"v\",\"l\":\"client\"}},\"t\":{\"0\":\"l\",\"l\":\"page\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_to_binary\"},\"a\":{\"0\":\"v\",\"l\":\"page\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Download\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"name\"},\"a\":{\"0\":\"s\",\"v\":\"index.html\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"content\"},\"a\":{\"0\":\"v\",\"l\":\"page\"}},\"a\":{\"0\":\"u\"}}}}}}}}}"

pub const fetch_key = "fetch"

const fetch_example = "{\"0\":\"l\",\"l\":\"$\",\"v\":{\"0\":\"@\",\"l\":{\"/\":\"baguqeeragtrji4oxi2ro6bpuo6bqiogjrwhvnmung3d7z5uf4hriebz5ujua\"},\"p\":\"standard\",\"r\":1},\"t\":{\"0\":\"l\",\"l\":\"http\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"http\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"l\",\"l\":\"request\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"get\"},\"a\":{\"0\":\"v\",\"l\":\"http\"}},\"a\":{\"0\":\"s\",\"v\":\"catfact.ninja\"}},\"a\":{\"0\":\"s\",\"v\":\"/fact\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"$\",\"b\":{\"0\":\"l\",\"l\":\"body\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"body\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_from_binary\"},\"a\":{\"0\":\"v\",\"l\":\"body\"}}}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"Error\"},\"a\":{\"0\":\"u\"}}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Fetch\"},\"a\":{\"0\":\"v\",\"l\":\"request\"}}}}}}"

pub const predictable_effects_key = "predictable_effects"

pub const predictable_effects_example = "{\"0\":\"l\",\"l\":\"exec\",\"v\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"_\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Alert\"},\"a\":{\"0\":\"s\",\"v\":\"hello world!\"}},\"t\":{\"0\":\"s\",\"v\":\"done\"}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"h\",\"l\":\"Alert\"},\"a\":{\"0\":\"f\",\"l\":\"value\",\"b\":{\"0\":\"f\",\"l\":\"resume\",\"b\":{\"0\":\"l\",\"l\":\"$\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"resume\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"l\",\"l\":\"alerts\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"alerts\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"l\",\"l\":\"return\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"return\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"alerts\"},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"c\"},\"a\":{\"0\":\"v\",\"l\":\"value\"}},\"a\":{\"0\":\"v\",\"l\":\"alerts\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"return\"},\"a\":{\"0\":\"v\",\"l\":\"return\"}},\"a\":{\"0\":\"u\"}}}}}}}}},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"l\",\"l\":\"return\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"v\",\"l\":\"exec\"},\"a\":{\"0\":\"u\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"alerts\"},\"a\":{\"0\":\"ta\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"return\"},\"a\":{\"0\":\"v\",\"l\":\"return\"}},\"a\":{\"0\":\"u\"}}}}}}}"

pub const type_check_key = "type_check"

pub const type_check_example = "{\"0\":\"l\",\"l\":\"user\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"age\"},\"a\":{\"0\":\"i\",\"v\":71}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"name\"},\"a\":{\"0\":\"s\",\"v\":\"Eve\"}},\"a\":{\"0\":\"u\"}}},\"t\":{\"0\":\"l\",\"l\":\"total\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"int_add\"},\"a\":{\"0\":\"i\",\"v\":10}},\"a\":{\"0\":\"s\",\"v\":\"hello\"}},\"t\":{\"0\":\"l\",\"l\":\"address\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"address\"},\"a\":{\"0\":\"v\",\"l\":\"user\"}},\"t\":{\"0\":\"v\",\"l\":\"sum\"}}}}"

pub const twitter_key = "twitter"

pub const twitter_example = "{\"0\":\"l\",\"l\":\"message\",\"v\":{\"0\":\"s\",\"v\":\"I've just finished the EYG introduction\"},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"s\",\"v\":\"Tweeted successfully\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"s\",\"v\":\"Failed to send tweet.\"}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Twitter.Tweet\"},\"a\":{\"0\":\"v\",\"l\":\"message\"}}}}"

pub const hot_reload_key = "hot_reload"

pub const hot_reload_example = "{\"0\":\"l\",\"l\":\"initial\",\"v\":{\"0\":\"i\",\"v\":10},\"t\":{\"0\":\"l\",\"l\":\"handle\",\"v\":{\"0\":\"f\",\"l\":\"state\",\"b\":{\"0\":\"f\",\"l\":\"message\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"int_add\"},\"a\":{\"0\":\"v\",\"l\":\"state\"}},\"a\":{\"0\":\"i\",\"v\":1}}}},\"t\":{\"0\":\"l\",\"l\":\"render\",\"v\":{\"0\":\"f\",\"l\":\"count\",\"b\":{\"0\":\"l\",\"l\":\"count\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"int_to_string\"},\"a\":{\"0\":\"v\",\"l\":\"count\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_append\"},\"a\":{\"0\":\"s\",\"v\":\"the total is \"}},\"a\":{\"0\":\"v\",\"l\":\"count\"}}}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"render\"},\"a\":{\"0\":\"v\",\"l\":\"render\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"handle\"},\"a\":{\"0\":\"v\",\"l\":\"handle\"}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"e\",\"l\":\"init\"},\"a\":{\"0\":\"v\",\"l\":\"initial\"}},\"a\":{\"0\":\"u\"}}}}}}}"

fn decode_source(json) {
  let assert Ok(source) = dag_json.from_block(<<json:utf8>>)
  e.from_annotated(source)
  |> e.open_all
}

fn init_example(json, cache, config) {
  let source = decode_source(json)
  snippet.init(source, [], effects(config), cache)
}

fn effects(config) {
  list.append(harness.effects(), spotless.effects(config))
}

fn init_reload_example(json, cache) {
  let source = decode_source(json)
  snippet.init(source, [], [], cache)
}

pub fn init(config) {
  let #(config, _origin, storage) = config
  let #(client, init_task) = client.default()
  let reload_snippet = init_reload_example(hot_reload_example, client.cache)
  let snippets =
    [
      #(
        closure_serialization_key,
        init_example(closure_serialization, client.cache, config),
      ),
      #(fetch_key, init_example(fetch_example, client.cache, config)),
      #(twitter_key, init_example(twitter_example, client.cache, config)),
      #(type_check_key, init_example(type_check_example, client.cache, config)),
      #(
        predictable_effects_key,
        init_example(predictable_effects_example, client.cache, config),
      ),
      #(hot_reload_key, reload_snippet),
    ]
    |> dict.from_list
  let reload =
    reload.init(client.cache, reload_snippet.editable |> e.to_annotated([]))
  let #(auth, task) = auth_panel.init(Nil)
  let missing_cids = missing_refs(snippets)
  let #(client, sync_task) = client.fetch_fragments(client, missing_cids)
  let state = State(auth, client, Nothing, snippets, reload)

  #(
    state,
    effect.batch([
      auth_panel.dispatch(task, AuthMessage, storage),
      client.lustre_run(list.append(init_task, sync_task), SyncMessage),
    ]),
  )
}

fn missing_refs(snippets) {
  dict.fold(snippets, [], fn(acc, _key, snippet) {
    snippet.references(snippet)
    |> list.append(acc)
    |> list.unique
  })
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
  AuthMessage(auth_panel.Message)
  SnippetMessage(String, snippet.Message)
  SyncMessage(client.Message)
  ReloadMessage(reload.Message(List(Int)))
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
      let #(auth, cmd) = auth_panel.update(state.auth, message)
      let state = State(..state, auth: auth)
      let assert Ok(storage) = auth_panel.local_storage("session")

      #(state, auth_panel.dispatch(cmd, AuthMessage, storage))
    }
    SnippetMessage(id, message) -> {
      let state = case state.active {
        Editing(current, _) if current != id -> {
          let snippet = get_snippet(state, current)
          let snippet = snippet.finish_editing(snippet)
          set_snippet(state, current, snippet)
        }
        Running(_current) -> panic as "should not click around when running"
        _ -> state
      }
      let snippet = get_snippet(state, id)
      let #(snippet, eff) = snippet.update(snippet, message)
      let #(failure, snippet_effect) = case eff {
        snippet.Nothing -> #(None, effect.none())
        snippet.Failed(failure) -> #(Some(failure), effect.none())
        snippet.RunEffect(p) -> #(
          None,
          dispatch_to_snippet(id, snippet.await_running_effect(p)),
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
          dispatch_to_snippet(id, snippet.read_from_clipboard()),
        )
        snippet.WriteToClipboard(text) -> #(
          None,
          dispatch_to_snippet(id, snippet.write_to_clipboard(text)),
        )
        snippet.Conclude(_, _, _) -> #(None, effect.none())
      }
      let state = set_snippet(state, id, snippet)
      let references = snippet.references(snippet)
      let #(client, task) = client.fetch_fragments(state.sync, references)

      let reload = case id == hot_reload_key {
        True -> {
          let source = snippet.editable |> e.to_annotated([])
          reload.update_source(state.reload, source)
        }
        False -> state.reload
      }
      let state = State(..state, reload:, active: Editing(id, failure))
      #(
        state,
        effect.batch([
          snippet_effect,
          effect.from(fn(d) {
            list.map(client.run(task), fn(p) {
              promise.map(p, fn(r) { d(SyncMessage(r)) })
            })
            Nil
          }),
        ]),
      )
    }
    SyncMessage(message) -> {
      let State(sync: sync_client, ..) = state
      let #(sync_client, effect) = client.update(sync_client, message)
      let snippets =
        dict.map_values(state.snippets, fn(_, v) {
          snippet.set_references(v, sync_client.cache)
        })
      let reload = reload.update_cache(state.reload, sync_client.cache)
      let state = State(..state, reload:, sync: sync_client, snippets:)
      #(state, client.lustre_run(effect, SyncMessage))
    }
    ReloadMessage(message) -> {
      let reload = reload.update(state.reload, message)
      let state = State(..state, reload:)
      #(state, effect.none())
    }
  }
}
