//// An agent that acts by writing EYG. It has one tool, `run`, and the host
//// decides what running means, usually a `shell.run` against the same shell
//// a person types into. The agent can do nothing a person at the shell could
//// not, and the host's effects are everything it can reach.
////
//// This module is pure. It builds requests to the model and reads responses,
//// the host sends them.

import castor
import eyg/embed/run
import eyg/embed/shell
import gleam/bit_array
import gleam/dynamic/decode
import gleam/http/request.{type Request}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/result
import gleam/string
import oas/generator/utils
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool

pub type Agent {
  Agent(
    llm: provider.Llm,
    system: String,
    history: List(chat.Message(tool.Call)),
    steps: Int,
    limit: Int,
  )
}

pub type Step(s) {
  /// The agent ran code, send the request to continue.
  /// Each run is the code and what the agent was told about it.
  Continue(
    agent: Agent,
    state: s,
    runs: List(#(String, String)),
    request: Request(BitArray),
  )
  /// The agent has answered the user.
  Answered(agent: Agent, state: s, text: String)
  /// The agent was stopped after too many steps.
  Failed(agent: Agent, state: s, reason: String)
}

/// An agent with this system prompt, see `system_prompt`.
pub fn new(llm: provider.Llm, system: String) -> Agent {
  Agent(llm:, system:, history: [], steps: 0, limit: 20)
}

/// The most round trips one message may take.
pub fn with_limit(agent: Agent, limit: Int) -> Agent {
  Agent(..agent, limit: int.max(0, limit))
}

/// A system prompt from what the agent is for, the readme of the library it
/// works with, and the EYG syntax guide.
pub fn system_prompt(purpose: String, readme: String, guide: String) -> String {
  purpose <> "
The run tool is the only way to see or change anything. Do not guess, look.
Prefer one program that does several things over many small runs.
Reply to the user in one or two plain sentences, do not include code in your reply.

# The environment

" <> readme <> "

# EYG

" <> guide
}

/// The one tool.
pub fn tool() -> tool.Tool {
  tool.Tool(
    name: "run",
    description: "Run an EYG program. Variables defined with a final let are kept for later runs.",
    parameters: [castor.field("code", castor.string())],
  )
}

/// Every message, oldest first.
pub fn messages(agent: Agent) -> List(chat.Message(tool.Call)) {
  list.reverse(agent.history)
}

/// Add the user's message and build the request for the model.
pub fn ask(agent: Agent, text: String) -> #(Agent, Request(BitArray)) {
  let history = [chat.UserMessage(text:, images: []), ..agent.history]
  let agent = Agent(..agent, history:, steps: 0)
  #(agent, request(agent))
}

fn request(agent: Agent) {
  let context = provider.Context(system_prompt: agent.system, tools: [tool()])
  provider.stream_completion_request(agent.llm, context, messages(agent))
}

/// Read a whole response to a request and run any code the model asked for.
pub fn respond(
  agent: Agent,
  state: s,
  body: BitArray,
  run: fn(s, String) -> #(s, String),
) -> Step(s) {
  case check(agent, state, read(agent, body)) {
    Ok(step) -> step
    Error(#(agent, calls)) -> {
      let #(state, results) =
        list.map_fold(calls, state, fn(state, call) {
          let #(state, report) = call_tool(state, call, run)
          #(state, #(call, report))
        })
      continue(agent, state, results)
    }
  }
}

/// `respond` for a host whose runs take time.
pub fn respond_async(
  agent: Agent,
  state: s,
  body: BitArray,
  run: fn(s, String) -> Promise(#(s, String)),
) -> Promise(Step(s)) {
  case check(agent, state, read(agent, body)) {
    Ok(step) -> promise.resolve(step)
    Error(#(agent, calls)) -> {
      use #(state, results) <- promise.map(run_all(calls, state, run, []))
      continue(agent, state, results)
    }
  }
}

fn run_all(calls, state, run, acc) {
  case calls {
    [] -> promise.resolve(#(state, list.reverse(acc)))
    [call, ..rest] ->
      case code(call) {
        Ok(code) -> {
          use #(state, report) <- promise.await(run(state, code))
          run_all(rest, state, run, [#(call, report), ..acc])
        }
        Error(report) -> run_all(rest, state, run, [#(call, report), ..acc])
      }
  }
}

// The requests ask for a stream, so a whole body is its events in order.
fn read(agent: Agent, body) {
  use text <- result.try(
    bit_array.to_string(body)
    |> result.replace_error("Model response is not UTF-8."),
  )
  let body = <<string.trim_end(text):utf8, "\n":utf8>>
  let #(chunks, _) =
    provider.completion_chunk_parse(agent.llm.provider, <<>>, body)
  let completion = chat.append_chunks(chat.fresh(), chunks)
  use completion <- result.try(provider.finish_stream(
    agent.llm.provider,
    body,
    completion,
  ))
  use Nil <- result.try(
    case completion.content == "" && completion.tool_calls == [] {
      True -> Error("Model returned no text or tool calls.")
      False -> Ok(Nil)
    },
  )
  let message = chat.from_completion(completion)
  Ok(#(
    Agent(..agent, history: [message, ..agent.history]),
    completion.tool_calls,
  ))
}

fn check(
  agent: Agent,
  state,
  response: Result(#(Agent, List(tool.Call)), String),
) {
  case response {
    Error(reason) -> Ok(Failed(agent, state, reason))
    Ok(#(agent, calls)) ->
      case calls {
        [] ->
          case agent.history {
            [message, ..] -> Ok(Answered(agent, state, chat.text(message)))
            [] -> Ok(Answered(agent, state, ""))
          }
        _ if agent.steps >= agent.limit ->
          Ok(Failed(
            agent,
            state,
            "Stopped after " <> int.to_string(agent.limit) <> " steps.",
          ))
        _ -> Error(#(agent, calls))
      }
  }
}

fn continue(agent: Agent, state, results: List(#(tool.Call, String))) {
  let replies =
    list.map(results, fn(result) {
      let #(tool.Call(id:, ..), report) = result
      chat.ToolResultMessage(tool_call_id: id, text: report, images: [])
    })
  let runs =
    list.map(results, fn(result) {
      let #(call, report) = result
      #(code(call) |> unwrap, report)
    })
  let history = list.append(list.reverse(replies), agent.history)
  let agent = Agent(..agent, history:, steps: agent.steps + 1)
  Continue(agent, state, runs, request(agent))
}

fn call_tool(state, call, run) {
  case code(call) {
    Ok(code) -> run(state, code)
    Error(report) -> #(state, report)
  }
}

fn code(call: tool.Call) -> Result(String, String) {
  let tool.Call(function: tool.FunctionCall(name:, arguments:), ..) = call
  case name {
    "run" ->
      decode.run(
        utils.fields_to_dynamic(arguments),
        decode.field("code", decode.string, decode.success),
      )
      |> result_or("The run tool needs a code argument.")
    _ -> Error("Unknown tool " <> name <> ", the only tool is run.")
  }
}

fn result_or(result, message) {
  case result {
    Ok(value) -> Ok(value)
    Error(_) -> Error(message)
  }
}

fn unwrap(result) {
  case result {
    Ok(code) -> code
    Error(_) -> ""
  }
}

/// Run the agent's code in a shell, the state being the shell and the host's own.
/// Pass `run_in_shell(handle)` as `run` to `respond`.
pub fn run_in_shell(
  handle: run.Handler(s, shell.Span),
) -> fn(#(shell.Shell, s), String) -> #(#(shell.Shell, s), String) {
  fn(state: #(shell.Shell, s), code) {
    let #(shell, host) = state
    let shell.Run(shell:, state: host, outcome:) =
      shell.run(shell, code, host, handle)
    #(#(shell, host), shell.report([], outcome))
  }
}
