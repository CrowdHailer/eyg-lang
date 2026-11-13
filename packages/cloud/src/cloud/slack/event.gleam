//// Slack events currently supplied by the history poller.

import cloud/slack/api/schema
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleam/result

pub type Event {
  MessageCreate(
    ts: String,
    channel_id: String,
    content: String,
    thread_ts: String,
  )
}

pub fn from_message(
  channel_id: String,
  message: schema.Message,
) -> Result(Event, String) {
  let decoder = decode.field("text", decode.string, decode.success)
  use content <- result.map(
    json.parse(json.to_string(message.data), decoder)
    |> result.replace_error("Invalid Slack message text"),
  )
  MessageCreate(
    message.ts,
    channel_id,
    content,
    option.unwrap(message.thread_ts, message.ts),
  )
}

pub fn type_() {
  t.record([
    #("channel_name", t.String),
    #(
      "event",
      t.union([
        #(
          "MessageCreate",
          t.record([
            #("ts", t.String),
            #("channel_id", t.String),
            #("content", t.String),
            #("thread_ts", t.String),
          ]),
        ),
      ]),
    ),
  ])
}

pub fn to_eyg(channel_name: String, event: Event) -> v.Value(a, b) {
  let MessageCreate(ts, channel_id, content, thread_ts) = event
  v.Record(
    dict.from_list([
      #("channel_name", v.String(channel_name)),
      #(
        "event",
        v.Tagged(
          "MessageCreate",
          v.Record(
            dict.from_list([
              #("ts", v.String(ts)),
              #("channel_id", v.String(channel_id)),
              #("content", v.String(content)),
              #("thread_ts", v.String(thread_ts)),
            ]),
          ),
        ),
      ),
    ]),
  )
}
