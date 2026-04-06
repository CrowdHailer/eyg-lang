import gleam/list
import gleam/option.{None, Some}
import gleam/uri.{Uri}
import lustre/attribute as a
import lustre/element/html as h
import mysig/html
import mysig/preview

// These are all parts of the layout, I prefer composing helpers than having a single layout to call
pub fn full_path(path) {
  Uri(Some("https"), None, Some("eyg.run"), None, path, None, None)
}

pub fn page_meta(path path, title title, description description) {
  list.append(
    preview.page(
      site: "The EYG homepage",
      title: title,
      description: description,
      canonical: full_path(path),
    ),
    preview.optimum_image(
      full_path("/share.png"),
      preview.png,
      "Penelopea the mascot for the EYG programming language.",
    ),
  )
}

pub fn diagnostics() {
  [
    h.script(
      [
        a.src(
          "https://js-de.sentry-cdn.com/02395cbfda3bca6b1c19224f411d0b03.min.js",
        ),
        a.attribute("crossorigin", "anonymous"),
      ],
      "",
    ),
    html.plausible("eyg.run"),
  ]
}

pub fn prism_style() {
  html.stylesheet(
    "https://cdnjs.cloudflare.com/ajax/libs/prism/9000.0.1/themes/prism.min.css",
  )
}
