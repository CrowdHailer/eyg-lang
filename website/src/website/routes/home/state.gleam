import eyg/interpreter/state as istate
import eyg/interpreter/value
import eyg/ir/dag_json
import gleam/dict.{type Dict}
import gleam/javascript/promise
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre/effect
import morph/editable as e
import website/components/auth_panel
import website/components/example
import website/components/reload
import website/components/runner
import website/components/snippet
import website/harness/browser as harness
import website/sync/client

pub type Meta =
  List(Int)

pub type Value =
  value.Value(Meta, #(List(#(istate.Kontinue(Meta), Meta)), istate.Env(Meta)))

pub type Example {
  Simple(example.Example)
  // reload is parameterised by meta, Simple is not
  Reload(reload.Reload(List(Int)))
}

pub type State {
  State(
    auth: auth_panel.State,
    sync: client.Client,
    active: Active,
    examples: Dict(String, Example),
  )
}

pub type Active {
  Editing(String, Option(snippet.Failure))
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

fn init_example(json, cache, extrinsic) {
  example.from_block(<<json:utf8>>, cache, extrinsic)
  |> Simple
}

fn effects(_config) {
  list.append(
    harness.effects(),
    // todo as "spotless.effects(config)"
    [],
  )
}

pub fn init(config) {
  let #(config, storage) = config
  let effects = effects(config)
  let #(client, init_task) = client.default()
  let examples =
    [
      #(
        closure_serialization_key,
        init_example(closure_serialization, client.cache, effects),
      ),
      #(fetch_key, init_example(fetch_example, client.cache, effects)),
      #(twitter_key, init_example(twitter_example, client.cache, effects)),
      #(type_check_key, init_example(type_check_example, client.cache, effects)),
      #(
        predictable_effects_key,
        init_example(predictable_effects_example, client.cache, effects),
      ),
      #(hot_reload_key, {
        let assert Ok(source) = dag_json.from_block(<<hot_reload_example:utf8>>)
        reload.init(
          source |> e.from_annotated |> e.to_annotated([]),
          client.cache,
        )
        |> Reload
      }),
    ]
    |> dict.from_list
  let #(auth, task) = auth_panel.init(Nil)
  let missing_cids = missing_refs(examples)
  let #(client, sync_task) = client.fetch_fragments(client, missing_cids)
  let state = State(auth, client, Nothing, examples)

  #(
    state,
    effect.batch([
      auth_panel.dispatch(task, AuthMessage, storage),
      client.lustre_run(list.append(init_task, sync_task), SyncMessage),
    ]),
  )
}

fn missing_refs(examples) {
  dict.fold(examples, [], fn(acc, _key, example) {
    case example {
      Simple(example.Example(snippet:, ..))
      | Reload(reload.Reload(snippet:, ..)) ->
        snippet.references(snippet)
        |> list.append(acc)
        |> list.unique
    }
  })
}

// Dont abstact as is useful because it uses the specific page State
pub fn get_example(state: State, id) {
  let assert Ok(snippet) = dict.get(state.examples, id)
  snippet
}

pub fn set_example(state: State, id, snippet) {
  State(..state, examples: dict.insert(state.examples, id, snippet))
}

pub type Message {
  AuthMessage(auth_panel.Message)
  SimpleMessage(String, example.Message)
  ReloadMessage(String, reload.Message(List(Int)))
  SyncMessage(client.Message)
}

fn dispatch_to_snippet(id, promise) {
  effect.from(fn(d) {
    promise.map(promise, fn(message) {
      d(SimpleMessage(id, example.SnippetMessage(message)))
    })
    Nil
  })
}

fn dispatch_to_runner(id, promise) {
  effect.from(fn(d) {
    promise.map(promise, fn(message) {
      d(SimpleMessage(id, example.RunnerMessage(message)))
    })
    Nil
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
    SimpleMessage(id, message) -> {
      let state = close_other_examples(state, id)
      let example = get_example(state, id)
      case example {
        Simple(example) -> {
          let #(example, action) = example.update(example, message)
          let state = set_example(state, id, Simple(example))
          let #(failure, action) = case action {
            example.Nothing -> #(None, effect.none())
            example.Failed(failure) -> #(Some(failure), effect.none())
            example.ReturnToCode -> #(
              None,
              dispatch_nothing(snippet.focus_on_buffer()),
            )
            example.FocusOnInput -> #(
              None,
              dispatch_nothing(snippet.focus_on_input()),
            )
            example.ToggleHelp -> #(None, effect.none())
            example.ReadFromClipboard -> #(
              None,
              dispatch_to_snippet(id, snippet.read_from_clipboard()),
            )
            example.WriteToClipboard(text) -> #(
              None,
              dispatch_to_snippet(id, snippet.write_to_clipboard(text)),
            )
            example.RunExternalHandler(ref, thunk) -> #(
              None,
              dispatch_to_runner(id, runner.run_thunk(ref, thunk)),
            )
          }
          let state = State(..state, active: Editing(id, failure))
          #(state, action)
        }
        _ ->
          panic as "SimpleMessage should not be sent to other kinds of example"
      }
    }
    ReloadMessage(id, message) -> {
      let state = close_other_examples(state, id)
      let example = get_example(state, id)
      case example {
        Reload(example) -> {
          let #(example, action) = reload.update(example, message)
          let state = set_example(state, id, Reload(example))
          let #(failure, action) = case action {
            reload.Nothing -> #(None, effect.none())
            reload.Failed(failure) -> #(Some(failure), effect.none())
            reload.ReturnToCode -> #(
              None,
              dispatch_nothing(snippet.focus_on_buffer()),
            )
            reload.FocusOnInput -> #(
              None,
              dispatch_nothing(snippet.focus_on_input()),
            )
            reload.ReadFromClipboard -> #(
              None,
              dispatch_to_snippet(id, snippet.read_from_clipboard()),
            )
            reload.WriteToClipboard(text) -> #(
              None,
              dispatch_to_snippet(id, snippet.write_to_clipboard(text)),
            )
          }
          let state = State(..state, active: Editing(id, failure))
          #(state, action)
        }
        _ ->
          panic as "SimpleMessage should not be sent to other kinds of example"
      }
    }
    SyncMessage(message) -> {
      let State(sync: sync_client, ..) = state
      let #(sync_client, effect) = client.update(sync_client, message)
      let #(entries, effects) =
        dict.fold(state.examples, #([], []), fn(acc, key, example) {
          let #(entries, effects) = acc
          case example {
            Simple(example) -> {
              let #(example, action) =
                example.update_cache(example, sync_client.cache)
              let entries = [#(key, Simple(example)), ..entries]
              let effects = case action {
                runner.Nothing -> effects
                runner.RunExternalHandler(ref, thunk) -> {
                  let effect =
                    dispatch_to_runner(key, runner.run_thunk(ref, thunk))
                  [effect, ..effects]
                }
                runner.Conclude(_return) -> effects
              }
              #(entries, effects)
            }
            Reload(example) -> {
              let entries = [#(key, Reload(example)), ..entries]
              #(entries, effects)
            }
          }
        })
      let examples = dict.from_list(entries)
      let state = State(..state, sync: sync_client, examples:)
      #(
        state,
        effect.batch([client.lustre_run(effect, SyncMessage), ..effects]),
      )
    }
  }
}

fn close_other_examples(state, id) {
  let State(active:, ..) = state
  case active {
    Editing(current, _) if current != id -> {
      let example = get_example(state, current)
      let example = case example {
        Simple(example) -> example.finish_editing(example) |> Simple
        Reload(example) -> reload.finish_editing(example) |> Reload
      }
      set_example(state, current, example)
    }
    _ -> state
  }
}
