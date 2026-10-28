//// This module is the effectful implementation of the tool calls available to overlay.
//// The state passed to each tool call is a cache of state that is reusable between tool calls.
//// Currently this state is only used for keeping access tokens for authenticated calls to API's
//// The state is currently a bun specific implementation however as it is scoped to tool calls it could be moved to overlay
//// Moving the full application state to overlay core is a bad idea, because we want to track different state when streaming
//// vs using The Elm Architecture in a Lustre web app.
////
//// The code execution tool is defined sans io using an effect type defined in this project.
//// The other tools could use the same effect logic, this is probably a good idea once we start applying policies for which files can be read.
////
//// Every session is recorded, see the glasshouse package.
//// The configuration, each generation and every tool call's effects are saved as an archive,
//// after every turn, to the trace directory.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/error as type_error
import eyg/analysis/type_/isomorphic as t
import eyg/cli/check
import eyg/cli/internal/config
import eyg/cli/internal/terminal
import eyg/cli/internal/traces
import eyg/cli/upload
import eyg/hub/cache
import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/cast
import eyg/interpreter/expression
import eyg/interpreter/state
import eyg/interpreter/value
import glasshouse/archive
import glasshouse/cohort
import glasshouse/journal
import glasshouse/langfuse
import glasshouse/lock
import glasshouse/recorder.{type Recorder}
import glasshouse/run
import glasshouse/secret.{type Secret}
import glasshouse/session as trace
import glasshouse/store.{type Store}
import glasshouse/usage
import glasshouse/value as recorded
import gleam/bit_array
import gleam/dict
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/pair
import gleam/result
import gleam/string
import gleam/uri
import gleam_community/ansi
import loam/execute
import loam/pin
import loam/platform/computer
import loam/record
import loam/source
import loam/system
import midas/effect
import oas/generator/utils
import overlay/agent
import overlay/config as overlay_config
import overlay/export
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool
import overlay/policy
import overlay/tools/run as run_tool
import touch_grass/harness/computer as harness_computer
import touch_grass/http
import touch_grass/interface

// I don't need to implement streaming but if so that goes at the loam level
// the tools module in overlay web should be reusable
// policy is read as part of config, which can read files and effects. policy is pure

// Env should be readable on startup
/// Everything about a session that is fixed when it starts.
pub type Session(eff) {
  Session(
    llm: provider.Llm,
    provider_context: provider.Context,
    cwd: String,
    policy: policy.Policy(eff, source.Location),
    context: cache.Module(source.Location),
    styled: Bool,
    /// The recorded configuration run.
    config: run.Run,
    /// The configuration's program, imports and recorded effects.
    store: Store,
    /// Secrets the configuration mounted, never recorded.
    secrets: List(Secret),
    /// Standalone sessions save each turn; sandbox runners persist externally.
    persist: Bool,
  )
}

/// Everything recorded so far in a session.
pub type Trace {
  Trace(
    id: String,
    started: Int,
    agent: trace.Agent,
    recorder: Recorder,
    /// Newest first.
    events: List(trace.Event),
    generations: Int,
    /// Supervisor checkpoint; observes immutable progress, never affects EYG.
    observe: fn(Trace) -> Nil,
  )
}

// Move with_variable and with_scope to analysis
// check should be on run/script/shell etc and test the right things
// --no-check can be an option
// pass in a policy should be possible in other commands such as REPL etc
// Safety in the language i.e. sandbox
// policy can have a debug effect during running it so we can see what's happening.
// type check some new code and then eval returns Effect(value, resume)
// This is the API choices such as use of types around eval can setup what's passed in.
pub fn execute(
  input: source.Input,
  config: config.Config,
) -> system.Effect(Result(Int, String)) {
  let state = execute.State(config.client.origin, cache.empty())
  use #(result, state) <- system.then(setup(
    input,
    config,
    computer.effects(),
    rule_mapping,
    state,
  ))
  use session <- system.try(result)
  use id <- system.then(traces.new_id(session.config.started))
  let trace = start_trace(id, session)
  use trace <- system.then(outer_loop(session, state, [], trace))
  use Nil <- system.then(finish(session, trace))
  Ok(0) |> system.Done
}

/// Policy fields of effects added after policies were first published.
/// A policy without one of them is still valid, the agent can not use that effect.
pub const optional_fields = []

/// Type check a configuration against the policy the rules describe,
/// optional fields the policy does not have are removed from the rules.
fn check_config(source, cwd, harness, rules, state) {
  // The harness bound with the rules
  let agent_harness = policy.match_rules(harness, rules)
  let context =
    infer.pure()
    // The policy is evaluated outside the policy and can access any effect
    |> infer.with_effects(interface.types(harness))
  let #(expected, context_type, bindings) =
    overlay_config.type_(agent_harness, context.level, context.bindings)
  let context =
    infer.Context(..context, bindings:)
    |> infer.with_expected_type(expected)
  // TODO this analysis should return updated state
  use #(_type, _, errors, analysis) <- system.then(check.check_from(
    source,
    cwd,
    context,
    state,
    check.allway_pass_gate,
  ))
  let missing =
    list.filter_map(errors, fn(error) {
      case error.1 {
        type_error.MissingRow(field) ->
          case list.contains(optional_fields, field) {
            True -> Ok(field)
            False -> Error(Nil)
          }
        _ -> Error(Nil)
      }
    })
  let reduced =
    list.filter(rules, fn(rule) {
      case rule.1 {
        policy.PolicyField(field) -> !list.contains(missing, field)
        policy.Unchecked -> True
      }
    })
  case list.length(reduced) < list.length(rules) {
    True -> check_config(source, cwd, harness, reduced, state)
    False -> system.Done(#(agent_harness, context_type, errors, analysis))
  }
}

fn try(result, state, then) {
  case result {
    Ok(value) -> then(value)
    Error(reason) -> system.Done(#(Error(reason), state))
  }
}

/// Setup the chat session.
/// The `Session` contains all information that is constant over the conversation
///
/// The `config` arg could be broken down as not that many parts are needed
/// The harness and rule_mappings are passed in to make building other CLI tools easier
pub fn setup(
  input: source.Input,
  config: config.Config,
  harness: interface.Harness(harness_computer.Effect, source.Location),
  rule_mapping: List(#(String, policy.Rule)),
  state: execute.State,
) -> system.Effect(
  #(Result(Session(harness_computer.Effect), String), execute.State),
) {
  use cwd <- system.then(system.cwd())
  use cwd <- try(cwd, state)
  use input <- try(source.normalize_input(cwd, input), state)
  use code <- system.then(source.read_input(input))
  use code <- try(code, state)
  use source <- try(source.parse_input(code, input), state)

  use #(agent_harness, context_type, errors, analysis) <- system.then(
    check_config(source, cwd, harness, rule_mapping, state),
  )
  use Nil <- try(
    case errors {
      [] -> Ok(Nil)
      _ -> Error(list.map(errors, check.render_error) |> string.join("\n"))
    },
    state,
  )

  let context_poly = {
    let mono = binding.resolve(context_type, analysis.bindings)
    binding.gen(mono, 0, analysis.bindings)
  }
  // The configuration is pinned and recorded like any other run.
  use started <- system.then(system.now())
  let recorder = recorder.new(traces.sha256)
  use #(pinned, state, recorder) <- system.then(pin.pin(
    source,
    cwd,
    state,
    recorder,
    pin.allow,
  ))
  use pinned <- try(pinned, state)
  use #(outcome, recorder, Nil) <- system.then(record.run_block(
    source,
    [],
    pinned,
    cwd,
    recorder,
    record.computer,
    Nil,
  ))
  use ended <- system.then(system.now())
  case outcome {
    record.Completed(#(Some(user_config), _)) ->
      case overlay_config.cast(user_config, agent_harness) {
        Ok(user_config) -> {
          // The rest of the configuration holds credentials, only the context is recorded.
          let #(context_value, recorder) =
            recorder.encode(recorder, user_config.context)
          let config_run =
            run.Run(
              id: "config",
              kind: run.Config,
              code:,
              origin: run_origin(input),
              program: Some(pinned.program),
              lock: recorder.lock_secrets(recorder, pinned.lock),
              cwd:,
              journal: recorder.journal(recorder),
              outcome: run.Returned(context_value),
              started:,
              ended:,
            )
          let session =
            Session(
              llm: user_config.llm,
              provider_context: provider.Context(
                system_prompt: agent.system_prompt(
                  config.client.origin,
                  // use the agent harness because the prompt should talk about effects that can't be used
                  list.map(agent_harness, pair.first),
                  user_config.readme,
                  True,
                ),
                tools: agent.tools(),
              ),
              cwd:,
              policy: user_config.policy,
              context: cache.Module(
                value: user_config.context,
                type_: context_poly,
              ),
              styled: config.styled,
              config: config_run,
              store: recorder.store(recorder),
              secrets: recorder.secrets(recorder),
              persist: True,
            )

          system.Done(#(Ok(session), state))
        }
        Error(reason) ->
          #(
            Error(execute.render_error(reason, source.1, state.Empty, cwd)),
            state,
          )
          |> system.Done
      }
    record.Completed(#(None, _)) ->
      #(
        Error(execute.render_error(break.Vacant, source.1, state.Empty, cwd)),
        state,
      )
      |> system.Done
    record.Raised(#(reason, location, _, k)) ->
      #(Error(execute.render_error(reason, location, k, cwd)), state)
      |> system.Done
    record.Exited(status:) ->
      #(
        Error("the configuration exited with status " <> int.to_string(status)),
        state,
      )
      |> system.Done
  }
}

fn run_origin(input: source.Input) -> run.Origin {
  case input {
    source.File(path:) -> run.File(path)
    source.Code(..) -> run.Inline
    source.Stdin -> run.Stdin
  }
}

/// A trace starting with the configuration run.
pub fn start_trace(id: String, session: Session(_)) -> Trace {
  let provider = case session.llm.provider {
    provider.Ollama(_) -> "ollama"
    provider.Mistral(_) -> "mistral"
  }
  let agent =
    trace.Agent(
      provider:,
      model: session.llm.model,
      system_prompt: session.provider_context.system_prompt,
    )
  let recorder =
    recorder.new(traces.sha256)
    |> recorder.with_store(session.store)
    |> recorder.with_secrets(session.secrets)
  Trace(
    id:,
    started: session.config.started,
    agent:,
    recorder:,
    events: [trace.Execution(session.config)],
    generations: 0,
    observe: fn(_) { Nil },
  )
}

fn add(trace: Trace, event: trace.Event) -> Trace {
  let trace = Trace(..trace, events: [event, ..trace.events])
  trace.observe(trace)
  trace
}

/// The archive for a trace so far.
pub fn to_archive(
  session: Session(_),
  trace: Trace,
  ended: Int,
) -> archive.Archive {
  let Trace(id:, started:, agent:, recorder:, events:, ..) = trace
  let session =
    trace.Session(
      id:,
      started:,
      ended:,
      cwd: session.cwd,
      agent: Some(agent),
      events: list.reverse(events),
    )
  archive.new(session, recorder.store(recorder))
}

fn save(
  session: Session(_),
  trace: Trace,
) -> system.Effect(Result(String, String)) {
  use ended <- system.then(system.now())
  traces.save(to_archive(session, trace, ended), session.cwd)
}

/// Save the trace and upload it to Langfuse when configured.
fn finish(session: Session(_), trace: Trace) -> system.Effect(Nil) {
  use ended <- system.then(system.now())
  let archive = to_archive(session, trace, ended)
  use credentials <- system.then(upload.configured())
  use #(archive, message) <- system.then(case credentials {
    Some(credentials) -> {
      use uploaded <- system.map(upload.upload(archive, credentials))
      case uploaded {
        Ok(archive) -> #(archive, case archive.links {
          [archive.Langfuse(host:, trace_id:), ..] ->
            "\nuploaded to " <> langfuse.trace_url(host, trace_id)
          _ -> ""
        })
        Error(reason) -> #(archive, "\nupload failed: " <> reason)
      }
    }
    None -> system.Done(#(archive, ""))
  })
  use saved <- system.then(traces.save(archive, session.cwd))
  let text = case saved {
    Ok(path) -> "trace saved to " <> path <> message
    Error(reason) -> reason <> message
  }
  system.stdout(terminal.style(session.styled, ansi.dim, text))
}

/// A chat based outer loop, this is the layer that a ralph loop would replace
pub fn outer_loop(
  session: Session(harness_computer.Effect),
  eyg_state: execute.State,
  history: List(chat.Message(tool.Call)),
  trace: Trace,
) -> system.Effect(Trace) {
  use read <- system.then(input(session.styled, ">>>", "send a message"))
  case read {
    Ok("") -> system.Done(trace)
    Ok("/export" <> path) -> {
      use Nil <- system.then(export(session, history, string.trim(path)))
      outer_loop(session, eyg_state, history, trace)
    }
    Ok(text) -> {
      use at <- system.then(system.now())
      let trace = add(trace, trace.Prompt(at:, text:))
      use #(result, eyg_state, trace) <- system.then(inner_loop(
        session,
        eyg_state,
        [chat.UserMessage(text, []), ..history],
        trace,
      ))
      // A failed completion is reported and the session continues from the
      // history before the failed message, so the user can try again.
      use history <- system.then(case result {
        Ok(history) -> system.Done(history)
        Error(reason) -> {
          // This output should be error and potentially show to the agent.
          use Nil <- system.then(system.stdout(
            terminal.style(session.styled, ansi.red, reason) <> "\n",
          ))
          system.Done(history)
        }
      })
      // Saving every turn keeps the trace if the process is stopped.
      use _ <- system.then(case session.persist {
        True -> save(session, trace)
        False -> system.Done(Ok(""))
      })
      outer_loop(session, eyg_state, history, trace)
    }
    Error(Nil) -> system.Done(trace)
  }
}

fn input(
  noninteractive: Bool,
  prompt: String,
  placeholder: String,
) -> system.Effect(Result(String, Nil)) {
  let prompt = case noninteractive {
    // The placeholder is overwritten as the user types.
    True -> {
      let prompt = ansi.bold(ansi.yellow(prompt))
      prompt <> " " <> ansi.dim(placeholder) <> "\r" <> prompt <> " "
    }
    False -> prompt <> " "
  }
  use return <- system.map(system.prompt(prompt))
  case return {
    Ok(line) -> Ok(string.trim_end(line))
    Error(reason) -> Error(reason)
  }
}

/// Complete and run tool calls until the agent replies without calling a tool.
/// This is a sequential inner loop
pub fn inner_loop(
  session: Session(harness_computer.Effect),
  eyg_state: execute.State,
  history: List(chat.Message(tool.Call)),
  trace: Trace,
) -> system.Effect(
  #(Result(List(chat.Message(tool.Call)), String), execute.State, Trace),
) {
  use #(completion, trace) <- system.then(generate(session, history, trace))
  case completion {
    Ok(#(completion, generation)) -> {
      use Nil <- system.then(system.stdout(completion.content))
      let history = [chat.from_completion(completion), ..history]
      case completion.tool_calls {
        [] -> system.Done(#(Ok(history), eyg_state, trace))
        calls -> {
          use #(history, eyg_state, trace, _) <- system.then(
            system.fold(calls, #(history, eyg_state, trace, 0), fn(acc, call) {
              let #(history, eyg_state, trace, index) = acc
              let tool.Call(id:, function:) = call
              let call_id = call_id(generation, index)
              use #(result, eyg_state, trace) <- system.then(execute_call(
                session,
                function,
                eyg_state,
                trace,
                call_id,
              ))
              let message = result_to_message(id, result)
              use at <- system.then(system.now())
              let trace =
                add(
                  trace,
                  trace.ToolResult(at:, call_id:, text: chat.text(message)),
                )
              system.Done(#([message, ..history], eyg_state, trace, index + 1))
            }),
          )
          inner_loop(session, eyg_state, history, trace)
        }
      }
    }
    Error(reason) -> system.Done(#(Error(reason), eyg_state, trace))
  }
}

/// The id of a tool call in the trace, providers do not always give ids.
pub fn call_id(generation: String, index: Int) -> String {
  generation <> "/" <> int.to_string(index)
}

/// Request a completion, recording the exact request and response bodies.
fn generate(
  session: Session(harness_computer.Effect),
  history: List(chat.Message(tool.Call)),
  trace: Trace,
) -> system.Effect(
  #(Result(#(chat.Completion(tool.Call), String), String), Trace),
) {
  let request =
    provider.completion_request(
      session.llm,
      session.provider_context,
      list.reverse(history),
    )
  let id = "g" <> int.to_string(trace.generations + 1)
  use started <- system.then(system.now())
  use #(response, source) <- system.then(complete(session, request))
  use ended <- system.then(system.now())
  let #(generation, result, recorder) =
    record_generation(
      session.llm,
      trace.recorder,
      id,
      request,
      response,
      started,
      ended,
      source,
    )
  let trace =
    Trace(..trace, recorder:, generations: trace.generations + 1)
    |> add(trace.Generated(generation))
  system.Done(#(result.map(result, fn(c) { #(c, id) }), trace))
}

/// Ask the model for a completion,
/// a variant reuses the recorded response to an identical request.
fn complete(
  _session: Session(_),
  request: Request(BitArray),
) -> system.Effect(
  #(Result(Response(BitArray), effect.FetchError), trace.Source),
) {
  use response <- system.map(system.fetch(request))
  #(response, trace.Live)
}

/// Record a completion request and its response.
/// Headers are never recorded, bodies are stored with secrets redacted.
pub fn record_generation(
  llm: provider.Llm,
  recorder: Recorder,
  id: String,
  request: Request(BitArray),
  response: Result(Response(BitArray), effect.FetchError),
  started: Int,
  ended: Int,
  source: trace.Source,
) -> #(trace.Generation, Result(chat.Completion(tool.Call), String), Recorder) {
  let key = cache_key(request)
  let #(recorder, request_cid) =
    recorder.store_binary(recorder, redact_bytes(recorder, request.body))
  let #(status, response_cid, usage, result, recorder) = case response {
    Ok(response) -> {
      let #(recorder, response_cid) =
        recorder.store_binary(recorder, redact_bytes(recorder, response.body))
      #(
        response.status,
        Some(response_cid),
        usage.from_response(response.body),
        provider.completion_response(llm, response),
        recorder,
      )
    }
    Error(reason) -> #(
      0,
      None,
      trace.no_usage(),
      Error(
        "request to "
        <> uri.to_string(request.to_uri(request))
        <> " failed: "
        <> effect.describe_fetch_error(reason),
      ),
      recorder,
    )
  }
  let #(thinking, content, tool_calls, error) = case result {
    Ok(chat.Completion(thinking:, content:, tool_calls:)) -> #(
      thinking,
      content,
      list.index_map(tool_calls, fn(call, index) {
        let tool.Call(function: tool.FunctionCall(name:, arguments:), ..) = call
        trace.ToolCall(
          id: call_id(id, index),
          name:,
          arguments: json.to_string(utils.fields_to_json(arguments)),
        )
      }),
      None,
    )
    Error(reason) -> #("", "", [], Some(reason))
  }
  let generation =
    trace.Generation(
      id:,
      started:,
      ended:,
      key:,
      request: request_cid,
      response: response_cid,
      status:,
      thinking:,
      content:,
      tool_calls:,
      usage:,
      source:,
      error:,
    )
  #(generation, result, recorder)
}

/// Full request identity, including headers, query, body and authority.
pub fn cache_key(request: Request(BitArray)) -> String {
  recorded.fingerprint(http.request_to_eyg(request), traces.sha256)
}

fn redact_bytes(recorder, bytes: BitArray) -> BitArray {
  case bit_array.to_string(bytes) {
    Ok(text) -> <<recorder.redact_text(recorder, text):utf8>>
    Error(Nil) -> bytes
  }
}

fn result_to_message(
  call_id: String,
  result: Result(tool.Return, String),
) -> chat.Message(a) {
  case result {
    Ok(tool.Return(text, images)) -> {
      chat.ToolResultMessage(
        tool_call_id: call_id,
        text: agent.tool_result_text(text),
        images:,
      )
    }
    Error(reason) ->
      chat.ToolResultMessage(
        tool_call_id: call_id,
        text: agent.tool_result_text(reason),
        images: [],
      )
  }
}

// ---------------------------- toools

fn execute_call(
  session: Session(harness_computer.Effect),
  call: tool.FunctionCall,
  eyg_state: execute.State,
  trace: Trace,
  call_id: String,
) -> system.Effect(#(Result(tool.Return, String), execute.State, Trace)) {
  let tool.FunctionCall(name, arguments) = call
  case agent.cast_tool_call(name, arguments) {
    Ok(call) -> {
      use Nil <- system.then(system.stdout(log_line(session.styled, call)))
      case call {
        agent.Run(code) -> {
          use executed <- system.then(record_tool_run(
            session,
            code,
            eyg_state,
            trace.recorder,
            call_id,
          ))
          let Executed(result:, state: eyg_state, output:, run:, recorder:) =
            executed
          let result = case result {
            // current state is not used by the CLI implementation, this will need to change.
            Ok(Some(value)) ->
              Ok(
                tool.Return(
                  run_tool.report(output, agent.inspect_result(value)),
                  [],
                ),
              )
            Ok(None) -> Ok(tool.Return(run_tool.report(output, ""), []))
            Error(reason) -> Error(run_tool.report(output, reason))
          }
          use Nil <- system.then(
            system.stdout(log_result(session.styled, result)),
          )
          let trace =
            Trace(..trace, recorder:)
            |> add(trace.Execution(run))
          system.Done(#(result, eyg_state, trace))
        }
      }
    }
    Error(reason) ->
      system.Done(#(
        Error(agent.describe_failure(reason, name, arguments)),
        eyg_state,
        trace,
      ))
  }
}

fn log_line(noninteractive, call) {
  case call {
    agent.Run(code) ->
      terminal.style(
        noninteractive,
        ansi.bg_bright_green,
        "Executing EYG code.",
      )
      <> "\n"
      <> terminal.style(noninteractive, ansi.dim, code)
  }
}

/// Summarise a tool call result so the user can see what the agent saw.
fn log_result(noninteractive, result: Result(tool.Return, String)) -> String {
  case result {
    Ok(tool.Return(text:, ..)) ->
      terminal.style(noninteractive, ansi.green, "ok ")
      <> terminal.style(noninteractive, ansi.dim, truncate(text))
    Error(reason) ->
      terminal.style(noninteractive, ansi.red, "error ")
      <> terminal.style(noninteractive, ansi.dim, truncate(reason))
  }
}

fn truncate(text) {
  case string.length(text) > 500 {
    True -> string.slice(text, 0, 500) <> "..."
    False -> text
  }
}

// ---------------------- run

/// The result of running a tool call's code.
pub type Executed {
  Executed(
    result: Result(Option(execute.Value), String),
    state: execute.State,
    /// Text written to standard out and error, newest first.
    output: List(String),
    run: run.Run,
    recorder: Recorder,
  )
}

/// Type check, pin and run code from a tool call, recording every effect.
pub fn record_tool_run(
  session: Session(harness_computer.Effect),
  code: String,
  eyg_state: execute.State,
  recorder: Recorder,
  call_id: String,
) -> system.Effect(Executed) {
  let recorder = recorder.restart(recorder)
  use started <- system.then(system.now())
  let finished = fn(result, state, output, program, lock, outcome, recorder) {
    use ended <- system.map(system.now())
    let run =
      run.Run(
        id: call_id,
        kind: run.Tool(call_id),
        code:,
        origin: run.Inline,
        program:,
        lock: recorder.lock_secrets(recorder, lock),
        cwd: session.cwd,
        journal: recorder.journal(recorder),
        outcome:,
        started:,
        ended:,
      )
    Executed(result:, state:, output:, run:, recorder:)
  }
  let rejected = fn(reason, state) {
    let message = recorder.redact_text(recorder, reason)
    finished(
      Error(reason),
      state,
      [],
      None,
      lock.empty(),
      run.Rejected(message),
      recorder,
    )
  }
  case source.parse_input(code, source.Stdin) {
    Error(reason) -> rejected(reason, eyg_state)
    Ok(source) -> {
      use errors <- system.then(type_check(session, source, eyg_state))
      case errors {
        [_, ..] -> rejected("type error", eyg_state)
        [] -> {
          use #(pinned, eyg_state, recorder) <- system.then(pin.pin(
            source,
            session.cwd,
            eyg_state,
            recorder,
            import_gate(session.policy, source.1),
          ))
          case pinned {
            Error(reason) -> rejected(reason, eyg_state)
            Ok(pinned) -> {
              let scope = [#("context", session.context.value)]
              use #(outcome, recorder, #(eyg_state, output)) <- system.then(
                record.run_block(
                  source,
                  scope,
                  pinned,
                  session.cwd,
                  recorder,
                  handler(session),
                  #(eyg_state, []),
                ),
              )
              let #(result, outcome, recorder) = case outcome {
                record.Completed(#(Some(value), _)) -> {
                  let #(encoded, recorder) = recorder.encode(recorder, value)
                  #(Ok(Some(value)), run.Returned(encoded), recorder)
                }
                record.Completed(#(None, _)) -> #(
                  Ok(None),
                  run.Finished,
                  recorder,
                )
                record.Raised(#(
                  break.UnhandledEffect("Unreproducible", value.String(reason)),
                  _,
                  _,
                  _,
                )) -> {
                  let reason = cohort.unreproducible(reason)
                  #(Error(reason), run.Failed(reason), recorder)
                }
                record.Raised(#(reason, location, _env, k)) -> {
                  let reason =
                    execute.render_error(reason, location, k, session.cwd)
                  #(
                    Error(reason),
                    run.Failed(recorder.redact_text(recorder, reason)),
                    recorder,
                  )
                }
                record.Exited(status:) -> #(
                  Error(
                    "the program exited with status " <> int.to_string(status),
                  ),
                  run.Exited(status),
                  recorder,
                )
              }
              finished(
                result,
                eyg_state,
                output,
                Some(pinned.program),
                pinned.lock,
                outcome,
                recorder,
              )
            }
          }
        }
      }
    }
  }
}

/// Run code as a tool call would, without keeping the recording.
pub fn check_and_execute(
  session: Session(harness_computer.Effect),
  code: String,
  eyg_state: execute.State,
) -> system.Effect(
  #(
    Result(#(Option(execute.Value), execute.Scope), String),
    execute.State,
    List(String),
  ),
) {
  use executed <- system.map(record_tool_run(
    session,
    code,
    eyg_state,
    recorder.new(traces.sha256),
    "check",
  ))
  let Executed(result:, state:, output:, ..) = executed
  #(result.map(result, fn(value) { #(value, []) }), state, output)
}

fn type_check(session: Session(_), source, eyg_state) {
  let base =
    infer.pure()
    |> infer.with_effects(interface.types(
      dict.values(session.policy) |> list.map(fn(i) { i.interface }),
    ))
    |> infer.with_effect("Abort", t.String, t.Never)
  // this is an infer context
  let context =
    infer.Context(..base, env: [#("context", session.context.type_), ..base.env])
  use #(_, _, errors, _) <- system.map(check.check_from(
    source,
    session.cwd,
    context,
    eyg_state,
    import_gate(session.policy, source.1),
    // Don't use check_from instead expose the lookup function from check so reference lookup is reusable.
  ))
  errors
}

/// The ReadFile request a relative import of `path` is decided by.
fn import_request(path) {
  value.Record(
    dict.from_list([
      #("path", value.String(path)),
      #("offset", value.Integer(0)),
      #("limit", value.Integer(100_000_000)),
    ]),
  )
}

/// Decide the agent's relative imports when type checking, as they are decided when it runs.
/// Policies are pure so asking the ReadFile gate performs no effects.
fn import_gate(
  policy: policy.Policy(harness_computer.Effect, source.Location),
  meta: source.Location,
) {
  fn(path, state) {
    use #(decided, state) <- system.map(decide(
      policy,
      "ReadFile",
      import_request(path),
      meta,
      state,
    ))
    let path = case decided {
      policy.Perform(_, modified) ->
        cast.field("path", cast.as_string, modified)
        |> result.replace_error(Nil)
      policy.Resume(_) | policy.Failed(_) | policy.Unavailable -> Error(Nil)
    }
    #(path, state)
  }
}

fn handler(
  session: Session(harness_computer.Effect),
) -> record.Handler(#(execute.State, List(String))) {
  policy_handler(session.policy)
}

/// Answer effects through the policy, recording how each was answered.
/// Text written to standard out or error is kept for the tool result.
fn policy_handler(
  policy: policy.Policy(harness_computer.Effect, source.Location),
) -> record.Handler(#(execute.State, List(String))) {
  fn(label, lift, meta: source.Location, handler_state) {
    let #(state, output) = handler_state
    use resolved <- system.then(resolve_policy_input(label, lift, meta.origin))
    case resolved {
      // Path resolution failures are ordinary filesystem effect errors.
      Error(reason) ->
        system.Done(#(
          record.Answered(
            value.error(value.String(reason)),
            journal.Mocked,
            None,
          ),
          handler_state,
        ))
      Ok(resolved) -> {
        use #(decided, state) <- system.then(decide_resolved(
          policy,
          label,
          resolved,
          meta,
          state,
        ))
        case decided {
          policy.Perform(interface, modified) ->
            case interface.decode(modified) {
              Ok(harness_computer.Exit(status)) ->
                system.Done(#(record.Halted(status), #(state, output)))
              Ok(effect) -> {
                let performed = computer.extrinsic(effect, meta.origin)
                // Capture the actual write after policy transformation while
                // still forwarding it to the terminal.
                let output = case performed {
                  system.WriteStdout(text, _) -> [text, ..output]
                  system.WriteStderr(text, _) -> [text, ..output]
                  _ -> output
                }
                let answer = case
                  recorded.encode(modified) == recorded.encode(resolved)
                {
                  True -> journal.Gated
                  False ->
                    journal.Altered(recorded.fingerprint(
                      modified,
                      traces.sha256,
                    ))
                }
                use reply <- system.map(performed)
                #(
                  record.Answered(
                    reply,
                    answer,
                    record.requested_path(label, modified),
                  ),
                  #(state, output),
                )
              }
              Error(reason) ->
                system.Done(#(record.Refused(reason), #(state, output)))
            }
          policy.Resume(returned) ->
            system.Done(#(
              record.Answered(
                returned,
                journal.Mocked,
                record.requested_path(label, resolved),
              ),
              #(state, output),
            ))
          policy.Failed(debug) ->
            system.Done(#(record.Failed(debug), #(state, output)))
          policy.Unavailable ->
            system.Done(#(
              record.Refused(break.UnhandledEffect(label, lift)),
              #(state, output),
            ))
        }
      }
    }
  }
}

/// Resolve filesystem paths before a policy sees them. Other request fields
/// stay intact, and the interface decoder still validates malformed requests.
///
/// This is an unfortunet amount of knowledge about the effects.
/// Maybe all filesystem effects should be absolute
fn resolve_policy_input(label, lift, origin) {
  case label, lift {
    "ReadFile", value.Record(fields)
    | "WriteFile", value.Record(fields)
    | "AppendFile", value.Record(fields)
    | "Commit", value.Record(fields)
    ->
      case dict.get(fields, "path") {
        Ok(value.String(path)) -> {
          use resolved <- system.map(source.resolve_filepath(origin, path))
          use path <- result.map(resolved)
          value.Record(dict.insert(fields, "path", value.String(path)))
        }
        _ -> system.Done(Ok(lift))
      }
    "DeleteFile", value.String(path)
    | "MakeDirectory", value.String(path)
    | "ReadDirectory", value.String(path)
    -> {
      use resolved <- system.map(source.resolve_filepath(origin, path))
      result.map(resolved, value.String)
    }
    _, _ -> system.Done(Ok(lift))
  }
}

/// Call the gate with absolute filesystem paths. Policy redirects must also
/// use absolute paths. Unchecked effects are always performed.
/// This could take a call as a continuation in which case the need for state would drop out
/// To extract to policy would require the continuation change
fn decide(
  policy: policy.Policy(harness_computer.Effect, source.Location),
  label: String,
  lift: execute.Value,
  meta: source.Location,
  state: execute.State,
) -> system.Effect(
  #(policy.Action(source.Location, harness_computer.Effect), execute.State),
) {
  use resolved <- system.then(resolve_policy_input(label, lift, meta.origin))
  case resolved {
    Ok(lift) -> decide_resolved(policy, label, lift, meta, state)
    // Path resolution failures are ordinary filesystem effect errors.
    Error(reason) ->
      system.Done(#(policy.Resume(value.error(value.String(reason))), state))
  }
}

fn decide_resolved(policy, label, lift, meta, state) {
  case dict.get(policy, label) {
    Ok(policy.Interface(interface, policy.Gated(gate))) -> {
      let return = expression.call(gate, [#(lift, meta)])
      use #(result, state) <- system.map(execute.pure_loop(return, state))
      let decided = case result {
        Ok(value) ->
          case policy.decision_from_value(value) {
            Ok(policy.Pass(modified)) -> policy.Perform(interface, modified)
            Ok(policy.Mock(returned)) -> policy.Resume(returned)
            Error(Nil) ->
              policy.Failed(#(
                break.IncorrectTerm(expected: "Pass/Mock", got: value),
                meta,
                builtin.default([]),
                state.Empty,
              ))
          }
        Error(debug) -> policy.Failed(debug)
      }
      #(decided, state)
    }
    Ok(policy.Interface(interface, policy.Unrestricted)) ->
      system.Done(#(policy.Perform(interface, lift), state))
    Error(Nil) -> system.Done(#(policy.Unavailable, state))
  }
}

// Only deterministic computations over supplied values bypass policy.
// Randomness and process termination are observable effects, even without file IO.
pub const rule_mapping = [
  #("AppendFile", policy.PolicyField("append_file")),
  #("CreateKey", policy.PolicyField("create_key")),
  #("CWD", policy.PolicyField("cwd")),
  #("DecodeJSON", policy.Unchecked),
  #("DeleteFile", policy.PolicyField("delete_file")),
  #("Env", policy.PolicyField("env")),
  #("Exit", policy.PolicyField("exit")),
  #("EYGParse", policy.Unchecked),
  #("Fetch", policy.PolicyField("fetch")),
  #("Flip", policy.PolicyField("flip")),
  #("Hash", policy.Unchecked),
  #("MakeDirectory", policy.PolicyField("make_directory")),
  #("Now", policy.PolicyField("now")),
  #("Random", policy.PolicyField("random")),
  #("ReadDirectory", policy.PolicyField("read_directory")),
  #("ReadFile", policy.PolicyField("read_file")),
  #("Sign", policy.Unchecked),
  #("Sleep", policy.PolicyField("sleep")),
  #("StandardError", policy.PolicyField("standard_error")),
  #("StandardIn", policy.PolicyField("standard_in")),
  #("StandardOut", policy.PolicyField("standard_out")),
  #("WriteFile", policy.PolicyField("write_file")),
]

/// Write the chat in the opencode session export format.
fn export(
  session: Session(harness_computer.Effect),
  history: List(chat.Message(tool.Call)),
  path: String,
) -> system.Effect(Nil) {
  use time <- system.then(system.now())
  let path = case path {
    "" -> "overlay-session-" <> int.to_string(time) <> ".json"
    path -> path
  }
  let exported =
    export.encode(
      export.Session(
        id: "ses_" <> int.to_string(time),
        directory: session.cwd,
        provider_id: provider.id(session.llm.provider),
        model_id: session.llm.model,
        time:,
      ),
      list.reverse(history),
    )
    |> json.to_string
  use resolved <- system.then(source.resolve_filepath(source.Pipe, path))
  let path = result.unwrap(resolved, path)
  use result <- system.then(system.write_file(path, exported))
  system.stdout(case result {
    Ok(Nil) -> "exported session to " <> path
    Error(reason) ->
      terminal.style(
        session.styled,
        ansi.red,
        "failed to export session: " <> string.inspect(reason),
      )
  })
}
