import cloud/api
import cloud/box/transaction as tx
import cloud/templates
import gleam/bit_array
import gleam/list
import gleam/result
import howdy/controller
import howdy/ui/page
import lustre/attribute as a
import lustre/element/html as h
import simplifile

pub fn controller() {
  controller.new("/docs")
  |> controller.get("/:topic", fn(ctx) {
    let topic = api.param(ctx, "topic")
    case topic {
      "templates" ->
        document(
          ctx,
          "20 starter filesystems",
          list.map(templates.all(), fn(template) {
            h.details([], [
              h.summary([], [h.text(template.title)]),
              h.p([], [h.text(template.description)]),
              h.p([], [h.text("Template ID: " <> template.id)]),
              ..list.map(template.files, fn(change) {
                case change {
                  tx.Put(path, bytes) ->
                    h.details([], [
                      h.summary([], [h.text(path)]),
                      h.pre([], [
                        h.text(
                          bit_array.to_string(bytes)
                          |> result.unwrap("Binary asset"),
                        ),
                      ]),
                    ])
                  _ -> h.p([], [h.text("Directory " <> tx.path(change))])
                }
              })
            ])
          }),
        )
      "concepts" | "api" | "getting-started" -> {
        case simplifile.read("docs/" <> topic <> ".md") {
          Ok(text) -> document(ctx, topic, [h.pre([], [h.text(text)])])
          Error(_) ->
            api.failure(
              ctx,
              500,
              "Documentation is missing from this installation",
            )
        }
      }
      _ -> api.failure(ctx, 404, "Unknown documentation page")
    }
  })
  |> controller.build
}

fn document(ctx, title, children) {
  page.new("EYG Cloud — " <> title)
  |> page.head([
    h.style(
      [],
      "body{background:#111923;color:#d5e4f1;font:16px/1.6 monospace}main{max-width:1000px;margin:auto;padding:2rem}a{color:#81c9ff;margin-right:1rem}pre{white-space:pre-wrap;overflow-wrap:anywhere}details{border:1px solid #345468;padding:1rem;margin:1rem 0}summary{cursor:pointer;color:#81e6bd}",
    ),
  ])
  |> page.body([
    h.main([], [
      h.nav([], [
        h.a([a.href("/")], [h.text("← Dashboard")]),
        h.a([a.href("/docs/concepts")], [h.text("Concepts")]),
        h.a([a.href("/docs/api")], [h.text("API reference")]),
        h.a([a.href("/docs/getting-started")], [h.text("Getting started")]),
        h.a([a.href("/docs/templates")], [h.text("Templates")]),
      ]),
      h.h1([], [h.text(title)]),
      ..children
    ]),
  ])
  |> page.respond(ctx)
}
