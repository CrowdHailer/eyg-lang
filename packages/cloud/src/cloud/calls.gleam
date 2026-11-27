//// Tool calls run as shells. The code of each call is the only turn of a shell made for it,
//// and the calls run at the same time. Their changes are merged into the box by the box's process,
//// a change that conflicts with another call's change is rejected and the call returns the rejection.
////
//// A chat's llm makes tool calls, and an agent outside the service can send them through the API.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/data/db
import cloud/data/shells.{type Shell}
import cloud/shells/turn
import gleam/erlang/process
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import overlay/agent
import overlay/llm/tool
import overlay/tools/run
import pog

/// What a tool call returned, the text the llm is told, and the shell its code ran in if it ran.
pub type Returned {
  Returned(call: String, shell: Option(String), result: Result(String, String))
}

/// Run the calls in the box, `chat` is the chat whose llm made them.
/// A chat's call that already has a shell is finished in it rather than run again.
/// Results are in the order of the calls.
pub fn run(
  context: Context,
  box: String,
  chat: Option(String),
  calls: List(tool.Call),
) -> List(Returned) {
  let reply = process.new_subject()
  list.each(calls, fn(call) {
    process.spawn(fn() {
      process.send(reply, #(call.id, one(context, box, chat, call)))
    })
  })
  let returned =
    list.map(calls, fn(_) {
      // A call can sleep or make slow requests.
      case process.receive(reply, 3_600_000) {
        Ok(returned) -> returned
        Error(Nil) -> #("", Returned("", None, Error("the call timed out")))
      }
    })
  list.map(calls, fn(call: tool.Call) {
    case list.key_find(returned, call.id) {
      Ok(returned) -> returned
      Error(Nil) -> Returned(call.id, None, Error("the call timed out"))
    }
  })
}

fn one(context: Context, box: String, chat: Option(String), call: tool.Call) {
  let tool.Call(id, tool.FunctionCall(name, arguments)) = call
  case agent.cast_tool_call(name, arguments) {
    Error(reason) ->
      Returned(id, None, Error(agent.describe_failure(reason, name, arguments)))
    Ok(agent.Run(code)) ->
      case shell(context, box, chat, id) {
        Error(reason) -> Returned(id, None, Error(describe(reason)))
        Ok(shell) ->
          Returned(id, Some(shell.id), case turn.once(context, shell, code) {
            Ok(#(Ok(text), output)) -> Ok(run.report(output, text))
            Ok(#(Error(reason), output)) -> Error(run.report(output, reason))
            Error(reason) -> Error(describe(reason))
          })
      }
  }
}

// The shell of the call, made if the call has none.
fn shell(
  context: Context,
  box: String,
  chat: Option(String),
  call: String,
) -> Result(Shell, box.Reason) {
  use rows <- result.try(query(
    context,
    shells.create(box, shells.Call(chat, call)),
  ))
  case rows, chat {
    [shell], _ -> Ok(shell)
    _, Some(chat) ->
      case query(context, shells.for_call(chat, call)) {
        Ok([shell]) -> Ok(shell)
        Ok(_) -> Error(box.Missing)
        Error(reason) -> Error(reason)
      }
    _, None -> Error(box.Failed("the shell could not be made"))
  }
}

fn describe(reason) {
  case reason {
    box.Missing -> "the box is missing"
    box.Taken -> "the box already exists"
    box.Conflict(paths) -> "File changes conflict\n" <> string.join(paths, "\n")
    box.Invalid(errors) ->
      "File changes rejected\n" <> string.join(errors, "\n")
    box.Failed(message) -> message
  }
}

fn query(context: Context, query) {
  db.execute(query, context.db)
  |> result.map(fn(returned: pog.Returned(_)) { returned.rows })
  |> result.map_error(fn(reason) { box.Failed(string.inspect(reason)) })
}
