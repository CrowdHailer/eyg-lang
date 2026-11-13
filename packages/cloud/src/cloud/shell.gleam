//// A channel shell prepared for the current process.
////
//// Every program run for a channel, posted by a person, run by the channel's agent,
//// run by a trigger or by a subagent, is run with the channel's `channel_shell` policy.
//// Preparing a shell evaluates the workspace configuration in the current process,
//// see `notes/cloud-process-boundaries.md`.

import cloud/beam/execute
import cloud/config
import cloud/overlay as agent
import cloud/skills
import cloud/tracing
import cloud/trigger
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import overlay/agent as overlay
import overlay/llm/chat
import overlay/tools/run

pub type Shell {
  Shell(
    workspace: config.Workspace,
    channel: config.Channel,
    host: execute.Host,
    state: execute.State,
    /// Where programs and agents in this shell are running, given to agents as context.
    location: String,
    completer: agent.Completer,
  )
}

/// Prepare the shell for a channel.
/// The host's subagents are run in the same shell, a subagent cannot start another.
pub fn prepare(
  load: config.Loader,
  info: config.ChannelInfo,
  host: execute.Host,
  location: String,
  completer: agent.Completer,
) -> Result(Shell, String) {
  use workspace <- result.try(load())
  use channel <- result.try(config.channel(workspace, info))
  let state = execute.State(..workspace.state, root: option.None)
  let shell = Shell(workspace:, channel:, host:, state:, location:, completer:)
  let subagent = fn(task, trace, state) {
    let shell = Shell(..shell, host: execute.Host(..shell.host, trace:))
    let #(history, state) = turn(shell, [], task, state, fn(_) { Nil })
    #(Ok(agent.last_reply(history)), state)
  }
  Ok(Shell(..shell, host: execute.Host(..host, subagent:)))
}

/// Run a program, the variables in scope are given.
pub fn run(
  shell: Shell,
  code: String,
  scope: List(#(String, execute.Value)),
  state: execute.State,
) -> #(execute.Run, execute.State) {
  execute.checked(code, scope, shell.channel.shell, shell.host, state)
}

/// Run a trigger's script for an event.
pub fn run_script(
  shell: Shell,
  script: trigger.Script,
  event: execute.Value,
  state: execute.State,
) -> #(execute.Run, execute.State) {
  let scope = [#("event", event)]
  case script {
    trigger.Source(code) -> run(shell, code, scope, state)
    trigger.Function(function) -> {
      let call = #(
        ir.Apply(function, #(ir.Variable("event"), #(0, 0))),
        #(0, 0),
      )
      execute.run_expression(
        call,
        scope,
        shell.channel.shell,
        shell.host,
        state,
      )
    }
  }
}

/// Call a trigger's pattern with an event.
/// Patterns are pure, a pattern that performs an effect fails.
pub fn matches(
  shell: Shell,
  pattern: trigger.Pattern,
  event: execute.Value,
) -> Result(Bool, String) {
  let argument = #(event, #(0, 0))
  let #(function, state) =
    execute.pure_loop(expression.execute(pattern, []), shell.state)
  let #(returned, _state) = case function {
    Ok(function) ->
      execute.pure_loop(expression.call(function, [argument]), state)
    Error(debug) -> #(Error(debug), state)
  }
  case returned {
    Ok(v.Tagged("True", _)) -> Ok(True)
    Ok(v.Tagged("False", _)) -> Ok(False)
    Ok(value) -> Error("pattern returned " <> simple_debug.inspect(value))
    Error(#(reason, _, _, _)) -> Error(simple_debug.describe(reason))
  }
}

/// Run one turn of an agent working in the shell.
pub fn turn(
  shell: Shell,
  history: agent.History,
  input: String,
  state: execute.State,
  emit: fn(execute.Output) -> Nil,
) -> #(agent.History, execute.State) {
  let Shell(workspace:, channel:, ..) = shell
  let effects =
    dict.values(channel.shell) |> list.map(fn(entry) { entry.interface })
  let readme =
    [
      shell.location,
      workspace.readme,
      channel.readme,
      skills.render(
        skills.index(case state.files {
          Some(files) -> execute.session_files(files.state)
          None -> shell.host.files
        }),
      ),
    ]
    |> list.filter(fn(section) { section != "" })
    |> string.join("\n\n")
  let context = agent.context(workspace.state.origin, effects, readme)
  // A turn is a span, each completion and each program the agent runs is inside it.
  let span =
    tracing.start("eyg.agent.turn", shell.host.trace, [
      #("eyg.cloud.location", tracing.text(shell.location)),
      #("gen_ai.request.model", tracing.text(channel.llm.model)),
    ])
  let shell =
    Shell(
      ..shell,
      host: execute.Host(..shell.host, trace: Some(tracing.context(span))),
    )
  let completion = shell.completer(channel.llm, context)
  let complete = fn(history) {
    tracing.span(
      "eyg.llm.completion",
      Some(tracing.context(span)),
      [#("gen_ai.request.model", tracing.text(channel.llm.model))],
      fn(_) { completion(history) },
      fn(result) {
        case result {
          Ok(_) -> None
          Error(reason) -> Some(reason)
        }
      },
    )
  }
  let scope = [
    #(
      "context",
      v.Record(
        dict.from_list([
          #("workspace", v.String(workspace.readme)),
          #("channel", v.String(channel.readme)),
        ]),
      ),
    ),
  ]
  let #(history, state, failure) =
    agent.complete_loop(
      [chat.UserMessage(input, []), ..history],
      complete,
      fn(code, state) {
        let #(execute.Run(result:, output:), state) =
          run(shell, code, scope, state)
        let printed = list.map(output, execute.output_text)
        list.reverse(output) |> list.each(emit)
        let result = case result {
          Ok(value) ->
            Ok(run.report(
              printed,
              value |> option.map(overlay.inspect_result) |> option.unwrap(""),
            ))
          Error(reason) -> Error(run.report(printed, reason))
        }
        #(result, state)
      },
      emit,
      state,
      agent.max_steps,
    )
  tracing.end(span, [], failure)
  #(history, state)
}
