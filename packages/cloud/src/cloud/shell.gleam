//// A channel shell prepared for the current process.
////
//// Every program run for a channel, posted by a person, run by the channel's agent,
//// run by a trigger or by a subagent, is run with the channel's `channel_shell` policy.
//// Preparing a shell evaluates the workspace configuration in the current process,
//// see `notes/cloud-process-boundaries.md`.

import cloud/agent
import cloud/beam/execute
import cloud/config
import cloud/skills
import cloud/trigger
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/dict
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import overlay/agent as overlay
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
  let subagent = fn(task) {
    turn(shell, [], task) |> result.map(agent.last_reply)
  }
  Ok(Shell(..shell, host: execute.Host(..host, subagent:)))
}

/// Run a program, the variables in scope are given.
pub fn run(
  shell: Shell,
  code: String,
  scope: List(#(String, execute.Value)),
) -> execute.Run {
  execute.run(code, scope, shell.channel.shell, shell.host, shell.state).0
}

/// Run a trigger's script for an event.
pub fn run_script(
  shell: Shell,
  script: trigger.Script,
  event: execute.Value,
) -> execute.Run {
  let scope = [#("event", event)]
  case script {
    trigger.Source(code) -> run(shell, code, scope)
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
        shell.state,
      ).0
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
) -> Result(agent.History, String) {
  let Shell(workspace:, channel:, ..) = shell
  let effects =
    dict.values(channel.shell) |> list.map(fn(entry) { entry.interface })
  let readme =
    [
      shell.location,
      workspace.readme,
      channel.readme,
      skills.render(skills.index(shell.host.files)),
    ]
    |> list.filter(fn(section) { section != "" })
    |> string.join("\n\n")
  let context = agent.context(workspace.state.origin, effects, readme)
  let complete = shell.completer(channel.llm, context)
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
  agent.turn(history, input, complete, fn(code) {
    let execute.Run(result:, output:) = run(shell, code, scope)
    let printed = list.map(output, execute.output_text)
    case result {
      Ok(value) ->
        Ok(run.report(
          printed,
          value |> option.map(overlay.inspect_result) |> option.unwrap(""),
        ))
      Error(reason) -> Error(run.report(printed, reason))
    }
  })
}
