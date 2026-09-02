import castor
import eyg/analysis/type_/binding/debug as t_debug
import eyg/hub/cache
import eyg/interpreter/simple_debug
import eyg/interpreter/state as istate
import eyg/interpreter/value as v
import eyg/parser/parser as _
import gleam/http/response.{Response}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/set
import gleam/string
import midas/continuation
import ogre/origin
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/provider/ollama
import overlay/llm/tool
import overlay/web/context
import overlay/web/provider_setup
import overlay/web/tools
import pal/system
import touch_grass/harness/browser as harness
import touch_grass/http
import touch_grass/interface

pub type Config {
  Config(origin: origin.Origin, context: context.Source)
}

// The system prompt and tools are not part of the state as they are built from readme and always one tool
pub type State {
  State(
    llm: provider.Llm,
    provider_setup: provider_setup.State,
    context: context.Status,
    status: AgentStatus,
    history: List(chat.Message(tool.Call)),
    input: String,
    input_error: Option(String),
    origin: origin.Origin,
    cache: cache.Cache(tools.Meta),
    counter: Int,
    expanded: set.Set(Int),
  )
}

pub type AgentStatus {
  Waiting
  Asking(messages: List(chat.Message(tool.Call)))
  Streaming(
    reader: system.Reader,
    completion: chat.Completion(tool.Call),
    remaining: BitArray,
  )
  Executing(calls: tools.Calls)
}

pub fn new(config: Config) -> State {
  let Config(origin:, context:) = config
  let llm =
    provider.Llm(
      provider: provider.Ollama(ollama.Config(origin:, api_key: None)),
      model: "",
    )
  let cache = cache.ready()
  let #(context, cache) = context.load(context, cache)
  State(
    llm:,
    provider_setup: provider_setup.new(),
    context:,
    status: Waiting,
    history: [],
    input: "",
    input_error: None,
    origin: origin,
    cache:,
    counter: 0,
    expanded: set.new(),
  )
}

pub fn init(config) {
  let state = new(config)
  let #(_, provider_effects) = provider_setup.init()
  let #(state, effects) = flush(state)
  let provider_effects =
    list.map(provider_effects, system.map(_, ProviderSetupMessage))
  #(state, list.append(provider_effects, effects))
}

pub type Effect(t) {
  Browser(system.Effect(Message))
  Done(t)
}

fn flush(state: State) {
  let State(cache:, ..) = state
  let #(cache, effects) = cache.flush(cache)
  let effects =
    list.map(effects, fn(effect) {
      {
        use message <- continuation.then(cache.compute(
          effect,
          state.origin,
          system.fetch,
        ))
        continuation.return(CacheMessage(message))
      }(system.Done)
    })
  #(State(..state, cache:), effects)
}

pub type Message {
  ProviderSetupMessage(provider_setup.Message)
  UserUpdatedInput(String)
  UserSubmittedPrompt
  LlmStartedStreaming(reader: system.Reader)
  LlmStreamedCompletion(
    completions: List(chat.Completion(tool.Call)),
    remaining: BitArray,
  )
  LlmStreamFinished(Result(Nil, String))
  UserClickedExpand(Int)
  UserClickedShrink(Int)
  // run messages
  EffectHandled(task_id: Int, value: istate.Value(tools.Meta))
  CacheMessage(cache.ActionCompleted)
  Ignore
}

pub fn update(
  state: State,
  message: Message,
) -> #(State, List(system.Effect(Message))) {
  case message {
    ProviderSetupMessage(message) -> {
      let can_save = case state.status {
        Waiting -> True
        _ -> False
      }
      let #(setup, actions, llm) =
        provider_setup.update(
          state.provider_setup,
          message,
          state.origin,
          can_save,
        )
      let state = State(..state, provider_setup: setup)
      let state = case llm {
        Some(llm) -> State(..state, llm:)
        None -> state
      }
      let actions = list.map(actions, system.map(_, ProviderSetupMessage))
      #(state, actions)
    }
    UserUpdatedInput(input) -> {
      let state = State(..state, input:)
      #(state, [])
    }
    UserSubmittedPrompt ->
      case
        state.provider_setup.configured,
        state.status,
        context.loading(state.context)
      {
        False, _, _ -> {
          let provider_setup =
            provider_setup.require_configuration(state.provider_setup)
          #(State(..state, provider_setup:), [])
        }
        // The readme is part of the system prompt, so a session cannot start
        // before the context it is for has arrived.
        True, Waiting, True -> {
          let state =
            State(..state, input_error: Some("Context is still loading"))
          #(state, [])
        }
        True, Waiting, False -> {
          case string.trim(state.input) {
            "" -> #(State(..state, input_error: Some("")), [])
            input -> {
              let message = chat.UserMessage(text: input, images: [])
              let action = fetch_completion(state, [message])
              let state = State(..state, status: Asking([message]), input: "")
              #(state, [action])
            }
          }
        }
        True, _, _ -> {
          let state =
            State(..state, input_error: Some("Cant send another message"))
          #(state, [])
        }
      }
    LlmStartedStreaming(reader) -> {
      case state.status {
        Asking(messages) -> {
          let history = list.append(messages, state.history)

          let state =
            State(
              ..state,
              status: Streaming(reader, chat.fresh(), <<>>),
              history:,
            )
          let action = stream_next_chunk(state.llm.provider, reader, <<>>)
          #(state, [action])
        }
        _ -> #(state, [])
      }
    }
    LlmStreamedCompletion(new, remaining) -> {
      case state.status {
        Streaming(reader:, completion:, remaining: _) -> {
          let completion = chat.append_chunks(completion, new)
          let state =
            State(..state, status: Streaming(reader:, completion:, remaining:))
          let action = stream_next_chunk(state.llm.provider, reader, remaining)
          #(state, [action])
        }
        _ -> #(state, [])
      }
    }
    LlmStreamFinished(Ok(Nil)) -> {
      case state.status {
        Streaming(reader: _, completion:, remaining: _) -> {
          let message = chat.from_completion(completion)
          let history = [message, ..state.history]

          let state = State(..state, history:)
          case completion.tool_calls {
            [] -> #(State(..state, status: Waiting), [])
            calls -> {
              current_context(state)
              |> tools.execute_all(calls)
              |> run_effects_if_any_remain_to_do(state)
            }
          }
        }
        _ -> #(state, [])
      }
    }
    LlmStreamFinished(Error(reason)) -> {
      let state = State(..state, status: Waiting, input_error: Some(reason))
      #(state, [])
    }
    UserClickedExpand(index) -> {
      let expanded = set.insert(state.expanded, index)
      #(State(..state, expanded:), [])
    }
    UserClickedShrink(index) -> {
      let expanded = set.delete(state.expanded, index)
      #(State(..state, expanded:), [])
    }
    EffectHandled(task_id:, value:) -> {
      case state.status {
        // executing is always a non empty list
        Executing(calls) -> {
          current_context(state)
          |> tools.effect_handled(calls, task_id, value)
          |> run_effects_if_any_remain_to_do(state)
        }
        _ -> #(state, [])
      }
    }
    CacheMessage(message) -> {
      let #(cache, _done) = cache.update(state.cache, message, fn(_) { [] })
      let previous = state.cache.cursor_status
      let was_pulling =
        previous == cache.Pulling || previous == cache.ReadyToPull
      let not_pulling =
        cache.cursor_status != cache.Pulling
        && cache.cursor_status != cache.ReadyToPull
      let stopped_pulling = was_pulling && not_pulling

      let #(context, cache) = case stopped_pulling {
        True -> context.pulled(state.context, cache)
        False -> #(state.context, cache)
      }
      let context = context.check_fetching(context, cache)

      let state = State(..state, cache:, context:)
      case state.status {
        Executing(calls) -> {
          let ctx = current_context(state)

          let #(ctx, calls) = case stopped_pulling {
            True -> list.map_fold(calls, ctx, tools.pulled)
            False -> #(ctx, calls)
          }
          list.map_fold(calls, ctx, tools.check_fetching)
          |> run_effects_if_any_remain_to_do(state)
        }
        _ -> flush(state)
      }
    }

    Ignore -> #(state, [])
  }
}

pub fn can_save_provider(state: State) {
  case state.provider_setup.restoring, state.status {
    False, Waiting -> True
    _, _ -> False
  }
}

// cache state doesn't update during the eval but needs to resume later if everything fetched at the beginning

fn current_context(state: State) {
  let State(cache:, counter:, context:, ..) = state
  tools.Context(cache:, counter:, effects: [], context: context.module(context))
}

/// If a stream message is completed, and effect is handled or a cache message received then resolve calls sees what stage tool calls are in.
/// 
fn run_effects_if_any_remain_to_do(return, state: State) {
  let #(ctx, calls) = return

  let tools.Context(cache:, counter:, effects: inner, context: _) = ctx
  let effects =
    list.map(
      inner,
      system.map(_, fn(return) {
        let #(id, value) = return
        EffectHandled(task_id: id, value:)
      }),
    )

  let state = State(..state, cache:, counter:)
  let #(state, cache_effects) = flush(state)
  let effects = list.append(cache_effects, effects)

  // I think here we do the switch on pulling. 
  let #(status, effects) = case tools.all_returns(calls) {
    Error(Nil) -> #(Executing(calls), effects)
    Ok(messages) -> #(Asking(messages), [
      fetch_completion(state, messages),
      ..effects
    ])
  }

  #(State(..state, status:), effects)
}

fn fetch_completion(state, messages) {
  use response <- system.FetchStreamResponse(completion_request(state, messages))

  case response {
    Ok(Response(200, body:, ..)) -> LlmStartedStreaming(body)
    Ok(Response(status: 401, body: _, ..)) ->
      LlmStreamFinished(Error("Provider rejected the API token (401)."))
    Ok(Response(status:, body: _, ..)) ->
      LlmStreamFinished(Error(
        "Provider returned HTTP " <> int.to_string(status) <> ".",
      ))
    Error(reason) -> LlmStreamFinished(Error(string.inspect(reason)))
  }
  |> system.Done
}

fn stream_next_chunk(provider, reader, remaining) {
  use chunk <- system.ReadChunk(reader)
  case chunk {
    Ok(Some(chunk)) -> {
      let #(completions, remaining) =
        provider.completion_chunk_parse(provider, remaining, chunk)
      LlmStreamedCompletion(completions, remaining)
    }
    Ok(None) -> LlmStreamFinished(Ok(Nil))
    Error(reason) -> LlmStreamFinished(Error(string.inspect(reason)))
  }
  |> system.Done
}

fn completion_request(state: State, messages: List(chat.Message(tool.Call))) {
  let tools = [spec()]
  let context = provider.Context(system_prompt: system_prompt(state), tools:)
  let history = list.append(messages, state.history) |> list.reverse
  provider.stream_completion_request(state.llm, context, history)
}

fn system_prompt(state: State) -> String {
  let origin = state.origin
  let scheme = http.scheme_to_eyg(origin.scheme)
  let host = v.String(origin.host)
  let port = v.option(origin.port, v.Integer)

  "You are an expery automation assistant.
You help users by executing EYG scripts to interact with the users system.
DO NOT guess any function of effects. Only use what you have seen explained and use guide to learn more about writing EYG code.

ALWAYS use djot syntax for your responses.
DO NOT write code blocks in your responses unless explicitly asked.
All code execution uses the 'run' tool.
Every program has the variable context in scope, it is the module described in the Context section at the end of this prompt.

To fetch a guide run the following script.
ALWAYS fetch the EYG syntax guide before writing scripts

```eyg
let request = {
  method: GET({}),
  scheme: " <> simple_debug.inspect(scheme) <> ",
  host: " <> simple_debug.inspect(host) <> ",
  port: " <> simple_debug.inspect(port) <> ",
  path: \"/guides/eyg-syntax-guide.md\",
  query: None({}),
  headers: [],
  body: !string_to_binary(\"\")
}
match perform Fetch(request) {
  Ok({body}) -> {
    match !string_from_binary(body) {
      Ok(text) -> { text }
      Error(_) -> { \"Not a utf-8 response.\" }
    }
  }
  Error(reason) -> { !string_append(\"fetch guide \", reason) }
}
```

Other guides are
- /guides/builtins-reference.md
- /guides/http-fetch.md

This environment has the following effects

"
  |> string.append(
    harness.effects()
    |> list.map(fn(effect) {
      let interface.Interface(name:, lift_type:, lower_type:, decode: _) =
        effect

      "-"
      <> name
      <> "("
      <> t_debug.mono(lift_type)
      <> "_ -> "
      <> t_debug.mono(lower_type)
    })
    |> string.join("\n"),
  ) <> "

Remember to always use perform to call an effect.

Use the service effects, such as DNSimple, to call service API's these do not require the scheme, host or port to be set.
They do not require an API token this will be added by the platform.

# Context

" <> context.readme(state.context)
}

pub fn spec() {
  let name = "run"

  let description =
    "Run an EYG program, the program may have effects at a top level."
  let parameters = [castor.field("code", castor.string())]
  tool.Tool(name, description, parameters)
}
