import castor
import eyg/analysis/type_/binding/debug as t_debug
import eyg/hub/cache
import eyg/interpreter/state as istate
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
import overlay/web/tools
import pal/system
import touch_grass/harness/browser as harness
import touch_grass/interface

pub type Config {
  Config(provider: provider.Provider, origin: origin.Origin)
}

// The system prompt and tools are not part of the state as they are built from readme and always one tool
pub type State {
  State(
    llm: provider.Llm,
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
  Executing(calls: List(#(String, tools.Call)))
}

pub fn new(config: Config) -> State {
  let Config(provider:, origin:) = config
  let llm = provider.Llm(provider:, model: default_model(provider))
  let cache = cache.ready()
  State(
    llm:,
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

fn default_model(provider) {
  case provider {
    provider.Ollama(ollama.Config(api_key: None, ..)) -> "qwen3.5:35b"
    provider.Ollama(ollama.Config(api_key: Some(_), ..)) -> "qwen3.5:397b-cloud"
    provider.Mistral(_) -> "ministral-3b-2512"
  }
}

pub fn init(config) {
  new(config)
  |> flush()
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
  SelectLlm(provider.Llm)
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
    SelectLlm(llm) -> {
      let state = State(..state, llm:)
      #(state, [])
    }
    UserUpdatedInput(input) -> {
      let state = State(..state, input:)
      #(state, [])
    }
    UserSubmittedPrompt ->
      case state.status {
        Waiting -> {
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
        _ -> {
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
              |> resolve_calls(state)
            }
          }
        }
        _ -> #(state, [])
      }
    }
    LlmStreamFinished(Error(reason)) -> {
      let state = State(..state, input_error: Some(reason))
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
          |> resolve_calls(state)
        }
        _ -> #(state, [])
      }
    }
    CacheMessage(message) -> {
      let #(cache, _done) = cache.update(state.cache, message, fn(_) { [] })
      let state = State(..state, cache: cache)

      case state.status {
        Executing(calls) -> {
          let ctx = current_context(state)
          // multiple id's might be needed
          list.map_fold(calls, ctx, tools.restart)
          |> resolve_calls(state)
        }
        _ -> flush(state)
      }
    }

    Ignore -> #(state, [])
  }
}

// cache state doesn't update during the eval but needs to resume later if everything fetched at the beginning

fn current_context(state) {
  let State(cache:, counter:, ..) = state
  tools.Context(cache:, counter:, effects: [])
}

fn resolve_calls(return, state: State) {
  let #(ctx, calls) = return

  let tools.Context(cache:, counter:, effects: inner) = ctx
  let effects =
    list.map(
      inner,
      system.map(_, fn(return) {
        let #(id, value) = return
        EffectHandled(task_id: id, value:)
      }),
    )

  let #(status, effects) = case tools.all_returns(calls) {
    Error(Nil) -> #(Executing(calls), effects)
    Ok(messages) -> #(Asking(messages), [
      fetch_completion(state, messages),
      ..effects
    ])
  }

  let state = State(..state, status:, cache:, counter:)
  #(state, effects)
}

fn fetch_completion(state, messages) {
  use response <- system.FetchStreamResponse(completion_request(state, messages))

  case response {
    Ok(Response(200, body:, ..)) -> LlmStartedStreaming(body)
    Ok(Response(status:, body: _, ..)) -> {
      LlmStreamFinished(Error("bad response" <> int.to_string(status)))
    }
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
  let context = provider.Context(system_prompt: system_prompt(), tools:)
  let history = list.append(messages, state.history) |> list.reverse
  provider.stream_completion_request(state.llm, context, history)
}

fn system_prompt() {
  "You are an expery automation assistant.
You help users by executing EYG scripts to interact with the users system.
DO NOT guess any function of effects. Only use what you have seen explained and use guide to learn more about writing EYG code.

ALWAYS use djot syntax for your responses

To fetch a guide run the following script.
ALWAYS fetch the EYG syntax guide before writing scripts

```eyg
let request = {
  method: GET({}),
  scheme: HTTP({}),
  host: \"localhost\",
  port: Some(5173),
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
  )
  <> "

Remember to always use perform to call an effect.

Use the service effects, such as DNSimple, to call service API's these do not require the scheme, host or port to be set.
They do not require an API token this will be added by the platform."
}

pub fn spec() {
  let name = "run"

  let description =
    "Run an EYG program, the program may have effects at a top level."
  let parameters = [castor.field("code", castor.string())]
  tool.Tool(name, description, parameters)
}
