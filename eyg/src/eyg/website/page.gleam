import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/uri
import lustre/element
import midas/task as t
import mysig/asset
import mysig/html
import mysig/layout
import mysig/neo
import mysig/preview

pub fn app(title, module, func, bundle) {
  use script <- t.do(t.bundle(module, func))
  use script <- t.do(asset.resource(asset.js("page", script), bundle))
  layout(title, [html.empty_lustre(), script], bundle)
}

fn layout(title, body, bundle) {
  let title = case title {
    None -> "EYG"
    Some(title) -> "EYG - " <> title
  }
  use layout <- t.do(asset.resource(layout.css, bundle))
  use neo <- t.do(asset.resource(neo.css, bundle))
  html.doc(
    list.flatten([
      [
        html.stylesheet(asset.tailwind_2_2_11),
        layout,
        neo,
        html.plausible("eyg.run"),
      ],
      preview.homepage(
        title: title,
        description: "EYG is a programming language for predictable, useful and most of all confident development.",
        canonical: uri.Uri(
          Some("https"),
          None,
          Some("eyg.run"),
          None,
          "/",
          None,
          None,
        ),
      ),
      preview.optimum_image(
        uri.Uri(
          Some("https"),
          None,
          Some("eyg.run"),
          None,
          "/share.png",
          None,
          None,
        ),
        preview.png,
        "Penelopea the mascot for the EYG programming language.",
      ),
    ]),
    body,
  )
  |> element.to_document_string()
  |> bit_array.from_string()
  |> t.done()
}
