//// Run programs for people using the web: the web shell and the HTTP API.
////
//// An unbound program runs with the person's shell policy: the admin's has every effect,
//// everyone else's is one of the `shells` in `cloud.eyg`.
//// A program bound to a channel runs as that channel, with its shell policy and host,
//// as the channel's agent would.

import cloud/agent
import cloud/api
import cloud/beam/execute
import cloud/instance
import cloud/registry
import cloud/shell
import cloud/users.{type User}
import cloud/workspace
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result

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
        )
      execute.run(code, scope, policy, host, context.state).0
    }
    Some(Binding(workspace:, channel:)) -> {
      use #(handle, info, host) <- result.try(channel_host(
        context,
        workspace,
        channel,
      ))
      let host = execute.Host(..host, bind:)
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
      shell.run(shell, code, scope)
    }
  }
  let run = case outcome {
    Ok(run) -> run
    Error(reason) -> execute.Run(Error(reason), [])
  }
  #(run, latest(changes, binding))
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
