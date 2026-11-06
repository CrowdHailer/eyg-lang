//// Pages and sockets for the browser.
////
//// There is no authentication: this is served on the local machine only.

import cloud/fs
import cloud/sessions.{type Sessions}
import cloud/web/script
import cloud/web/sidebar as session_list
import cloud/web/style
import cloud/web/terminal
import gleam/http/response
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import howdy/controller.{type Controller}
import howdy/form
import howdy/ui/live
import howdy/ui/page
import howdy/ui/sidebar
import lustre/attribute
import lustre/element/html
import multiformats/cid/v1
import simplifile

pub fn controller(registry: Sessions) -> Controller {
  controller.new("/")
  |> controller.get("/", fn(ctx) {
    let session = sessions.create(registry)
    redirect(ctx, "/sessions/" <> session.id)
  })
  |> controller.get("/sessions/:id", fn(ctx) {
    let assert Ok(id) = controller.param(ctx, "id")
    case sessions.get(registry, id) {
      Ok(session) -> session_page(session) |> page.respond(ctx)
      Error(Nil) -> not_found(ctx)
    }
  })
  |> controller.post("/sessions/:id/fork", fn(ctx) {
    let assert Ok(id) = controller.param(ctx, "id")
    use fields <- form.read(ctx)
    let step = case form.get(fields, "step") {
      Ok(step) -> int.parse(step)
      Error(Nil) -> Error(Nil)
    }
    case step {
      Ok(step) ->
        case sessions.fork(registry, id, step) {
          Ok(fork) -> redirect(ctx, "/sessions/" <> fork.id)
          Error(Nil) -> not_found(ctx)
        }
      Error(Nil) -> controller.status(ctx, 400)
    }
  })
  |> controller.post("/uploads", fn(ctx) { upload(ctx, registry) })
  |> controller.get("/live/terminal/:id", fn(ctx) {
    let assert Ok(id) = controller.param(ctx, "id")
    case sessions.get(registry, id) {
      Ok(session) -> live.serve(ctx, terminal.app(), with: #(registry, session))
      Error(Nil) -> not_found(ctx)
    }
  })
  |> controller.get("/live/sessions/:id", fn(ctx) {
    let assert Ok(id) = controller.param(ctx, "id")
    live.serve(ctx, session_list.app(), with: #(registry, id))
  })
  |> controller.build
}

fn session_page(session: sessions.Session) {
  let id = session.id
  page.new(sessions.title(session) <> " · EYG cloud")
  |> page.live
  |> page.head([
    html.style([], style.css),
    html.script([attribute.type_("module")], script.script),
  ])
  |> page.body([
    sidebar.layout(
      collapsed: False,
      attributes: [],
      sidebar: sidebar.sidebar("sessions", [], [
        sidebar.header([
          html.a([attribute.href("/"), attribute.class("brand")], [
            html.text("EYG cloud"),
          ]),
        ]),
        sidebar.content([
          html.a([attribute.href("/"), attribute.class("new-session")], [
            html.text("+ New session"),
          ]),
          live.mount("/live/sessions/" <> id),
        ]),
      ]),
      main: [
        html.div([attribute.class("mobile-bar")], [
          html.button(
            [
              attribute.type_("button"),
              attribute.aria_label("Show sessions"),
              ..sidebar.trigger("sessions")
            ],
            [html.text("☰")],
          ),
          html.span([], [html.text("EYG cloud")]),
        ]),
        live.mount("/live/terminal/" <> id),
      ],
    ),
  ])
}

/// Write uploaded files into the block store as one directory, keeping the
/// relative path sent with each file, and answer with its CID. The upload
/// is not part of any session until it is mounted.
fn upload(ctx, registry) {
  let limits =
    form.limits()
    |> form.accept_files(max_files: 10_000, max_file_size: 50_000_000)
    |> form.max_total_file_size(500_000_000)
  use fields <- form.read_with(ctx, limits)
  let store = sessions.store(registry)
  let files = list.zip(form.all(fields, "path"), form.all_files(fields, "file"))
  let written =
    list.try_fold(files, fs.empty(store), fn(root, file) {
      let #(path, uploaded) = file
      let path = case fs.segments(path) {
        [] -> uploaded.file_name
        _ -> path
      }
      use contents <- result.try(
        simplifile.read_bits(uploaded.path)
        |> result.replace_error("could not read " <> path),
      )
      fs.write_file(store, root, path, contents)
    })
  case files, written {
    [], _ -> problem(ctx, "no files")
    _, Ok(root) ->
      controller.json(
        ctx,
        json.object([#("upload", json.string(v1.to_string(root)))]),
      )
    _, Error(reason) -> problem(ctx, reason)
  }
}

fn problem(ctx, reason) {
  controller.json(ctx, json.object([#("error", json.string(reason))]))
  |> controller.with_status(400)
}

fn redirect(ctx, location) {
  controller.status(ctx, 303)
  |> response.set_header("location", location)
}

fn not_found(ctx) {
  controller.text(ctx, "session not found")
  |> controller.with_status(404)
}
