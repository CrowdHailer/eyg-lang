//// Complete, checked starter filesystems. Each template is installed in one batch.

import cloud/box/transaction as tx
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/string

pub type Template {
  Template(
    id: String,
    title: String,
    description: String,
    files: List(tx.Change),
  )
}

pub const policy =
  "let pass = (input) -> { Pass(input) }
let writable = (path, input) -> {
  match !string_starts_with(path, \"/data/\") {
    True(_) -> { Pass(input) }
    False(_) -> { Mock(Error(\"Only /data/ is writable\")) }
  }
}
{
  append_file: (input) -> { writable(input.path, input) },
  cwd: pass, delete_file: (path) -> { writable(path, path) },
  env: pass, fetch: pass, flip: pass,
  make_directory: (path) -> { writable(path, path) },
  now: pass, random: pass, read_directory: pass, read_file: pass,
  sleep: pass, standard_error: pass, standard_out: pass,
  write_file: (input) -> { writable(input.path, input) }
}"

pub fn file(path, text) {
  tx.Put(path, bit_array.from_string(text))
}

fn quote(text) {
  json.string(text) |> json.to_string
}

pub fn response(text) {
  "{status: 200, headers: [], body: !string_to_binary(" <> text <> ")}"
}

fn constant(text) {
  "(_) -> { " <> response(quote(text)) <> " }"
}

fn receive(path, message) {
  "(request) -> { let _ = perform AppendFile({path: "
  <> quote(path)
  <> ", contents: !binary_concat(request.body, !string_to_binary(\"\\n\"))}) "
  <> response(quote(message))
  <> " }"
}

fn stored(path) {
  "(_) -> { let body = match perform ReadFile({path: "
  <> quote(path)
  <> ", offset: 0, limit: 1048576}) { Ok(bytes) -> { bytes } Error(_) -> { !string_to_binary(\"No entries yet\") } } {status: 200, headers: [], body} }"
}

pub fn http(handler) {
  "{handler: " <> handler <> ", policy: import \"/system/policy.eyg\"}"
}

pub fn cron(expression, handler) {
  "{cron: "
  <> quote(expression)
  <> ", handler: "
  <> handler
  <> ", policy: import \"/system/policy.eyg\"}"
}

fn starter(id, title, description, handler, files) {
  // A lambda after a let-binding needs its own binding: otherwise the parser
  // reads the opening parenthesis as an application of the preceding value.
  let handler = case string.contains(handler, "\n(") {
    True -> string.replace(handler, "\n(", "\nlet endpoint = (") <> "\nendpoint"
    False -> handler
  }
  Template(
    id,
    title,
    description,
    list.append(
      [
        tx.MakeDirectory("/system/cron"),
        tx.MakeDirectory("/app"),
        tx.MakeDirectory("/data"),
        tx.MakeDirectory("/skills"),
        file("/system/policy.eyg", policy),
        file(
          "/system/connection.eyg",
          "{mode: \"shell\", policy: import \"/system/policy.eyg\"}",
        ),
        file("/system/http.eyg", http("import \"/app/handler.eyg\"")),
        file("/app/handler.eyg", handler),
        file(
          "/README.md",
          "# "
            <> title
            <> "\n\n"
            <> description
            <> "\n\nThe HTTP entry point is /system/http.eyg. Mutable data lives in /data.\nEdit related files together in one transaction. See /docs/getting-started on the dashboard.\n",
        ),
        file(
          "/skills/entry.md",
          "Read README.md before changing the application. Write runtime data only beneath /data/. Check errors returned by effects.\n",
        ),
      ],
      files,
    ),
  )
}

pub fn all() {
  [
    starter(
      "webhook-inbox",
      "Webhook inbox",
      "POST arbitrary event bodies to the public URL. Events append to /data/events.ndjson for later processing.",
      receive("/data/events.ndjson", "Event accepted"),
      [],
    ),
    starter(
      "cron-heartbeat",
      "Cron heartbeat",
      "A UTC cron appends a heartbeat every minute. GET the public URL to inspect the log.",
      stored("/data/heartbeats.txt"),
      [
        file(
          "/system/cron/heartbeat.eyg",
          cron(
            "* * * * *",
            "(_) -> { let _ = perform AppendFile({path: \"/data/heartbeats.txt\", contents: !string_to_binary(\"heartbeat\\n\")}) {} }",
          ),
        ),
      ],
    ),
    starter(
      "contact-form",
      "Contact form receiver",
      "Accept contact submissions by POST; other methods describe the endpoint. Messages are kept separately from application code.",
      "let submit = "
        <> receive("/data/messages.txt", "Thank you for your message")
        <> "\n(request) -> { match !binary_compare(!string_to_binary(request.method), !string_to_binary(\"POST\")) { Eq(_) -> { submit(request) } | (_) -> { "
        <> response(quote("POST your message to this URL"))
        <> " } } }",
      [],
    ),
    starter(
      "static-site",
      "Static website",
      "Serve a versioned HTML page imported as bytes. Replacing index.html atomically updates the site.",
      "let page = import \"/app/index.html\"\n(_) -> { {status: 200, headers: [{name: \"content-type\", value: \"text/html; charset=utf-8\"}], body: page} }",
      [
        file(
          "/app/index.html",
          "<!doctype html><title>My EYG site</title><h1>Hello from a versioned computer</h1>",
        ),
      ],
    ),
    starter(
      "redirect",
      "URL redirect",
      "A short-link service whose destination is a checked EYG value.",
      "let destination = import \"/app/destination.eyg\"\n(_) -> { {status: 302, headers: [{name: \"location\", value: destination}], body: !string_to_binary(\"Redirecting\")} }",
      [file("/app/destination.eyg", "\"https://eyg.run\"")],
    ),
    starter(
      "feature-flags",
      "Feature flag endpoint",
      "Publish a JSON feature-flag document. Consumers read the public endpoint; edits are versioned with the application.",
      "let flags = import \"/app/flags.json\"\n(_) -> { {status: 200, headers: [{name: \"content-type\", value: \"application/json\"}], body: flags} }",
      [file("/app/flags.json", "{\"new_checkout\":false,\"search\":true}")],
    ),
    starter(
      "request-inspector",
      "Request inspector",
      "Return the received HTTP method and path. Useful for checking proxy routing and webhook delivery paths.",
      "(request) -> { "
        <> response(
        "!string_append(request.method, !string_append(\" \", request.path))",
      )
        <> " }",
      [],
    ),
    starter(
      "echo",
      "Binary echo service",
      "Return the exact received bytes, including non-UTF-8 payloads. Useful for testing clients and transport integrity.",
      "(request) -> { {status: 200, headers: [], body: request.body} }",
      [],
    ),
    starter(
      "upper-case",
      "Text transformation",
      "Transform UTF-8 request bodies to uppercase. Invalid UTF-8 gets a readable response.",
      "(request) -> { let text = match !string_from_binary(request.body) { Ok(text) -> { !string_uppercase(text) } Error(_) -> { \"Expected UTF-8\" } } "
        <> response("text")
        <> " }",
      [],
    ),
    starter(
      "pricing",
      "Pricing calculator",
      "POST an integer quantity to calculate a quote from a checked unit-price dependency.",
      "let price = import \"/app/unit-price.eyg\"\n(request) -> { let quote = match !string_from_binary(request.body) { Ok(text) -> { match !int_parse(text) { Ok(quantity) -> { !int_to_string(!int_multiply(quantity, price)) } Error(_) -> { \"Expected an integer quantity\" } } } Error(_) -> { \"Expected UTF-8\" } } "
        <> response("quote")
        <> " }",
      [file("/app/unit-price.eyg", "25")],
    ),
    starter(
      "audit-log",
      "Append-only audit receiver",
      "Collect externally produced audit entries. The application can append data but cannot change policy or code.",
      receive("/data/audit.ndjson", "Audit entry recorded"),
      [],
    ),
    starter(
      "status-page",
      "Status page",
      "Serve an operational status message from mutable data. Update /data/status.txt through the authenticated filesystem API.",
      stored("/data/status.txt"),
      [file("/data/status.txt", "All systems operational\n")],
    ),
    starter(
      "rss-feed",
      "RSS feed",
      "Publish a content-addressed RSS document from a filesystem asset.",
      "let feed = import \"/app/feed.xml\"\n(_) -> { {status: 200, headers: [{name: \"content-type\", value: \"application/rss+xml\"}], body: feed} }",
      [
        file(
          "/app/feed.xml",
          "<?xml version=\"1.0\"?><rss version=\"2.0\"><channel><title>Box updates</title><link>https://eyg.run</link><description>Versioned news</description></channel></rss>",
        ),
      ],
    ),
    starter(
      "csv-export",
      "CSV download",
      "Publish a downloadable CSV report. The data and serving configuration travel together in snapshots.",
      "let csv = import \"/app/report.csv\"\n(_) -> { {status: 200, headers: [{name: \"content-type\", value: \"text/csv\"}, {name: \"content-disposition\", value: \"attachment; filename=report.csv\"}], body: csv} }",
      [file("/app/report.csv", "product,quantity\napples,12\npears,7\n")],
    ),
    starter(
      "daily-digest",
      "Daily digest",
      "At 09:00 UTC, copy the inbox into a latest-digest file. GET returns the latest digest.",
      stored("/data/digest.txt"),
      [
        file("/data/inbox.txt", "Team updates go here.\n"),
        file(
          "/system/cron/digest.eyg",
          cron(
            "0 9 * * *",
            "(_) -> { let _ = match perform ReadFile({path: \"/data/inbox.txt\", offset: 0, limit: 1048576}) { Ok(contents) -> { perform WriteFile({path: \"/data/digest.txt\", contents}) } Error(reason) -> { Error(reason) } } {} }",
          ),
        ),
      ],
    ),
    starter(
      "daily-reset",
      "Daily workspace reset",
      "Reset a mutable work queue at midnight UTC. Useful for daily exercises and disposable sandboxes.",
      stored("/data/queue.txt"),
      [
        file("/data/queue.txt", "Today's work\n"),
        file(
          "/system/cron/reset.eyg",
          cron(
            "0 0 * * *",
            "(_) -> { let _ = perform WriteFile({path: \"/data/queue.txt\", contents: !string_to_binary(\"\")}) {} }",
          ),
        ),
      ],
    ),
    starter(
      "asset-registry",
      "Asset registry",
      "Pattern-import binary assets and return their count. Adding assets changes the checked registry automatically.",
      "let assets = import \"/app/assets/:{asset}.txt\"\n(_) -> { let count = !list_fold(assets, 0, (_, count) -> { !int_add(count, 1) }) "
        <> response("!int_to_string(count)")
        <> " }",
      [
        tx.MakeDirectory("/app/assets"),
        file("/app/assets/first.txt", "First asset"),
      ],
    ),
    starter(
      "translation-catalog",
      "Translation catalog",
      "Select a greeting by URL path from a checked record. Edit translations without changing the handler.",
      "let messages = import \"/app/messages.eyg\"\n(request) -> { let message = match !binary_compare(!string_to_binary(request.path), !string_to_binary(\"/es\")) { Eq(_) -> { messages.es } | (_) -> { messages.en } } "
        <> response("message")
        <> " }",
      [file("/app/messages.eyg", "{en: \"Hello\", es: \"Hola\"}")],
    ),
    starter(
      "health-check",
      "Health check",
      "A small independent liveness endpoint. Fork this box to provision isolated checks for different environments.",
      constant("healthy\n"),
      [],
    ),
    starter(
      "agent-notebook",
      "Agent notebook",
      "A writable notebook with skills instructions. Connect an external agent using an account-issued policy restricted to /data/.",
      stored("/data/notebook.md"),
      [
        file("/data/notebook.md", "# Notebook\n\nRecord findings here.\n"),
        file(
          "/skills/research.md",
          "Read existing notes before adding findings. Include source links. Keep facts separate from hypotheses.\n",
        ),
      ],
    ),
  ]
}

pub fn get(id) {
  all() |> list.find(fn(template) { template.id == id })
}
