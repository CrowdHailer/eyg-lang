---
name: triggers
description: How to run a script automatically when a message, reaction or connection event (GitHub, Bluesky, feeds, Hacker News, Lobsters) reaches this channel.
---

A trigger runs an EYG script when its pattern matches an event in this channel.
The pattern is a pure function from the event to `True({})` or `False({})`, it cannot perform effects.
Events are tagged, match on the tag:

- `ChatPosted(message)` and `ChatReacted({message, emoji, by})` for the example chat.
- `SlackMessage({message, ...})` and `SlackReaction({message, reaction, ...})` for Slack.
- `DiscordMessage({message, ...})` and `DiscordReaction({message, emoji, ...})` for Discord.
- `WhatsAppMessage({message, referenced})` retains native content tags: `Text`, `Reaction`, `Button`, `Interactive`, `Media` or `Other`.

Payloads keep the platform's native fields. Discord uses Unicode such as `📚` or `name:id`; Slack uses reaction names such as `books`.
- `GitHubIssue`, `GitHubComment`, `GitHubPullRequest`, `GitHubPush`, `GitHubStar`, `GitHubRelease`, `GitHubWorkflowRun`,
  each with `repository`, `actor`, `url`, issues and pull requests also have `action`, `number`, `title` and `body`
- `BskyPost({account, author, text, url, likes, ..})`
- `FeedItem({feed, title, link, summary, published})`
- `HackerNewsStory({list, title, url, link, by, score})` and `LobstersStory({title, url, link, tags, score})`

The script is a function of the same event, it runs with this channel's shell. Posts from the script go to the thread
of a chat message, or to the channel for other events. `match` with a catch all `| (_) -> { ... }` for events you ignore.

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

```eyg
perform AddTrigger({
  name: "bug-reports",
  pattern: match {
    GitHubIssue(issue) -> { !equal(issue.action, "opened") }
    | (_) -> { False({}) }
  },
  script: match {
    GitHubIssue(issue) -> { perform Post(!string_append("New issue: ", issue.url)) }
    | (_) -> { Ok("") }
  }
})
```

A script can hand work to a subagent with `perform Delegate("task description")`,
and read the logged events of a connection with `perform Events("github")`, newest first.
Use `ListTriggers({})`, `StopTrigger(name)`, `StartTrigger(name)` and `DeleteTrigger(name)` to manage them.
