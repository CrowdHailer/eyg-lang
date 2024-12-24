import gleam/bit_array
import gleam/list
import gleam/option.{None, Some}
import gleam/uri
import lustre/attribute as a
import lustre/element
import lustre/element/html as h
import mysig/asset
import mysig/html
import mysig/layout
import mysig/neo
import mysig/preview

pub fn app(title, module, func, bundle) {
  use client <- asset.do(asset.bundle(module, func))
  layout(
    title,
    [html.empty_lustre(), h.script([a.src(asset.src(client))], "")],
    bundle,
  )
}

fn layout(title, body, bundle) {
  let title = case title {
    None -> "EYG"
    Some(title) -> "EYG - " <> title
  }
  use layout <- asset.do(layout.css())
  use neo <- asset.do(neo.css())
  html.doc(
    list.flatten([
      [
        html.stylesheet(html.tailwind_2_2_11),
        html.stylesheet(asset.src(layout)),
        html.stylesheet(asset.src(neo)),
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
  |> asset.done()
}
