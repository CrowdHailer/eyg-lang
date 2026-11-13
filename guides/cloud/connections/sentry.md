---
name: Sentry connection
description: Run triggers on Sentry issues, alerts and errors with a Sentry internal integration.
---

# Sentry

A `Sentry` connection receives the webhooks of a Sentry internal integration and reports issues, alerts and errors
to its channel's triggers.

```eyg
let sentry = match perform Secret("SENTRY_CLIENT_SECRET") {
  Ok(secret) -> { [{name: "sentry", source: Sentry({secret}), channel: "ops"}] }
  Error(_) -> { [] }
}
```

## Setup

1. In Sentry, open Settings, Custom Integrations (Developer Settings), and create a new internal integration.
2. Set the webhook URL to `<CLOUD_ORIGIN>/connections/sentry/webhook`. It must be reachable from the internet, use a tunnel when developing.
3. Give the integration read permission for issues and events, turn on "Alert Rule Action", and under Webhooks choose `issue` and `error`.
4. Save, copy the integration's client secret and store it with `perform SetSecret({name: "SENTRY_CLIENT_SECRET", value})`.
5. To be notified by alert rules, choose the integration in an alert rule's actions, for issue alerts and metric alerts.

Every delivery is signed with the client secret in `Sentry-Hook-Signature`, the connection rejects others with `401`.
The kind of delivery is `Sentry-Hook-Resource`.

## Events

| Resource | Event |
| --- | --- |
| `issue` | `SentryIssue({connection, action, id, short_id, title, culprit, level, status, project, url})` |
| `event_alert` | `SentryAlert({connection, kind: "event_alert", action, rule, title, level, url})` |
| `metric_alert` | `SentryAlert({connection, kind: "metric_alert", action, rule, title, level, url})` |
| `error` | `SentryError({connection, action, title, level, culprit, url, issue_url})` |
| anything else | `SentryEvent({connection, resource, action})` |

`SentryIssue.action` is `created`, `resolved`, `assigned`, `ignored`, `archived` or `unresolved`.
A metric alert's `action` and `level` are its status, `critical`, `warning` or `resolved`.
Missing fields are empty strings.

## Example triggers

Ask an agent to look at each new issue:

```eyg
{
  name: "new-issues",
  pattern: cloud.triggers.sentry_issue("created"),
  script: match {
    SentryIssue(issue) -> {
      let task = !string_append("A new Sentry issue. Read the stack trace at the url and suggest the likely cause in one message: ",
        !string_append(issue.title, !string_append(" ", issue.url)))
      perform Delegate(task)
    }
    | (_) -> { Error("not an issue") }
  }
}
```

Post when an alert fires, `sentry_alert` ignores resolved metric alerts:

```eyg
{
  name: "alerts",
  pattern: cloud.triggers.sentry_alert,
  script: match {
    SentryAlert(alert) -> { perform Post(!string_append("🚨 ", !string_append(alert.title, !string_append(" ", alert.url)))) }
    | (_) -> { Error("not an alert") }
  }
}
```

## Without Sentry

The errors a Sentry SDK reports can also be sent straight to a [webhook](./webhooks.md) from your own error handler,
see [errors and logs as triggers](../errors_and_logs.md).
