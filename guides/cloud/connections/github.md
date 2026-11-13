---
name: GitHub connection
description: Run triggers on issues, pull requests, pushes, stars and CI runs of GitHub repositories.
---

# GitHub

A GitHub connection reports the activity of repositories to a channel's triggers.
GitHub is not a chat: issue bodies and comments never run as code, they arrive as event values.

```eyg
let github = match perform Secret("GITHUB_WEBHOOK_SECRET") {
  Ok(secret) -> { GitHub({repositories: ["owner/repo"], secret, every: 60}) }
  Error(_) -> { GitHub({repositories: ["owner/repo"], every: 60}) }
}

{
  connections: [{name: "github", source: github, channel: "dev"}],
  ..
}
```

## Polling or webhooks

**Polling** reads the public [events API](https://docs.github.com/en/rest/activity/events) of each repository every `every` seconds.
It needs no setup, but GitHub limits unauthenticated clients to 60 requests an hour, delays events by up to five minutes
and leaves out push commits and CI runs. Set `every: 0` to only use webhooks.

**Webhooks** deliver events as they happen. In the repository's settings add a webhook with

- Payload URL `https://<CLOUD_ORIGIN>/connections/<name>/webhook`, here `/connections/github/webhook`
- Content type `application/json`
- Secret, the same value saved in the workspace's store as `GITHUB_WEBHOOK_SECRET`
- The events your triggers use: issues, issue comments, pull requests, pushes, stars, releases, workflow runs

Deliveries without a valid `X-Hub-Signature-256` are rejected, and a connection without a secret accepts none.
The sample deliveries in [`examples/cloud/webhooks`](../../../examples/cloud/webhooks) can be sent with curl to try triggers locally.

## Example triggers

The [example workspace](../../../examples/cloud/workspace.eyg) installs these in `#dev`.

| Trigger | Pattern | Script |
| --- | --- | --- |
| `triage-issues` | `cloud.triggers.issue_opened` | Delegates to a subagent that posts a summary and a suggested label |
| `merged` | `cloud.triggers.pull_request_merged` | Posts the title, author and link |
| `stars` | `GitHubStar` | Thanks the stargazer |
| `ci-failed` | `GitHubWorkflowRun` with `conclusion` `failure` on `main` | Posts the run's link |

A pattern for comments that mention a word:

```eyg
match {
  GitHubComment(comment) -> {
    match !string_split_once(comment.body, "regression") {
      Ok(_) -> { True({}) }
      Error(_) -> { False({}) }
    }
  }
  | (_) -> { False({}) }
}
```

Agents can install the same triggers with `AddTrigger` when someone asks in the channel.
Every event's fields are listed in [trigger events](../trigger_events.md#github).
