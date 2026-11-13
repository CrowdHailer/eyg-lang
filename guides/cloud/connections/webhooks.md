---
name: Webhook connection
description: Turn any HTTP request, from a log drain, an error tracker, a form or a deploy hook, into trigger events.
---

# Webhooks

A `Webhook` connection gives a workspace a URL. Every request to it is a `WebhookRequest` event for the triggers of its channel,
so anything that can call a URL can run triggers: log drains, error trackers, deploy hooks, forms, monitoring and other clouds.

```eyg
{
  name: "logs",
  source: Webhook({secret: logs_secret, split: True({})}),
  channel: "ops"
}
```

The URL is `<CLOUD_ORIGIN>/connections/logs/webhook`. Paths under it are accepted too,
`/connections/logs/webhook/vercel` arrives with `path` set to `/vercel`, so one connection can serve several senders.
Every method is accepted.

| Field | |
| --- | --- |
| `secret` | Optional. When set, a request must carry it, see [authentication](#authentication) |
| `split` | Optional, `False({})` by default. A JSON array body becomes one event per element |
| `respond` | Optional. A pure function from the request to `{status, body}`, the reply |

## Events

```text
WebhookRequest({connection, method, path, query, headers, body, fields})
```

Patterns are pure, they cannot decode JSON with `DecodeJSON`, so the body is also given as `fields`:
a `{path, value}` pair, as text, for every string, number, boolean and null in a JSON body.
`{"status": 404, "request": {"path": "/x"}}` has the fields `request.path` `/x` and `status` `404`, array elements are numbered, `lines.0.status`.
Scripts can decode `body` with the [json package](../../../eyg_packages/json/) for anything else.

`cloud.triggers` has patterns for requests:

```eyg
// Every 404 a log drain sends.
{
  name: "not-found",
  pattern: cloud.triggers.field_equals("status", "404"),
  script: match {
    WebhookRequest(request) -> {
      match cloud.triggers.field(request, "path") {
        Ok(path) -> { perform Post(!string_append("404 for ", path)) }
        Error(_) -> { perform Post("404") }
      }
    }
    | (_) -> { Error("not a request") }
  }
}
```

`webhook_path("/deploys")` matches requests to one path. `field(request, path)` reads a field in patterns and scripts.

## Batches

Log drains send many lines in one request. With `split: True({})` a JSON array body is one event per element,
so a trigger runs for each line and `field_equals("status", "404")` matches every 404 in the batch, not the batch.
Each element's event has that element, as JSON, for its `body`. A body that is not an array is one event.

## Authentication

Without a secret anyone who knows the URL can send events. Patterns and the channel's shell still decide what runs,
but set a secret for anything public. With one, a request is accepted when it has any of:

- a `sha256=<hex>` HMAC-SHA256 of the body, keyed by the secret, in `X-Hub-Signature-256` or `X-Signature-256`, as GitHub and many others send;
- `Authorization: Bearer <secret>`;
- a `token=<secret>` query parameter, for senders that only let you set a URL.

Other requests are answered `401`. The `Authorization`, `Cookie` and any header named like a signature, token, secret or key,
and the `token` query parameter, are not in events, so programs and the connection's event log never see the secret.

## Responding

A request is answered `200 accepted` before triggers run. A `respond` function answers instead,
for senders that verify the URL or expect a body, such as a challenge to echo:

```eyg
respond: (request) -> {
  match cloud.triggers.field(request, "challenge") {
    Ok(challenge) -> { {status: 200, body: challenge} }
    Error(_) -> { {status: 202, body: "accepted"} }
  }
}
```

`respond` is pure, like a pattern, it cannot perform effects, and it sees the whole request before it is split.
It runs for authenticated requests only.

## Tracing and the event log

Every event is kept in the connection's log, the latest 500, and programs read it with `Events("logs")`.
Triggers that run for a request are traced like other triggers, see [tracing](../tracing.md).

## Specific senders

GitHub and Sentry have their own connections, which verify their signatures and give typed events,
see [GitHub](./github.md) and [Sentry](./sentry.md). A `Webhook` works for them too when typed events are not needed.
