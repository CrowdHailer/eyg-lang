//// Rewrite the start tags of an HTML document, copying everything else through.
////
//// The document is text throughout, nothing in it is parsed by a browser here.

import gleam/list
import gleam/option.{type Option}
import gleam/result.{try}
import gleam/string
import html_parser.{
  type Element, Attribute, Content, EmptyElement, EndElement, StartElement,
}

/// Call `update` with each start tag, the contents of a script or style
/// element are its only child. `None` removes the tag, only use it for void
/// elements as their end tag is removed. An error stops the rewrite.
///
/// Declarations, such as the doctype, are removed.
pub fn rewrite(
  source: String,
  update: fn(Element) -> Result(Option(Element), String),
) -> Result(String, String) {
  do_rewrite(source, update, [])
}

fn do_rewrite(source, update, acc) {
  // html_parser drops whitespace before an element, keep it.
  let #(space, source) = split_space(source, "")
  let acc = [space, ..acc]
  case source {
    "" -> Ok(string.concat(list.reverse(acc)))
    "<!--" <> rest -> {
      let #(comment, rest) =
        string.split_once(rest, "-->") |> result.unwrap(#(rest, ""))
      do_rewrite(rest, update, ["<!--" <> comment <> "-->", ..acc])
    }
    "<!" <> rest | "<?" <> rest -> {
      let #(_, rest) =
        string.split_once(rest, ">") |> result.unwrap(#(rest, ""))
      do_rewrite(rest, update, acc)
    }
    _ -> {
      let #(element, rest) = html_parser.get_first_element(source)
      use text <- try(case element {
        StartElement(..) -> {
          use updated <- try(update(element))
          Ok(option.map(updated, render) |> option.unwrap(""))
        }
        _ -> Ok(render(element))
      })
      do_rewrite(rest, update, [text, ..acc])
    }
  }
}

fn split_space(source, space) {
  case source {
    " " <> rest -> split_space(rest, space <> " ")
    "\n" <> rest -> split_space(rest, space <> "\n")
    "\t" <> rest -> split_space(rest, space <> "\t")
    "\r" <> rest -> split_space(rest, space <> "\r")
    _ -> #(space, source)
  }
}

fn render(element: Element) -> String {
  case element {
    StartElement(name, attributes, children) ->
      "<"
      <> name
      <> string.concat(
        list.map(attributes, fn(attribute) {
          let Attribute(key, value) = attribute
          " " <> key <> "=\"" <> string.replace(value, "\"", "&quot;") <> "\""
        }),
      )
      <> ">"
      <> string.concat(list.map(children, render))
    EndElement(name) ->
      case is_void(name) {
        True -> ""
        False -> "</" <> name <> ">"
      }
    Content(text) -> text
    EmptyElement -> ""
  }
}

fn is_void(name) {
  list.contains(
    [
      "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
      "source", "track", "wbr",
    ],
    string.lowercase(name),
  )
}

/// The value of an attribute, names are not case sensitive.
pub fn attribute(element: Element, name: String) -> Result(String, Nil) {
  case element {
    StartElement(attributes:, ..) ->
      list.find_map(attributes, fn(attribute) {
        case string.lowercase(attribute.key) == name {
          True -> Ok(attribute.value)
          False -> Error(Nil)
        }
      })
    _ -> Error(Nil)
  }
}

/// Replace the value of an existing attribute.
pub fn set_attribute(element: Element, name: String, value: String) -> Element {
  case element {
    StartElement(attributes:, ..) -> {
      let attributes =
        list.map(attributes, fn(attribute) {
          case string.lowercase(attribute.key) == name {
            True -> Attribute(attribute.key, value)
            False -> attribute
          }
        })
      StartElement(..element, attributes:)
    }
    _ -> element
  }
}

pub fn remove_attribute(element: Element, name: String) -> Element {
  case element {
    StartElement(attributes:, ..) -> {
      let attributes =
        list.filter(attributes, fn(attribute) {
          string.lowercase(attribute.key) != name
        })
      StartElement(..element, attributes:)
    }
    _ -> element
  }
}

/// The lowercase tag name of a start or end tag.
pub fn name(element: Element) -> String {
  case element {
    StartElement(name:, ..) | EndElement(name) -> string.lowercase(name)
    _ -> ""
  }
}
