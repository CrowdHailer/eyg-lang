---
name: Errors and logs as triggers
description: Act on Sentry reports and server logs with triggers, why not to copy everything into one database, how Lakebase fits, and owning the endpoint your errors go to.
---

# Errors and logs as triggers

Errors and logs are streams of events. A cloud workspace can act on each one as it arrives,
with a trigger, instead of storing everything and querying it later.
This page answers four questions:

1. Can Sentry reports or server logs, every 404 for example, run triggers?
2. How do you act on them without copying everything into one database?
3. Is one database for everything sensible, and is that what Lakebase is?
4. Is an endpoint you own for error events a way off a platform?

## 1. Sentry and logs run triggers

**Sentry.** A [Sentry connection](./connections/sentry.md) receives the webhooks of a Sentry internal integration.
New issues, issue state changes, alert rules and errors become `SentryIssue`, `SentryAlert` and `SentryError` events.

```eyg
{
  name: "new-issues",
  pattern: cloud.triggers.sentry_issue("created"),
  script: match {
    SentryIssue(issue) -> { perform Delegate(!string_append("Suggest a likely cause for this new issue: ", issue.url)) }
    | (_) -> { Error("not an issue") }
  }
}
```

**Logs.** A [webhook connection](./connections/webhooks.md) with `split: True({})` takes the JSON batches a log drain posts
and makes each line an event. Vercel and Netlify log drains post JSON, other hosts can forward their logs with a log shipper such as Vector.
Heroku's HTTPS drains post syslog text, which arrives as `body` with no `fields`.
`field_equals("status", "404")` matches every 404:

```eyg
{name: "logs", source: Webhook({secret: logs_secret, split: True({})}), channel: "ops"}
```

The [example workspace](../../examples/cloud/workspace.eyg) posts every 5xx line in #dev.
A pattern sees one event at a time, so it is cheap: lines that match nothing cost a pure function call and are dropped,
apart from the connection's log of the latest 500 events.

## 2. Act on the stream, keep what you need

The usual architecture copies everything, every log line and every error, into one store and runs queries on a schedule.
Triggers turn that around. Each event is looked at once, as it arrives, and only what a trigger decides to keep is stored.

| Need | Where it lives |
| --- | --- |
| React now: page someone, open an issue, ask an agent | A trigger, nothing stored |
| Recent context: "has this happened in the last hour?" | The connection's event log, read with `Events` |
| Durable facts: first seen, counts, who is on call | A small named [database](./dataclips.md), written by the trigger |
| Everything, for audits and debugging | The system that already keeps it: your log store, Sentry, the host's logs |
| Questions other channels ask | A [dataclip](./dataclips.md) over the small database, or one that fetches from the log store's API |

A trigger that posts only the first time an error is seen, and counts repeats, needs one table:

```eyg
let sql = (statement, parameters) -> {
  perform SQLite({database: "errors", sql: statement, parameters})
}

{
  name: "first-seen",
  pattern: cloud.triggers.sentry_issue("created"),
  script: match {
    SentryIssue(issue) -> {
      let _ = sql("CREATE TABLE IF NOT EXISTS seen (title TEXT PRIMARY KEY, count INTEGER)", [])
      match sql("INSERT INTO seen VALUES (?, 1) ON CONFLICT (title) DO UPDATE SET count = count + 1 RETURNING count", [Text(issue.title)]) {
        Ok(rows) -> {
          match !equal(rows, [[Integer(1)]]) {
            True(_) -> { perform Post(!string_append("New error: ", issue.title)) }
            False(_) -> { Ok("seen before") }
          }
        }
        Error(reason) -> { Error(reason) }
      }
    }
    | (_) -> { Error("not an issue") }
  }
}
```

The channel running it needs `shell.with_databases(["errors"], shell.everything)`, other channels read it through a dataclip.

The data that is not copied is not lost, it stays where it already is.
A dataclip can fetch from a log store's query API when someone asks, with the store's token in a network secret,
so the question is answered from the source rather than from a copy. This is federation: data stays with the system that owns it,
and queries go to it.

## 3. One database for everything?

One database for everything has real advantages: joins across all data, one backup, one place to look.
It also has costs that grow with the data:

- **Access is all or nothing.** Most databases grant access per database or per table. Logs contain tokens, emails and IP addresses.
  Putting them next to everything else widens who can read them. Named databases on the cloud are granted one by one, and dataclips grant less than a database.
- **Volume dominates.** Logs and error events outnumber business data by orders of magnitude.
  Storing them in an operational database makes every backup, migration and index pay for data that is rarely read.
- **Coupling.** One schema shared by every team and tool is hard to change. Small databases owned by one trigger or one channel are easy to change and to delete.
- **Retention differs.** Logs are kept for days, invoices for years. One store needs per table rules for both.

For a workspace the trade-off favours several small databases, each written by the triggers that own it,
with dataclips as the shared interface and large streams left in the systems built for them.

### Lakebase

Lakebase is Databricks' managed Postgres, announced in 2025 after Databricks acquired Neon.
It is an operational, transactional database that runs inside the Databricks platform
and syncs tables with the lakehouse, the Delta tables in object storage that Databricks queries for analytics,
under the same governance (Unity Catalog).

So Lakebase is not one database for everything. It is two kinds of store, an operational database and an analytical lakehouse,
kept in sync and governed together, so applications and analytics see the same data without hand written pipelines.
That is the "one platform" answer: many stores, one vendor, one catalogue.
The approach on this page is the "small pieces" answer: act on events as they arrive, keep small databases per purpose,
and leave the rest where it lives. They solve different sizes of problem. A team with a lakehouse full of data gets value from Lakebase,
a team that wants to react to the next 404 does not need a lakehouse.

## 4. Owning the error endpoint

Error tracking platforms are, at their core, an endpoint that accepts error events, and a product built on what arrives:
grouping, stack trace symbolication, source maps, release tracking, dashboards and alerting.

Owning the endpoint is a way off a platform, in steps:

1. **Add, do not replace.** Keep Sentry and connect it with the Sentry connection. Triggers now own the alerting,
   in EYG that you can read and test, rather than in alert rules in a vendor's UI.
2. **Send errors to your own endpoint too.** Your application's error handler posts a small JSON body to a webhook connection,
   alongside the platform SDK.

   ```js
   window.addEventListener("error", (event) => {
     fetch("https://cloud.example.com/connections/errors/webhook?token=...", {
       method: "POST",
       body: JSON.stringify({message: event.message, source: event.filename, line: event.lineno, release: RELEASE}),
       keepalive: true,
     })
   })
   ```

   Every field you choose to send becomes a field patterns can match. You decide what is collected, which matters for personal data.
3. **Move the product you use.** Grouping can be a trigger that keys errors by message and source in a small database, as in the first seen example.
   Dashboards can be an artifact built from a dataclip.
4. **Drop the platform** when what you still use from it is covered. Often that is never, symbolication and source maps are hard,
   and the platform remains the store of record while your endpoint and triggers own the decisions.

The endpoint is the part that cannot be moved later without changing every application, so it is the part worth owning first.
Sentry SDKs can also send their own envelopes to any server that speaks Sentry's protocol, there are compatible open source servers.
The cloud's webhook connection does not parse Sentry envelopes, it takes plain JSON, so with a Sentry SDK keep using the Sentry connection.

## See also

- [Webhooks](./connections/webhooks.md), [Sentry](./connections/sentry.md), [databases and dataclips](./dataclips.md)
- [Trigger events](./trigger_events.md), every event a trigger can see
