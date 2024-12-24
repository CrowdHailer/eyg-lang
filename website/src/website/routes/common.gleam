import gleam/list
import gleam/option.{None, Some}
import gleam/uri.{Uri}
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
