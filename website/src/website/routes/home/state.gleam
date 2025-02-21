import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/expression as runner
import eyg/interpreter/state as istate
import eyg/interpreter/value
import eyg/ir/dag_json
import gleam/dict.{type Dict}
import gleam/dynamic
import gleam/dynamicx
import gleam/io
import gleam/javascript/promisex
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/effect
import morph/analysis
import morph/editable as e
import website/components/auth_panel
import website/components/reload
import website/components/snippet
import website/harness/browser as harness
import website/harness/spotless
import website/sync/browser
import website/sync/cache
import website/sync/sync

pub type Meta =
  List(Int)

pub type Value =
  value.Value(Meta, #(List(#(istate.Kontinue(Meta), Meta)), istate.Env(Meta)))

pub type Example {
  Example(
    value: Value,
    // Need to be all generalised
    state_type: binding.Poly,
  )
}

pub type State {
  State(
    auth: auth_panel.State,
    cache: cache.Cache,
    active: Active,
    snippets: Dict(String, snippet.Snippet),
    example: Example,
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

const fetch_example = "{\"0\":\"l\",\"l\":\"$\",\"v\":{\"0\":\"@\",\"l\":{\"/\":\"baguqeeralt3s7yi53wf6hhlbtppwo4ebzgshdd7nr2onw7jlr3e2zkl4bxda\"},\"p\":\"std\",\"r\":1},\"t\":{\"0\":\"l\",\"l\":\"http\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"http\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"l\",\"l\":\"request\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"get\"},\"a\":{\"0\":\"v\",\"l\":\"http\"}},\"a\":{\"0\":\"s\",\"v\":\"catfact.ninja\"}},\"a\":{\"0\":\"s\",\"v\":\"/fact\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Ok\"},\"a\":{\"0\":\"f\",\"l\":\"$\",\"b\":{\"0\":\"l\",\"l\":\"body\",\"v\":{\"0\":\"a\",\"f\":{\"0\":\"g\",\"l\":\"body\"},\"a\":{\"0\":\"v\",\"l\":\"$\"}},\"t\":{\"0\":\"a\",\"f\":{\"0\":\"b\",\"l\":\"string_from_binary\"},\"a\":{\"0\":\"v\",\"l\":\"body\"}}}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"a\",\"f\":{\"0\":\"m\",\"l\":\"Error\"},\"a\":{\"0\":\"f\",\"l\":\"_\",\"b\":{\"0\":\"a\",\"f\":{\"0\":\"t\",\"l\":\"Error\"},\"a\":{\"0\":\"u\"}}}},\"a\":{\"0\":\"n\"}}},\"a\":{\"0\":\"a\",\"f\":{\"0\":\"p\",\"l\":\"Fetch\"},\"a\":{\"0\":\"v\",\"l\":\"request\"}}}}}}"

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
  let assert Ok(source) = dag_json.from_block(<<json:utf8>>)
  let source =
    e.from_annotated(source)
    |> e.open_all
  snippet.init(source, [], effects(config), cache)
}

fn effects(config) {
  list.append(harness.effects(), spotless.effects(config))
}

fn init_reload_example(json, cache) {
  let source = decode_source(json)
  snippet.init(source, [], [], cache)
}

fn all_references(snippets) {
  list.flat_map(snippets, fn(snippet) {
    let #(_, snippet) = snippet
    snippet.references(snippet)
  })
}

pub fn init(config) {
  let #(config, origin, storage) = config
  let cache = cache.init()
  let snippets = [
    #(
      closure_serialization_key,
      init_example(closure_serialization, cache, config),
    ),
    #(fetch_key, init_example(fetch_example, cache, config)),
    #(twitter_key, init_example(twitter_example, cache, config)),
    #(type_check_key, init_example(type_check_example, cache, config)),
    #(
      predictable_effects_key,
      init_example(predictable_effects_example, cache, config),
    ),
    #(hot_reload_key, init_reload_example(hot_reload_example, cache)),
  ]
  let example = Example(value.Integer(0), t.Integer)
  let #(auth, task) = auth_panel.init(Nil)
  let state = State(auth, cache, Nothing, dict.from_list(snippets), example)

  #(
    state,
    effect.batch([
      auth_panel.dispatch(task, AuthMessage, storage),
      // effect.from(browser.do_load(SyncMessage)),
    ]),
  )
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
  SyncMessage(sync.Message)
  ClickExample
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
      let references = all_references(state.snippets |> dict.to_list)
      // let #(cache, tasks) = sync.fetch_missing(state.cache, references)

      let state = State(..state, active: Editing(id, failure))
      // let sync_effect = effect.from(browser.do_sync(tasks, SyncMessage))
      io.debug("the cache fetching")
      #(state, effect.batch([snippet_effect]))
    }
    SyncMessage(message) -> {
      todo as "no sync messages"
      // let cache = sync.task_finish(state.cache, message)
      // let #(cache, tasks) = sync.fetch_all_missing(cache)
      // let snippets =
      //   dict.map_values(state.snippets, fn(_, v) {
      //     snippet.set_references(v, cache)
      //   })
      // #(
      //   State(..state, snippets: snippets, cache: cache),
      //   effect.from(browser.do_sync(tasks, SyncMessage)),
      // )
    }
    ClickExample -> {
      let Example(value, type_) = state.example
      let s = get_snippet(state, hot_reload_key)
      let source = snippet.source(s)

      // TODO real refs
      let check = reload.check_against_state(source, type_, dict.new())

      case check {
        Ok(#(_, False)) -> {
          let assert Ok(source) =
            runner.execute_next(source |> e.to_annotated([]), [])
          let source = #(source, [])

          // TODO remove by fixing everything to be paths
          let value = dynamicx.unsafe_coerce(dynamic.from(value))

          let select = value.Partial(value.Select("handle"), [])
          let args = [source, #(value, []), #(value.unit(), [])]
          let assert Ok(new_value) = runner.call_next(select, args)
          let example = Example(new_value, type_)
          let state = State(..state, example: example)
          #(state, effect.none())
        }
        Ok(#(_, True)) -> {
          let assert Ok(source) =
            runner.execute_next(source |> e.to_annotated([]), [])
          let source = #(source, [])

          // TODO remove by fixing everything to be paths
          let value = dynamicx.unsafe_coerce(dynamic.from(value))

          let select = value.Partial(value.Select("migrate"), [])
          let args = [source, #(value, [])]
          let assert Ok(new_value) = runner.call_next(select, args)
          let #(new_type, _b) =
            analysis.value_to_type(new_value, dict.new(), [])
          let example = Example(new_value, new_type)
          let state = State(..state, example: example)
          #(state, effect.none())
        }
        Error(_) -> #(state, effect.none())
      }
    }
  }
}

// run code in reload example to render page
pub fn render(state: State) {
  let Example(value, type_) = state.example
  let s = get_snippet(state, hot_reload_key)
  let source = snippet.source(s)

  todo as "need the types"
  // let check = reload.check_against_state(source, type_, sync.types(state.cache))

  // case check {
  //   Ok(#(_, False)) -> {
  //     // TODO pass in a better env
  //     let env = istate.Env([], dict.new(), dict.new())
  //     let h = dict.new()

  //     let assert Ok(source) =
  //       runner.execute(source |> e.to_annotated([]), env, h)
  //     let source = #(source, [])

  //     let select = value.Partial(value.Select("render"), [])
  //     let args = [source, #(value, [])]
  //     let page = case runner.call(select, args, env, h) {
  //       Ok(value.String(page)) -> page
  //       // TODO print actual value
  //       other -> "something went wrong: " <> string.inspect(other)
  //     }
  //     Ok(#(page, False))
  //   }
  //   Ok(#(_, True)) -> Ok(#("", True))
  //   Error(reason) -> Error(reason)
  // }
}
