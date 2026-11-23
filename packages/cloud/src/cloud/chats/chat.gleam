//// A chat with an llm about a box. Each chat has a process that replies to the messages sent to it,
//// one turn at a time, and records everything it does in the chat's journal, see `chats/event`.
////
//// The llm's tool calls run as shells in the box at the same time, see `cloud/calls`.
//// When they have all returned their results are recorded and the llm is asked again.
////
//// If the process stops the chat continues from its journal the next time it is used.
//// A completion that was not recorded is asked for again, completions have no effect outside the chat.
//// A completion of a long chat can take minutes, so it is waited for up to five.
//// A tool call that was running is finished in its shell, its code is not run twice.

import cloud/apex/context.{type Context}
import cloud/box
import cloud/calls
import cloud/chats/event.{type Entry}
import cloud/data/chats.{type Chat}
import cloud/data/db
import cloud/data/shells
import cloud/overlay
import cloud/registry
import cloud/shells/turn
import cloud/system
import gleam/dict
import gleam/erlang/process
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, Some}
import gleam/result
import gleam/string
import overlay/llm/chat
import overlay/llm/provider
import overlay/llm/tool
import pog

/// A new chat in the box with the llm configured as `llm`.
pub fn start(
  context: Context,
  box: String,
  llm: String,
) -> Result(Chat, box.Reason) {
  use Nil <- result.try(case dict.has_key(context.llms, llm) {
    True -> Ok(Nil)
    False -> Error(box.Invalid(["No llm is configured as " <> llm]))
  })
  use _ <- result.try(box.latest(context, box))
  case query(context, chats.create(box, llm)) {
    Ok([chat]) -> Ok(chat)
    Ok(_) -> Error(box.Failed("the chat could not be made"))
    Error(reason) -> Error(reason)
  }
}

pub fn find(context: Context, id: String) -> Result(Chat, box.Reason) {
  case query(context, chats.get(id)) {
    Ok([chat]) -> Ok(chat)
    Ok(_) -> Error(box.Missing)
    Error(reason) -> Error(reason)
  }
}

/// The most recent chats in any box, with the name of the box if it has one and when each was made.
/// Chats in transient boxes are left out unless `transient` is true.
pub fn recent(
  context: Context,
  limit: Int,
  transient: Bool,
) -> Result(List(#(Chat, Option(String), Int)), box.Reason) {
  query(context, chats.recent(limit, transient))
}

/// Send a message to the chat and wait for the llm's reply.
pub fn send(
  context: Context,
  chat: Chat,
  message: String,
) -> Result(Result(String, String), box.Reason) {
  use Nil <- result.try(append(context, chat, [event.Sent(message)]))
  reply(context, chat)
}

/// Reply to every message sent to the chat, in the chat's process, which replies to one at a time.
/// It is the chat's last reply if there is nothing to reply to.
pub fn reply(
  context: Context,
  chat: Chat,
) -> Result(Result(String, String), box.Reason) {
  registry.lookup(context.chats, chat.id, fn() { registry.serve(Nil) })
  |> registry.call(3_600_000, fn(_) { #(Nil, continue(context, chat)) })
}

// Ask the llm and run its tool calls until it has replied to every message.
fn continue(context: Context, chat: Chat) {
  use entries <- result.try(entries(context, chat.id))
  case event.next(entries) {
    event.Idle(reply) -> Ok(reply)
    event.Ask(history) -> {
      let replied =
        list.count(entries, fn(entry) {
          case entry {
            event.Replied(..) -> True
            _ -> False
          }
        })
      use entry <- result.try(ask(context, chat, history, replied))
      use Nil <- result.try(append(context, chat, [entry]))
      continue(context, chat)
    }
    event.Call(pending) -> {
      let returned = calls.run(context, chat.box, Some(chat.id), pending)
      let entries =
        list.map(returned, fn(returned) {
          event.Returned(returned.call, returned.result)
        })
      use Nil <- result.try(append(context, chat, entries))
      continue(context, chat)
    }
  }
}

fn ask(context: Context, chat: Chat, history: chat.History, replied: Int) {
  case dict.get(context.llms, chat.llm) {
    Error(Nil) ->
      Ok(event.Failed("the llm " <> chat.llm <> " is not configured"))
    Ok(llm) -> {
      let provider = overlay.box_context(context.state.origin)
      let completed =
        provider.completion(llm, provider, history, system.slow_fetch(300_000))(
          fn(completion) { completion },
        )
      Ok(case completed {
        Ok(completion) -> event.Replied(named(completion, replied))
        Error(reason) -> event.Failed(reason)
      })
    }
  }
}

// Each tool call needs an id of its own in the chat, it has a shell and a result.
// Some llms, such as Ollama's, give none, so calls without one are named by the completion and their place in it.
fn named(completion: chat.Completion(tool.Call), replied: Int) {
  let prefix = "call-" <> int.to_string(replied) <> "-"
  let tool_calls =
    list.index_map(completion.tool_calls, fn(call: tool.Call, i) {
      case call.id {
        "" -> tool.Call(..call, id: prefix <> int.to_string(i))
        _ -> call
      }
    })
  chat.Completion(..completion, tool_calls:)
}

/// Stop the chat replying and record that it was cancelled, so it does not continue.
/// Tool calls that are running are cancelled in their shells, changes that were merged are kept.
pub fn cancel(context: Context, chat: Chat) -> Result(Nil, box.Reason) {
  let process =
    registry.lookup(context.chats, chat.id, fn() { registry.serve(Nil) })
  case process.subject_owner(process) {
    Ok(pid) -> {
      let monitor = process.monitor(pid)
      process.kill(pid)
      let _ =
        process.new_selector()
        |> process.select_specific_monitor(monitor, fn(_) { Nil })
        |> process.selector_receive(5000)
      Nil
    }
    Error(Nil) -> Nil
  }
  use entries <- result.try(entries(context, chat.id))
  case event.next(entries) {
    event.Idle(_) -> Ok(Nil)
    event.Ask(_) -> append(context, chat, [event.Cancelled])
    event.Call(pending) -> {
      use running <- result.try(query(context, shells.of_chat(chat.id)))
      list.each(running, fn(running) {
        let #(shell, call) = running
        case list.any(pending, fn(pending) { Some(pending.id) == call }) {
          True -> {
            let _ = turn.cancel(context, shell)
            Nil
          }
          False -> Nil
        }
      })
      list.map(pending, fn(call) { event.Returned(call.id, Error("cancelled")) })
      |> list.append([event.Cancelled])
      |> append(context, chat, _)
    }
  }
}

/// Every entry in the chat's journal, with the time it was recorded in microseconds.
pub fn history(
  context: Context,
  chat: String,
) -> Result(List(#(Int, Entry)), box.Reason) {
  use _ <- result.try(find(context, chat))
  use recorded <- result.try(query(context, chats.entries(chat)))
  list.try_map(recorded, fn(recorded) {
    json.parse(recorded.entry, event.decoder())
    |> result.map(fn(entry) { #(recorded.at, entry) })
    |> result.map_error(fn(reason) { box.Failed(string.inspect(reason)) })
  })
}

pub fn entries(
  context: Context,
  chat: String,
) -> Result(List(Entry), box.Reason) {
  history(context, chat)
  |> result.map(list.map(_, fn(entry) { entry.1 }))
}

/// The shells of the chat, by the tool call they ran if they ran one.
pub fn shells(
  context: Context,
  chat: String,
) -> Result(List(#(shells.Shell, Option(String))), box.Reason) {
  query(context, shells.of_chat(chat))
}

fn append(context: Context, chat: Chat, entries: List(Entry)) {
  list.try_each(entries, fn(entry) {
    query(context, chats.append(chat.id, json.to_string(event.encode(entry))))
    |> result.replace(Nil)
  })
}

fn query(context: Context, query) {
  db.execute(query, context.db)
  |> result.map(fn(returned: pog.Returned(_)) { returned.rows })
  |> result.map_error(fn(reason) { box.Failed(string.inspect(reason)) })
}
