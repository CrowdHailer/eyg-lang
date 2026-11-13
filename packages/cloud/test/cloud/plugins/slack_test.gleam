import cloud/native_input as input
import cloud/slack/api/schema
import cloud/slack/events as slack
import gleam/dict
import gleam/json
import gleam/option.{None, Some}

const me = slack.Me(user: "UBOT", bot: "BBOT")

fn message(ts, user, text) {
  schema.Message(
    ts:,
    data: json.null(),
    thread_ts: None,
    reply_count: 0,
    subtype: None,
    deleted_ts: None,
    user: Some(user),
    bot_id: None,
    text:,
    latest_reply: None,
    reactions: [],
  )
}

pub fn new_messages_are_posted_test() {
  let #(events, known, threads) =
    slack.changes(
      "C1",
      None,
      dict.new(),
      [message("1.0", "U1", "a &amp; b")],
      me,
    )
  let assert [event] = events
  let posted = input.event(event, "SlackMessage", slack.input_type())
  assert input.text(input.field(posted, "message"), "text") == "a &amp; b"
  assert event.platform == "slack"
  assert event.channel == "C1"
  assert event.reply == Some("1.0")
  assert !input.bool(posted, "is_self")
  assert dict.size(known) == 1
  assert threads == []
}

pub fn seen_messages_are_not_posted_again_test() {
  let messages = [message("1.0", "U1", "hi")]
  let #(_, known, _) = slack.changes("C1", None, dict.new(), messages, me)
  let #(events, _, _) = slack.changes("C1", None, known, messages, me)
  assert events == []
}

pub fn own_messages_are_self_test() {
  let #(events, _, _) =
    slack.changes("C1", None, dict.new(), [message("1.0", "UBOT", "hi")], me)
  let assert [event] = events
  let posted = input.event(event, "SlackMessage", slack.input_type())
  assert input.bool(posted, "is_self")
}

pub fn new_reactions_are_reported_test() {
  let first = message("1.0", "U1", "a link")
  let #(_, known, _) = slack.changes("C1", None, dict.new(), [first], me)
  let reacted =
    schema.Message(..first, reactions: [schema.Reaction("books", ["U2"])])
  let #(events, known, _) = slack.changes("C1", None, known, [reacted], me)
  let assert [event] = events
  let payload = input.event(event, "SlackReaction", slack.input_type())
  assert input.text(input.field(payload, "message"), "ts") == "1.0"
  assert input.text(payload, "user") == "U2"
  assert input.text(payload, "reaction") == "books"
  let #(events, _, _) = slack.changes("C1", None, known, [reacted], me)
  assert events == []
}

pub fn changed_threads_are_fetched_test() {
  let parent = message("1.0", "U1", "start")
  let #(_, known, _) = slack.changes("C1", None, dict.new(), [parent], me)
  let replied = schema.Message(..parent, latest_reply: Some("2.0"))
  let #(_, known, threads) = slack.changes("C1", None, known, [replied], me)
  assert threads == [#("1.0", "1.0")]
  let replied = schema.Message(..parent, latest_reply: Some("3.0"))
  let #(_, _, threads) = slack.changes("C1", None, known, [replied], me)
  assert threads == [#("1.0", "2.0")]
}

pub fn replies_are_in_the_thread_test() {
  let reply =
    schema.Message(..message("2.0", "U1", "reply"), thread_ts: Some("1.0"))
  let #(events, _, _) =
    slack.changes("C1", Some("1.0"), dict.new(), [reply], me)
  let assert [event] = events
  let _ = input.event(event, "SlackMessage", slack.input_type())
  assert event.reply == Some("1.0")
}

pub fn notices_are_ignored_test() {
  let join =
    schema.Message(
      ..message("1.0", "U1", "joined"),
      subtype: Some("channel_join"),
    )
  let #(events, _, _) = slack.changes("C1", None, dict.new(), [join], me)
  assert events == []
}
