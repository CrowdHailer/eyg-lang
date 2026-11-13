//// The guides of eyg.run served from a local directory.
////
//// Guides are served at the same paths as the website, `/guides/<slug>.md`
//// and `/guides/<slug>`, and listed in `/llms.txt`. Slugs are made from the
//// frontmatter the same way the website makes them.

import filepath
import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type Guide {
  Guide(slug: String, name: String, description: String, body: String)
}

pub type Site {
  Site(guides: List(Guide))
}

/// Every guide with a name and description in a directory.
pub fn load(directory: String) -> Result(Site, String) {
  use names <- result.try(
    simplifile.read_directory(directory)
    |> result.map_error(fn(reason) {
      "unable to list "
      <> directory
      <> ": "
      <> simplifile.describe_error(reason)
    }),
  )
  list.sort(names, string.compare)
  |> list.filter(string.ends_with(_, ".md"))
  |> list.try_map(fn(name) {
    let path = filepath.join(directory, name)
    simplifile.read(path)
    |> result.map_error(fn(reason) {
      "unable to read " <> path <> ": " <> simplifile.describe_error(reason)
    })
  })
  |> result.map(fn(texts) { Site(list.filter_map(texts, parse)) })
}

/// A guide from its markdown, if it has the frontmatter the website needs.
pub fn parse(text: String) -> Result(Guide, Nil) {
  use #(front, body) <- result.try(frontmatter(text))
  use name <- result.try(list.key_find(front, "name"))
  use description <- result.try(list.key_find(front, "description"))
  let slug =
    list.key_find(front, "slug")
    |> result.unwrap(
      name
      |> string.replace(" ", "-")
      |> string.replace("_", "-")
      |> string.lowercase
      |> string.trim,
    )
  Ok(Guide(slug:, name:, description:, body:))
}

fn frontmatter(text) {
  case string.split(text, "\n") {
    ["---", ..rest] -> {
      let #(front, rest) = list.split_while(rest, fn(line) { line != "---" })
      case rest {
        ["---", ..body] -> {
          let fields =
            list.filter_map(front, fn(line) {
              use #(key, value) <- result.map(string.split_once(line, ":"))
              #(string.trim(key), string.trim(value))
            })
          Ok(#(fields, string.join(body, "\n")))
        }
        _ -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

/// Answer a request if it is for a page the site serves.
pub fn handle(
  site: Site,
  request: Request(BitArray),
) -> Result(Response(BitArray), Nil) {
  case request.method, request.path_segments(request) {
    http.Get, ["llms.txt"] -> Ok(text(200, llms(site)))
    http.Get, ["guides", page] -> {
      let slug = case string.ends_with(page, ".md") {
        True -> string.drop_end(page, 3)
        False -> page
      }
      case list.find(site.guides, fn(guide) { guide.slug == slug }) {
        Ok(guide) -> Ok(text(200, guide.body))
        Error(Nil) -> Ok(text(404, "Not found"))
      }
    }
    _, _ -> Error(Nil)
  }
}

fn llms(site: Site) {
  [
    "# Eat Your Greens (EYG)",
    "",
    "> EYG is an immutable functional language with structural typing and managed effects.",
    "",
    "## Guides",
    "",
    ..list.map(site.guides, fn(guide) {
      "- ["
      <> guide.name
      <> "](/guides/"
      <> guide.slug
      <> ".md): "
      <> string.trim(string.replace(guide.description, "\n", " "))
    })
  ]
  |> string.join("\n")
}

fn text(status, body) {
  response.new(status)
  |> response.set_header("content-type", "text/markdown; charset=utf-8")
  |> response.set_body(<<body:utf8>>)
}
