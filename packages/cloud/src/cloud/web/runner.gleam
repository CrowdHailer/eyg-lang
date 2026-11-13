//// Run programs for people using the web: the web shell and the HTTP API.
////
//// An unbound program runs with the person's shell policy: the admin's has every effect,
//// everyone else's is one of the `shells` in `cloud.eyg`.
//// A program bound to a channel runs as that channel, with its shell policy and host,
//// as the channel's agent would.

import cloud/api
import cloud/beam/execute
import cloud/instance
import cloud/overlay as agent
import cloud/registry
import cloud/session
import cloud/shell
import cloud/tracing
import cloud/users.{type User}
import cloud/workspace
import eyg/interpreter/capture
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string

pub type Context {
  Context(
    registry: Subject(registry.Message),
    instance: instance.Loader,
    state: execute.State,
  )
}

pub type Binding {
  Binding(workspace: String, channel: String)
}

/// The policy of a person's unbound shell.
pub fn policy(context: Context, user: User) -> Result(execute.Policy, String) {
  case user.admin {
    True -> Ok(execute.unrestricted())
    False -> {
      use instance <- result.try(context.instance())
      list.key_find(instance.shells, user.shell)
      |> result.replace_error("no shell named " <> user.shell)
    }
  }
}

/// Run a program, returning its outcome and the binding for the next program,
/// which the program may change with `Bind` and `Unbind`.
pub fn run(
  context: Context,
  user: User,
  binding: Option(Binding),
  code: String,
  scope: List(#(String, execute.Value)),
) -> #(execute.Run, Option(Binding)) {
  // Capture before sending: an evaluated closure may retain a huge environment.
  case list.all(scope, fn(pair) { capture.is_capturable(pair.1) }) {
    False -> #(
      execute.Run(Error("Cannot send a continuation to a session"), []),
      binding,
    )
    True -> {
      let scope =
        list.map(scope, fn(pair) { #(pair.0, capture.capture(pair.1, #(0, 0))) })
      let executor = process.call(context.registry, 5000, registry.Executor)
      // Binding grants a channel policy and outbound address, never its files.
      let identity = "web:" <> user.name
      let reply = process.new_subject()
      process.send(
        executor,
        session.WithFiles(identity, None, fn(execution) {
          let #(run, binding, execution) = case execution {
            Error(reason) -> #(
              execute.Run(Error(reason), []),
              binding,
              context.state,
            )
            Ok(execution) -> {
              let scope =
                list.map(scope, fn(pair) {
                  let assert Ok(value) = expression.execute(pair.1, [])
                  #(pair.0, value)
                })
              run_in_session(context, user, binding, code, scope, execution)
            }
          }
          let value = case run.result {
            Error(reason) -> Error(reason)
            Ok(None) -> Ok(None)
            Ok(Some(value)) ->
              case capture.is_capturable(value) {
                True -> Ok(Some(capture.capture(value, #(0, 0))))
                False -> Error("Cannot return a continuation from a session")
              }
          }
          process.send(reply, #(value, run.output, binding))
          let output = case run.result {
            Ok(Some(value)) -> simple_debug.inspect(value)
            Ok(None) -> ""
            Error(reason) -> "Error: " <> reason
          }
          let printed =
            list.reverse(run.output)
            |> list.map(execute.output_text)
            |> string.join("\n")
          #(code <> "\n" <> printed <> "\n" <> output, execution)
        }),
      )
      let assert Ok(#(value, output, binding)) =
        process.receive(reply, 86_400_000)
      let value =
        result.map(
          value,
          option.map(_, fn(ir) {
            let assert Ok(value) = expression.execute(ir, [])
            value
          }),
        )
      #(execute.Run(value, output), binding)
    }
  }
}

fn run_in_session(
  context: Context,
  user: User,
  binding: Option(Binding),
  code: String,
  scope: List(#(String, execute.Value)),
  execution: execute.State,
) {
  let assert Some(session_files) = execution.files
  let files = execute.session_files(session_files.state)
  let changes = process.new_subject()
  let bind = fn(target) {
    case target {
      Some(#(workspace, channel)) -> {
        use _ <- result.map(channel_host(context, workspace, channel))
        process.send(changes, Some(Binding(workspace, channel)))
      }
      None -> Ok(process.send(changes, None))
    }
  }
  let at = case binding {
    Some(Binding(workspace:, channel:)) -> workspace <> " #" <> channel
    None -> "unbound"
  }
  let span =
    tracing.start("eyg.cloud.web", None, [
      #("eyg.cloud.user", tracing.text(user.name)),
      #("eyg.cloud.binding", tracing.text(at)),
    ])
  let trace = Some(tracing.context(span))
  let outcome = case binding {
    None -> {
      use policy <- result.map(policy(context, user))
      let host =
        execute.Host(
          ..execute.configuration_host(fn(_) {
            Error("Secrets are only read by configuration")
          }),
          post: fn(_) { Error("Bind to a channel to post") },
          api: api.perform(context.registry, context.state, _),
          bind:,
          trace:,
          files:,
        )
      execute.checked(
        code,
        scope,
        policy,
        host,
        execute.State(..context.state, root: None, files: execution.files),
      )
    }
    Some(Binding(workspace:, channel:)) -> {
      use handle <- result.try(registry.workspace(context.registry, workspace))
      use #(info, host) <- result.try(
        process.call(handle.workspace, 5000, workspace.WebHost(
          user.name,
          channel,
          _,
        )),
      )
      let host = execute.Host(..host, bind:, trace:, files:)
      let location =
        "You are in the channel #"
        <> info.name
        <> ", run from the web shell by "
        <> user.name
        <> "."
      use shell <- result.map(shell.prepare(
        handle.load,
        info,
        host,
        location,
        agent.complete,
      ))
      shell.run(
        shell,
        code,
        scope,
        execute.State(..shell.state, files: execution.files),
      )
    }
  }
  let #(run, execution) = case outcome {
    Ok(result) -> result
    Error(reason) -> #(execute.Run(Error(reason), []), execution)
  }
  tracing.end(span, [], case run.result {
    Ok(_) -> None
    Error(reason) -> Some(reason)
  })
  #(run, latest(changes, binding), execution)
}

fn channel_host(context: Context, workspace: String, channel: String) {
  use handle <- result.try(registry.workspace(context.registry, workspace))
  use #(info, host) <- result.map(
    process.call(handle.workspace, 5000, workspace.ChannelHost(channel, _)),
  )
  #(handle, info, host)
}

fn latest(changes, binding) {
  case process.receive(changes, 0) {
    Ok(binding) -> latest(changes, binding)
    Error(Nil) -> binding
  }
}
