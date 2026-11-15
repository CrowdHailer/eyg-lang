//// Per-connection dashboard. The terminal summary and browser controls share
//// the same model; native controls preserve keyboard and screen-reader access.

import cloud/access
import cloud/api
import cloud/beam/file_system
import cloud/box
import cloud/box/check
import cloud/box/transaction as tx
import cloud/catalog
import cloud/templates
import etui/buffer
import etui/geometry
import etui/style
import eyg/interpreter/cast
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import lustre
import lustre/attribute as a
import lustre/element/html as h
import lustre/event
import lustre/server_component
import multiformats/cid/v1

pub opaque type Model {
  Model(
    service: api.Service,
    token: String,
    authenticated: Bool,
    section: String,
    names: List(String),
    selected: String,
    fields: dict.Dict(String, String),
    files: List(String),
    root: String,
    draft: List(tx.Change),
    status: String,
  )
}

pub type Message {
  Field(String, String)
  Navigate(String)
  Login
  Select(String)
  Create
  Open(String)
  Stage
  Commit
  Refresh
  Webhook
  Cron
  RunCron
  TestWebhook
  Issue
  Revoke
  Fork
  Connect
  Channel
}

pub fn app() {
  lustre.simple(
    fn(service) {
      Model(
        service,
        "",
        False,
        "Welcome",
        [],
        "",
        dict.from_list([
          #("template", "webhook-inbox"),
          #("cron", "* * * * *"),
          #("job", "heartbeat"),
          #("payload", "hello from the dashboard"),
          #(
            "grant",
            "(request) -> { !string_starts_with(request.path, \"/data/\") }",
          ),
        ]),
        [],
        "",
        [],
        "Connect with the administrator token to manage boxes.",
      )
    },
    update,
    view,
  )
}

fn field(model: Model, key) {
  dict.get(model.fields, key) |> result.unwrap("")
}

fn set(model: Model, key, value) {
  Model(..model, fields: dict.insert(model.fields, key, value))
}

fn admin(model: Model) {
  access.authorize(model.service.access, model.token, "", "admin", "/")
}

fn refresh(model: Model) {
  case catalog.get(model.service.catalog, model.selected) {
    Error(_) -> Model(..model, names: catalog.names(model.service.catalog))
    Ok(owner) -> {
      let snapshot = box.inspect(owner)
      Model(
        ..model,
        names: catalog.names(model.service.catalog),
        root: v1.to_string(snapshot.files.root),
        files: check.paths(snapshot.files, "") |> result.unwrap([]),
      )
    }
  }
}

fn outcome(model: Model, outcome: Result(String, String)) {
  case outcome {
    Ok(message) -> refresh(Model(..model, status: message))
    Error(reason) -> Model(..model, status: reason)
  }
}

fn update(model: Model, message: Message) {
  case message {
    Field(key, value) -> set(model, key, value)
    Navigate(section) -> Model(..model, section:)
    Login -> {
      let model = Model(..model, token: field(model, "token"))
      case admin(model) {
        True ->
          refresh(
            Model(
              ..set(model, "token", ""),
              authenticated: True,
              section: "Boxes",
              status: "Connected",
            ),
          )
        False -> Model(..model, status: "Invalid administrator token")
      }
    }
    _ ->
      case admin(model) {
        False ->
          Model(
            ..model,
            authenticated: False,
            status: "Connect before managing a box",
          )
        True -> act(model, message)
      }
  }
}

fn act(model: Model, message: Message) {
  case message {
    Channel -> {
      let workspace = string.lowercase(field(model, "workspace"))
      let channel = string.lowercase(field(model, "channel"))
      case catalog.valid_name(workspace) && catalog.valid_name(channel) {
        False -> Model(..model, status: "Enter workspace/guild and channel IDs")
        True -> {
          let platform = case field(model, "platform") {
            "discord" -> "discord"
            _ -> "slack"
          }
          let key = platform <> "-" <> workspace <> "-" <> channel
          let scope = "/" <> platform <> "/channel/" <> channel
          let policy_path = "/system/channel-policy-" <> key <> ".eyg"
          commit(model, [
            tx.MakeDirectory(scope),
            tx.MakeDirectory("/app/skills"),
            tx.MakeDirectory("/system/connections"),
            templates.file(policy_path, templates.channel_policy(scope)),
            templates.file(
              "/system/connections/" <> key <> ".eyg",
              "{mode: \"agent\", policy: import \"" <> policy_path <> "\"}",
            ),
          ])
        }
      }
    }
    Connect -> {
      let connected = {
        use owner <- result.try(catalog.get(
          model.service.catalog,
          model.selected,
        ))
        box.connect(
          owner,
          "/system/connection.eyg",
          access.token_id(model.token),
          field(model, "command"),
          model.service.agent,
        )
      }
      outcome(model, connected)
    }
    Select(name) ->
      refresh(Model(..model, selected: name, draft: [], status: "Box selected"))
    Create -> {
      let name = field(model, "name")
      let created = {
        use template <- result.try(
          templates.get(field(model, "template"))
          |> result.replace_error("Choose a template"),
        )
        use _ <- result.map(catalog.create(
          model.service.catalog,
          name,
          template.files,
        ))
        "Created " <> name
      }
      outcome(Model(..model, selected: name), created)
    }
    Open(path) -> {
      let loaded = {
        use owner <- result.try(catalog.get(
          model.service.catalog,
          model.selected,
        ))
        use bytes <- result.try(file_system.read(
          box.inspect(owner).files,
          path,
          0,
          1_048_576,
        ))
        bit_array.to_string(bytes)
        |> result.replace_error("Binary file: use the API to download")
      }
      case loaded {
        Ok(text) -> model |> set("path", path) |> set("content", text)
        Error(error) -> Model(..model, status: error)
      }
    }
    Stage ->
      case file_system.resolve_path(field(model, "path")) {
        Error(error) -> Model(..model, status: error)
        Ok(path) ->
          Model(
            ..model,
            draft: list.append(
              list.filter(model.draft, fn(change) { tx.path(change) != path }),
              [templates.file(path, field(model, "content"))],
            ),
            status: "Staged " <> path,
          )
      }
    Commit -> commit(model, model.draft)
    Refresh -> refresh(model)
    Webhook ->
      commit(model, [
        templates.file(
          "/app/webhook.eyg",
          "(request) -> { let _ = perform AppendFile({path: \"/data/webhooks.ndjson\", contents: !binary_concat(request.body, !string_to_binary(\"\\n\"))}) {status: 200, headers: [], body: !string_to_binary(\"Webhook accepted\")} }",
        ),
        templates.file(
          "/system/http.eyg",
          templates.http("import \"/app/webhook.eyg\""),
        ),
      ])
    Cron ->
      case catalog.valid_name(field(model, "job")) {
        False -> Model(..model, status: "Use a simple lowercase cron name")
        True ->
          commit(model, [
            templates.file(
              "/system/cron/" <> field(model, "job") <> ".eyg",
              templates.cron(
                field(model, "cron"),
                "(_) -> { let _ = perform AppendFile({path: \"/data/cron.log\", contents: !string_to_binary(\"cron fired\\n\")}) {} }",
              ),
            ),
          ])
      }
    RunCron ->
      invoke(model, "/system/cron/" <> field(model, "job") <> ".eyg", v.unit())
    TestWebhook ->
      invoke(
        model,
        "/system/http.eyg",
        v.Record(
          dict.from_list([
            #("method", v.String("POST")),
            #("path", v.String("/hook")),
            #("headers", v.LinkedList([])),
            #("body", v.Binary(bit_array.from_string(field(model, "payload")))),
          ]),
        ),
      )
    Issue -> {
      let result =
        access.issue(
          model.service.access,
          model.token,
          model.selected,
          field(model, "grant"),
        )
      case result {
        Ok(token) ->
          set(
            Model(
              ..model,
              status: "Token created. Copy it now; only its hash is persisted.",
            ),
            "issued",
            token <> "\nID: " <> access.token_id(token),
          )
        Error(reason) -> Model(..model, status: reason)
      }
    }
    Revoke ->
      outcome(
        model,
        access.revoke(model.service.access, model.token, field(model, "revoke"))
          |> result.replace("Token revoked"),
      )
    Fork -> {
      let forked = {
        use #(root, _) <- result.try(
          v1.from_string(model.root)
          |> result.replace_error("Select a snapshot"),
        )
        use _ <- result.map(catalog.fork(
          model.service.catalog,
          field(model, "fork"),
          model.selected,
          root,
        ))
        "Fork created"
      }
      outcome(model, forked)
    }
    _ -> model
  }
}

fn commit(model: Model, changes) {
  let committed = {
    use owner <- result.try(catalog.get(model.service.catalog, model.selected))
    use #(base, _) <- result.try(
      v1.from_string(model.root) |> result.replace_error("Select a box"),
    )
    use root <- result.map(
      box.commit(owner, base, changes, fn(_) { admin(model) })
      |> result.map_error(string.inspect),
    )
    "Committed " <> v1.to_string(root)
  }
  case committed {
    Ok(_) -> outcome(Model(..model, draft: []), committed)
    Error(_) -> outcome(model, committed)
  }
}

fn invoke(model: Model, path, input) {
  let called = {
    use owner <- result.try(catalog.get(model.service.catalog, model.selected))
    use value <- result.map(box.invoke(owner, path, input))
    case cast.field("body", cast.as_binary, value) {
      Ok(bytes) ->
        bit_array.to_string(bytes) |> result.unwrap(simple_debug.inspect(value))
      Error(_) -> simple_debug.inspect(value)
    }
  }
  outcome(model, called)
}

fn input(model, key, label) {
  h.label([], [
    h.text(label),
    h.input([
      a.name(key),
      a.value(field(model, key)),
      a.attribute("aria-label", label),
    ]),
  ])
}

fn textarea(model, key, label) {
  h.label([], [
    h.text(label),
    h.textarea(
      [
        a.name(key),
        a.value(field(model, key)),
        a.attribute("aria-label", label),
        a.rows(12),
        a.spellcheck(False),
      ],
      field(model, key),
    ),
  ])
}

fn button(label, message) {
  h.button([event.on_click(message)], [h.text(label)])
}

fn section(title, children) {
  h.section([], [h.h2([], [h.text(title)]), ..children])
}

fn view(model: Model) {
  h.main(
    [
      a.id("cloud-tui"),
      event.on("change", {
        use name <- decode.subfield(["target", "name"], decode.string)
        use value <- decode.subfield(["target", "value"], decode.string)
        decode.success(Field(name, value))
      })
        |> server_component.include(["target.name", "target.value"]),
    ],
    [
      terminal(model),
      h.nav(
        [a.attribute("aria-label", "Main navigation")],
        list.map(
          ["Boxes", "Files", "Automation", "Tokens", "Shell / agent"],
          fn(name) { button(name, Navigate(name)) },
        )
          |> list.append([
            h.a([a.href("/docs/concepts")], [h.text("Concepts")]),
            h.a([a.href("/docs/api")], [h.text("API reference")]),
            h.a([a.href("/docs/getting-started")], [h.text("Getting started")]),
            h.a([a.href("/docs/templates")], [h.text("20 templates")]),
          ]),
      ),
      h.p([a.attribute("role", "status"), a.id("status")], [
        h.text(model.status),
      ]),
      case model.authenticated {
        False ->
          section("Connect", [
            h.p([], [
              h.text(
                "Use the token configured as EYG_CLOUD_TOKEN on your server.",
              ),
            ]),
            h.label([], [
              h.text("Administrator token"),
              h.input([
                a.name("token"),
                a.type_("password"),
                a.attribute("aria-label", "Administrator token"),
              ]),
            ]),
            button("Connect", Login),
          ])
        True ->
          h.div([], [
            h.aside([], [
              h.h2([], [h.text("Your boxes")]),
              ..list.map(model.names, fn(name) { button(name, Select(name)) })
            ]),
            case model.section {
              "Shell / agent" ->
                section("Connect to the box", [
                  h.p([], [
                    h.text(
                      "/system/connection.eyg selects shell or agent mode and its effect policy. Agent mode uses the server's configured model; trajectories are saved beneath /traces/sessions.",
                    ),
                  ]),
                  textarea(model, "command", "Code or agent message"),
                  button("Send to connection", Connect),
                ])
              "Files" ->
                section("Files and transactions", [
                  button("Refresh root", Refresh),
                  h.div(
                    [a.class("file-list")],
                    list.map(model.files, fn(path) { button(path, Open(path)) }),
                  ),
                  input(model, "path", "File path"),
                  textarea(model, "content", "File contents"),
                  button("Stage file", Stage),
                  h.p([], [
                    h.text(
                      "Staged: "
                      <> string.join(list.map(model.draft, tx.path), ", "),
                    ),
                  ]),
                  button("Commit batch", Commit),
                  input(model, "fork", "Fork name"),
                  button("Fork current snapshot", Fork),
                ])
              "Automation" ->
                section("Webhook and cron", [
                  h.p([], [
                    h.text(
                      "Install a webhook that appends received bodies to /data/webhooks.ndjson. This replaces the HTTP entry point.",
                    ),
                  ]),
                  button("Install webhook", Webhook),
                  h.p([], [h.text("POST /app/" <> model.selected <> "/hook")]),
                  input(model, "payload", "Webhook payload"),
                  button("Send test webhook", TestWebhook),
                  input(model, "job", "Cron name"),
                  input(model, "cron", "Cron expression (UTC)"),
                  button("Install cron", Cron),
                  button("Run cron now", RunCron),
                  h.h3([], [h.text("Channel agent")]),
                  h.label([], [
                    h.text("Platform"),
                    h.select([a.name("platform")], [
                      h.option([a.value("slack")], "Slack"),
                      h.option([a.value("discord")], "Discord"),
                    ]),
                  ]),
                  input(model, "workspace", "Workspace or guild ID"),
                  input(model, "channel", "Channel ID"),
                  button("Install channel agent", Channel),
                  h.p([], [
                    h.text(
                      "The agent can write only its channel workspace and read /app/skills/. Configure bot credentials on the server to activate the transport.",
                    ),
                  ]),
                  h.p([], [
                    h.text(
                      "Cron writes /data/cron.log. Inspect Files to see output and /traces for execution records. Refresh root after scheduled writes before editing.",
                    ),
                  ]),
                ])
              "Tokens" ->
                section("Account token policies", [
                  h.p([], [
                    h.text(
                      "Tokens are bound to the selected box. These policies live outside its filesystem.",
                    ),
                  ]),
                  textarea(model, "grant", "Token policy (EYG)"),
                  button("Issue token", Issue),
                  h.pre([], [h.text(field(model, "issued"))]),
                  input(model, "revoke", "Token ID to revoke"),
                  button("Revoke token", Revoke),
                ])
              _ ->
                section("Create a box", [
                  input(model, "name", "Box name"),
                  h.label([], [
                    h.text("Initial filesystem"),
                    h.select(
                      [
                        a.name("template"),
                        a.attribute("aria-label", "Initial filesystem"),
                      ],
                      list.map(templates.all(), fn(template) {
                        h.option(
                          [
                            a.value(template.id),
                            a.selected(field(model, "template") == template.id),
                          ],
                          template.title,
                        )
                      }),
                    ),
                  ]),
                  button("Create box", Create),
                  h.div(
                    [],
                    list.map(templates.all(), fn(template) {
                      h.p([], [
                        h.strong([], [h.text(template.title <> ": ")]),
                        h.text(template.description),
                      ])
                    }),
                  ),
                ])
            },
          ])
      },
    ],
  )
}

fn terminal(model: Model) {
  let rows = [
    " EYG CLOUD / a versioned computer",
    " ────────────────────────────────────────────────────────────────────────────────────────────────",
    " BOX      "
      <> case model.selected {
      "" -> "No box selected"
      name -> name
    },
    " ROOT     " <> model.root,
    " FILES    " <> int.to_string(list.length(model.files)),
    " DRAFT    " <> int.to_string(list.length(model.draft)) <> " changes",
    " VIEW     "
      <> model.section
      <> "     |     Tab: navigate controls     Enter: activate",
  ]
  let screen =
    list.index_fold(
      rows,
      buffer.buffer_new(geometry.rect_new(0, 0, 100, 7)),
      fn(screen, row, y) {
        buffer.set_string(
          screen,
          geometry.Position(0, y),
          row,
          style.default_style(),
        )
      },
    )
  h.pre(
    [a.class("terminal"), a.attribute("aria-label", "Box terminal summary")],
    list.repeat(Nil, 7)
      |> list.index_map(fn(_, y) {
        h.text(
          list.repeat(Nil, 100)
          |> list.index_map(fn(_, x) {
            buffer.get_cell(screen, geometry.Position(x, y))
            |> buffer.cell_symbol
          })
          |> string.join("")
          |> string.append("\n"),
        )
      }),
  )
}
