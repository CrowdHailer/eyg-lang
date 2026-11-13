---
name: triggers
description: How to run a script automatically when a message or reaction appears in this channel.
---

A trigger runs an EYG script when its pattern matches an event in this channel.
The pattern is a pure function from the event to `True({})` or `False({})`, it cannot perform effects.
Events are tagged, match on the tag:

- `ChatPosted(message)` and `ChatReacted({message, emoji, by})` for the example chat.
- `SlackMessage({message, ...})` and `SlackReaction({message, reaction, ...})` for Slack.
- `DiscordMessage({message, ...})` and `DiscordReaction({message, emoji, ...})` for Discord.

Payloads keep the platform's native fields. Discord uses Unicode such as `📚` or `name:id`; Slack uses reaction names such as `books`.

The script is a function of the same event, it runs with this channel's shell. Posts from the script go to the thread
of the message. `match` with a catch all `| (_) -> { ... }` for events you ignore.

```eyg
perform AddTrigger({
  name: "thanks",
  pattern: match {
    ChatPosted(message) -> { !string_starts_with(message.text, "thank you") }
    SlackMessage(event) -> { !string_starts_with(event.message.text, "thank you") }
    DiscordMessage(event) -> { !string_starts_with(event.message.content, "thank you") }
    | (_) -> { False({}) }
  },
  script: (_event) -> { perform Post("You're welcome!") }
})
```

A script can hand work to a subagent with `perform Delegate("task description")`.
Use `ListTriggers({})`, `StopTrigger(name)`, `StartTrigger(name)` and `DeleteTrigger(name)` to manage them.
