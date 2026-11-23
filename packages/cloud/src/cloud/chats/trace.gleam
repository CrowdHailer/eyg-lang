//// OpenTelemetry spans for a chat, made from its journal.
////
//// The chat is one span and each turn is a span in it, from a message to the llm's reply.
//// Asking the llm for a completion is a span in its turn, from the entry before it to the completion.
//// Each tool call is a span from the completion that made it to the result recorded for it,
//// the spans of the code it ran are in the trace of its shell.

import cloud/chats/event.{type Entry}
import cloud/shells/trace.{type Span, Span}
import gleam/json
import gleam/list
import gleam/option.{None, Some}

/// `log` is every entry of the chat's journal with the time it was recorded, in microseconds.
pub fn spans(chat: String, log: List(#(Int, Entry))) -> List(Span) {
  let log = list.index_map(log, fn(entry, i) { #(i, entry.0, entry.1) })
  case log, list.last(log) {
    [#(_, start, _), ..], Ok(#(_, end, _)) -> {
      let id = trace.span_id(chat, -1)
      let root =
        Span(id, None, "chat", False, start, end, [#("chat.id", chat)], None)
      [root, ..turns(chat, id, log, [])]
    }
    _, _ -> []
  }
}

// A turn starts with a message sent while the chat is idle and ends at a reply without tool calls.
fn turns(chat, parent, log, done) {
  case log {
    [] -> list.reverse(done) |> list.flatten
    [#(i, start, event.Sent(message)), ..rest] -> {
      let #(entries, rest) = split_turn(rest, [])
      let id = trace.span_id(chat, i)
      let #(end, error) = case list.last(entries) {
        Ok(#(_, at, event.Failed(reason))) -> #(at, Some(reason))
        Ok(#(_, at, event.Cancelled)) -> #(at, Some("cancelled"))
        Ok(#(_, at, event.Replied(completion))) if completion.tool_calls == [] -> #(
          at,
          None,
        )
        Ok(#(_, at, _)) -> #(at, Some("unfinished"))
        Error(Nil) -> #(start, Some("unfinished"))
      }
      let span =
        Span(
          id,
          Some(parent),
          "turn",
          False,
          start,
          end,
          [
            #("gen_ai.prompt", message),
          ],
          error,
        )
      let inner = steps(chat, id, start, entries)
      turns(chat, parent, rest, [[span, ..inner], ..done])
    }
    [_, ..rest] -> turns(chat, parent, rest, done)
  }
}

fn split_turn(log, entries) {
  case log {
    [] -> #(list.reverse(entries), [])
    [#(_, _, event.Replied(completion)) as entry, ..rest]
      if completion.tool_calls == []
    -> #(list.reverse([entry, ..entries]), rest)
    [#(_, _, event.Failed(_)) as entry, ..rest]
    | [#(_, _, event.Cancelled) as entry, ..rest] -> #(
      list.reverse([entry, ..entries]),
      rest,
    )
    [entry, ..rest] -> split_turn(rest, [entry, ..entries])
  }
}

// Completions start at the entry before them, tool calls at the completion that made them.
fn steps(chat, parent, previous, entries) {
  case entries {
    [] -> []
    [#(i, at, event.Replied(completion)), ..rest] -> {
      let asked =
        Span(
          trace.span_id(chat, i),
          Some(parent),
          "chat",
          True,
          previous,
          at,
          [
            #("gen_ai.operation.name", "chat"),
          ],
          None,
        )
      let calls =
        list.map(completion.tool_calls, fn(call) {
          let #(end, error) =
            list.find_map(rest, fn(entry) {
              case entry {
                #(_, end, event.Returned(id, result)) if id == call.id ->
                  Ok(
                    #(end, case result {
                      Ok(_) -> None
                      Error(reason) -> Some(reason)
                    }),
                  )
                _ -> Error(Nil)
              }
            })
            |> option.from_result
            |> option.unwrap(#(at, Some("no result was recorded")))
          Span(
            trace.span_id(chat <> call.id, i),
            Some(parent),
            "tool " <> call.function.name,
            False,
            at,
            end,
            [#("gen_ai.tool.call.id", call.id)],
            error,
          )
        })
      list.flatten([[asked], calls, steps(chat, parent, at, rest)])
    }
    [#(i, at, event.Failed(reason)), ..rest] -> [
      Span(
        trace.span_id(chat, i),
        Some(parent),
        "chat",
        True,
        previous,
        at,
        [
          #("gen_ai.operation.name", "chat"),
        ],
        Some(reason),
      ),
      ..steps(chat, parent, at, rest)
    ]
    [#(_, at, _), ..rest] -> steps(chat, parent, at, rest)
  }
}

/// An OTLP export request with every span of the chat.
pub fn encode(chat: String, spans: List(Span)) -> json.Json {
  trace.otlp(chat, "cloud/chats", spans)
}
