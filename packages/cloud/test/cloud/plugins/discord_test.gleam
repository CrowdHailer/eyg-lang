import cloud/discord/api/schema
import cloud/discord/events as discord
import cloud/native_input as input
import gleam/dict
import gleam/int
import gleam/option.{None, Some}

const me = "900"

/// Snowflakes for messages sent `ms` milliseconds after the Discord epoch.
fn id(ms) {
  int.to_string(ms * 4_194_304)
}

fn started(ms) {
  ms + 1_420_070_400_000
}

fn user(id) {
  schema.User(id:, username: "u" <> id, bot: False)
}

fn post(id, author, content, reactions) {
  schema.Post(
    id:,
    channel_id: "C1",
    kind: 0,
    author: user(author),
    webhook: False,
    content:,
    reactions:,
  )
}

fn book(count) {
  schema.Reaction(schema.Emoji(None, "📖"), count)
}

pub fn new_messages_are_posted_test() {
  let messages = [post(id(10), "1", "hello", [])]
  let #(events, lookups, seen) =
    discord.changes("C1", None, discord.unseen(), messages, me, started(5))
  let assert [event] = events
  let posted = input.event(event, "DiscordMessage", discord.input_type())
  assert input.text(input.field(posted, "message"), "content") == "hello"
  assert event.platform == "discord"
  assert event.channel == "C1"
  assert event.reply == Some(id(10))
  assert !input.bool(posted, "is_self")
  assert lookups == []
  assert seen.newest == Some(id(10))
}

pub fn history_is_not_posted_test() {
  let messages = [post(id(10), "1", "old", [book(2)])]
  let #(events, lookups, _) =
    discord.changes("C1", None, discord.unseen(), messages, me, started(20))
  assert events == []
  assert lookups == []
}

pub fn seen_messages_are_not_posted_again_test() {
  let messages = [post(id(10), "1", "hello", [])]
  let #(_, _, seen) =
    discord.changes("C1", None, discord.unseen(), messages, me, started(5))
  let #(events, _, _) =
    discord.changes("C1", None, seen, messages, me, started(5))
  assert events == []
}

pub fn cursor_and_reaction_windows_do_not_duplicate_messages_test() {
  let message = post(id(10), "1", "hello", [])
  let #(events, _, _) =
    discord.changes(
      "C1",
      None,
      discord.unseen(),
      [message, message],
      me,
      started(5),
    )
  let assert [_] = events
}

pub fn own_and_bot_messages_test() {
  let bot = schema.Post(..post(id(11), "2", "beep", []), webhook: True)
  let messages = [post(id(10), me, "mine", []), bot]
  let #(events, _, _) =
    discord.changes("C1", None, discord.unseen(), messages, me, started(5))
  let assert [mine, beep] = events
  let mine = input.event(mine, "DiscordMessage", discord.input_type())
  let beep = input.event(beep, "DiscordMessage", discord.input_type())
  assert input.bool(mine, "is_self")
  assert !input.bool(beep, "is_self")
  assert input.bool(input.field(beep, "message"), "webhook")
}

pub fn notices_are_not_messages_test() {
  let notice = schema.Post(..post(id(10), "1", "", []), kind: 18)
  let #(events, _, _) =
    discord.changes("C1", None, discord.unseen(), [notice], me, started(5))
  assert events == []
}

pub fn growing_reactions_are_looked_up_test() {
  let #(_, _, seen) =
    discord.changes(
      "C1",
      None,
      discord.unseen(),
      [post(id(10), "1", "a link", [])],
      me,
      started(5),
    )
  let #(events, lookups, seen) =
    discord.changes(
      "C1",
      None,
      seen,
      [post(id(10), "1", "a link", [book(1)])],
      me,
      started(5),
    )
  assert events == []
  let assert [discord.Lookup(message:, emoji: "📖", before: 0)] = lookups
  let #(events, seen) =
    discord.reactions(seen, message, "📖", 0, [user("2")], me)
  let assert [event] = events
  let reacted = input.event(event, "DiscordReaction", discord.input_type())
  assert input.text(input.field(reacted, "message"), "content") == "a link"
  assert input.text(input.field(reacted, "user"), "id") == "2"
  assert input.text(reacted, "emoji") == "📖"
  // The same user is not reported again.
  let #(events, _) =
    discord.reactions(seen, message, "📖", 1, [user("2"), user("3")], me)
  let assert [event] = events
  let reacted = input.event(event, "DiscordReaction", discord.input_type())
  assert input.text(input.field(reacted, "user"), "id") == "3"
}

pub fn reactions_from_before_any_were_seen_are_quiet_test() {
  let message = discord.Incoming("C1", None, post(id(10), "1", "old", []))
  let #(events, seen) =
    discord.reactions(
      discord.unseen(),
      message,
      "📖",
      2,
      [user("2"), user("3")],
      me,
    )
  assert events == []
  assert dict.get(seen.reacted, id(10)) |> option.from_result != None
}

pub fn custom_emoji_preserve_the_native_id_test() {
  let message = discord.Incoming("C1", None, post(id(10), "1", "hi", []))
  let #(events, _) =
    discord.reactions(
      discord.unseen(),
      message,
      "party:123",
      0,
      [user("2")],
      me,
    )
  let assert [event] = events
  let reacted = input.event(event, "DiscordReaction", discord.input_type())
  assert input.text(reacted, "emoji") == "party:123"
}

pub fn thread_names_test() {
  assert discord.thread_name("  first line\nsecond") == "first line"
  assert discord.thread_name("") == "Conversation"
}

pub fn snowflake_times_test() {
  assert discord.sent_at("175928847299117063") == 1_462_015_105_796
}
