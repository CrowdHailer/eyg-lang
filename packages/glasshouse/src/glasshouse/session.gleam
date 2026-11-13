//// A session is everything that happened in one sitting, in order.
////
//// An agent session has the model's generations and the tool calls it made.
//// A shell session or a single script has only runs.
//// Generations are observability, runs and their journals are state.

import glasshouse/run.{type Run}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{type Option, None}

pub type Session {
  Session(
    id: String,
    started: Int,
    ended: Int,
    cwd: String,
    agent: Option(Agent),
    events: List(Event),
  )
}

/// The model and the instructions an agent session started with.
pub type Agent {
  Agent(provider: String, model: String, system_prompt: String)
}

pub type Event {
  /// Code was run, a configuration, tool call, script or shell input.
  Execution(run: Run)
  /// A message from the user.
  Prompt(at: Int, text: String)
  /// A completion requested from the model.
  Generated(generation: Generation)
  /// The text returned to the model for a tool call.
  ToolResult(at: Int, call_id: String, text: String)
}

pub type Generation {
  Generation(
    id: String,
    started: Int,
    ended: Int,
    /// SHA-256 of the request body, the key a recorded completion is replayed by.
    key: String,
    /// CID of the request body, headers are never recorded.
    request: String,
    response: Option(String),
    status: Int,
    thinking: String,
    content: String,
    tool_calls: List(ToolCall),
    usage: Usage,
    source: Source,
    error: Option(String),
  )
}

pub type ToolCall {
  ToolCall(id: String, name: String, arguments: String)
}

/// Tokens counted by the provider.
pub type Usage {
  Usage(input: Int, output: Int)
}

/// Was a completion requested from the model or replayed from a recording.
pub type Source {
  Live
  Recorded
}

pub fn no_usage() -> Usage {
  Usage(0, 0)
}

pub fn add_usage(a: Usage, b: Usage) -> Usage {
  Usage(input: a.input + b.input, output: a.output + b.output)
}

/// Every run in the session, in order.
pub fn runs(session: Session) -> List(Run) {
  list.filter_map(session.events, fn(event) {
    case event {
      Execution(run:) -> Ok(run)
      _ -> Error(Nil)
    }
  })
}

pub fn generations(session: Session) -> List(Generation) {
  list.filter_map(session.events, fn(event) {
    case event {
      Generated(generation:) -> Ok(generation)
      _ -> Error(Nil)
    }
  })
}

/// Total tokens, live is what the session spent, recorded is what replays saved.
pub fn usage(session: Session) -> #(Usage, Usage) {
  list.fold(generations(session), #(no_usage(), no_usage()), fn(acc, g) {
    let #(live, recorded) = acc
    case g.source {
      Live -> #(add_usage(live, g.usage), recorded)
      Recorded -> #(live, add_usage(recorded, g.usage))
    }
  })
}

/// Every stored block the session refers to.
pub fn references(session: Session) -> List(String) {
  list.flat_map(session.events, fn(event) {
    case event {
      Execution(run:) -> run.references(run)
      Generated(generation:) -> [
        generation.request,
        ..option.values([generation.response])
      ]
      Prompt(..) | ToolResult(..) -> []
    }
  })
  |> list.unique
}

pub fn encode(session: Session) -> json.Json {
  let Session(id:, started:, ended:, cwd:, agent:, events:) = session
  json.object([
    #("id", json.string(id)),
    #("started", json.int(started)),
    #("ended", json.int(ended)),
    #("cwd", json.string(cwd)),
    #("agent", json.nullable(agent, agent_encode)),
    #("events", json.array(events, event_encode)),
  ])
}

fn agent_encode(agent) {
  let Agent(provider:, model:, system_prompt:) = agent
  json.object([
    #("provider", json.string(provider)),
    #("model", json.string(model)),
    #("system_prompt", json.string(system_prompt)),
  ])
}

fn event_encode(event) {
  case event {
    Execution(run:) ->
      json.object([
        #("type", json.string("execution")),
        #("run", run.encode(run)),
      ])
    Prompt(at:, text:) ->
      json.object([
        #("type", json.string("prompt")),
        #("at", json.int(at)),
        #("text", json.string(text)),
      ])
    Generated(generation:) ->
      json.object([
        #("type", json.string("generation")),
        #("generation", generation_encode(generation)),
      ])
    ToolResult(at:, call_id:, text:) ->
      json.object([
        #("type", json.string("tool_result")),
        #("at", json.int(at)),
        #("call", json.string(call_id)),
        #("text", json.string(text)),
      ])
  }
}

fn generation_encode(generation) {
  let Generation(
    id:,
    started:,
    ended:,
    key:,
    request:,
    response:,
    status:,
    thinking:,
    content:,
    tool_calls:,
    usage:,
    source:,
    error:,
  ) = generation
  json.object([
    #("id", json.string(id)),
    #("started", json.int(started)),
    #("ended", json.int(ended)),
    #("key", json.string(key)),
    #("request", json.string(request)),
    #("response", json.nullable(response, json.string)),
    #("status", json.int(status)),
    #("thinking", json.string(thinking)),
    #("content", json.string(content)),
    #(
      "tool_calls",
      json.array(tool_calls, fn(call) {
        let ToolCall(id:, name:, arguments:) = call
        json.object([
          #("id", json.string(id)),
          #("name", json.string(name)),
          #("arguments", json.string(arguments)),
        ])
      }),
    ),
    #(
      "usage",
      json.object([
        #("input", json.int(usage.input)),
        #("output", json.int(usage.output)),
      ]),
    ),
    #(
      "source",
      json.string(case source {
        Live -> "live"
        Recorded -> "recorded"
      }),
    ),
    #("error", json.nullable(error, json.string)),
  ])
}

pub fn decoder() -> decode.Decoder(Session) {
  use id <- decode.field("id", decode.string)
  use started <- decode.optional_field("started", 0, decode.int)
  use ended <- decode.optional_field("ended", 0, decode.int)
  use cwd <- decode.optional_field("cwd", "", decode.string)
  use agent <- decode.optional_field(
    "agent",
    None,
    decode.optional(agent_decoder()),
  )
  use events <- decode.field("events", decode.list(event_decoder()))
  decode.success(Session(id:, started:, ended:, cwd:, agent:, events:))
}

fn agent_decoder() {
  use provider <- decode.field("provider", decode.string)
  use model <- decode.field("model", decode.string)
  use system_prompt <- decode.field("system_prompt", decode.string)
  decode.success(Agent(provider:, model:, system_prompt:))
}

fn event_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "execution" -> {
      use run <- decode.field("run", run.decoder())
      decode.success(Execution(run:))
    }
    "prompt" -> {
      use at <- decode.field("at", decode.int)
      use text <- decode.field("text", decode.string)
      decode.success(Prompt(at:, text:))
    }
    "generation" -> {
      use generation <- decode.field("generation", generation_decoder())
      decode.success(Generated(generation:))
    }
    "tool_result" -> {
      use at <- decode.field("at", decode.int)
      use call_id <- decode.field("call", decode.string)
      use text <- decode.field("text", decode.string)
      decode.success(ToolResult(at:, call_id:, text:))
    }
    _ -> decode.failure(Prompt(0, ""), "event")
  }
}

fn generation_decoder() {
  use id <- decode.field("id", decode.string)
  use started <- decode.optional_field("started", 0, decode.int)
  use ended <- decode.optional_field("ended", 0, decode.int)
  use key <- decode.field("key", decode.string)
  use request <- decode.field("request", decode.string)
  use response <- decode.optional_field(
    "response",
    None,
    decode.optional(decode.string),
  )
  use status <- decode.optional_field("status", 0, decode.int)
  use thinking <- decode.optional_field("thinking", "", decode.string)
  use content <- decode.optional_field("content", "", decode.string)
  use tool_calls <- decode.optional_field(
    "tool_calls",
    [],
    decode.list({
      use id <- decode.field("id", decode.string)
      use name <- decode.field("name", decode.string)
      use arguments <- decode.field("arguments", decode.string)
      decode.success(ToolCall(id:, name:, arguments:))
    }),
  )
  use usage <- decode.optional_field("usage", no_usage(), {
    use input <- decode.field("input", decode.int)
    use output <- decode.field("output", decode.int)
    decode.success(Usage(input:, output:))
  })
  use source <- decode.optional_field(
    "source",
    Live,
    decode.then(decode.string, fn(source) {
      case source {
        "recorded" -> decode.success(Recorded)
        _ -> decode.success(Live)
      }
    }),
  )
  use error <- decode.optional_field(
    "error",
    None,
    decode.optional(decode.string),
  )
  decode.success(Generation(
    id:,
    started:,
    ended:,
    key:,
    request:,
    response:,
    status:,
    thinking:,
    content:,
    tool_calls:,
    usage:,
    source:,
    error:,
  ))
}
