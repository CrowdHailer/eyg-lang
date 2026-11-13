//// Locators resolve within the preview document. Strict actions reject ambiguous matches.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import overlay/web/puppet as p
import plinthx/browser/node as dom
import plinthx/javascript/object

pub fn normalize(text: String) -> String {
  text
  |> string.to_graphemes
  |> list.map(fn(char) {
    case char {
      "\t"
      | "\n"
      | "\r"
      | "\u{000b}"
      | "\u{000c}"
      | "\u{0085}"
      | "\u{00a0}"
      | "\u{2028}"
      | "\u{2029}" -> " "
      _ -> char
    }
  })
  |> string.concat
  |> string.split(" ")
  |> list.filter(fn(part) { part != "" })
  |> string.join(" ")
}

pub fn includes(text, part) {
  string.contains(
    string.lowercase(normalize(text)),
    string.lowercase(normalize(part)),
  )
}

fn attr(element, name) {
  dom.attribute(element, name) |> result.unwrap("")
}

pub fn label(element) {
  dom.labels(element)
  |> list.map(dom.text(_, "textContent"))
  |> string.join(" ")
}

pub fn name(element) {
  case attr(element, "aria-labelledby") {
    "" -> {
      let button = case dom.text(element, "tagName"), attr(element, "type") {
        "INPUT", "button" | "INPUT", "submit" | "INPUT", "reset" ->
          dom.value(element) |> result.unwrap("")
        _, _ -> ""
      }
      [
        attr(element, "aria-label"),
        label(element),
        attr(element, "alt"),
        attr(element, "title"),
        button,
        dom.text(element, "textContent"),
        attr(element, "placeholder"),
      ]
      |> list.find(fn(text) { text != "" })
      |> result.unwrap("")
    }
    ids ->
      normalize(ids)
      |> string.split(" ")
      |> list.map(fn(id) {
        dom.by_id(id)
        |> result.map(dom.text(_, "textContent"))
        |> result.unwrap("")
      })
      |> string.join(" ")
  }
}

pub fn visible(element) {
  let #(_, _, width, height) = dom.rect(element)
  dom.flag(element, "isConnected")
  && dom.check_visibility(element)
  && width >. 0.0
  && height >. 0.0
}

fn implicit_role(role) {
  case role {
    "button" ->
      "button,input[type=button],input[type=submit],input[type=reset],summary"
    "link" -> "a[href]"
    "heading" -> "h1,h2,h3,h4,h5,h6"
    "textbox" ->
      "input:not([type]),input[type=text],input[type=email],input[type=search],input[type=url],input[type=tel],input[type=password],input[type=number],textarea"
    "checkbox" -> "input[type=checkbox]"
    "radio" -> "input[type=radio]"
    "combobox" -> "select"
    "slider" -> "input[type=range]"
    "option" -> "option"
    "list" -> "ul,ol"
    "listitem" -> "li"
    "img" -> "img[alt],svg[role=img]"
    "table" -> "table"
    "row" -> "tr"
    "cell" -> "td"
    "columnheader" -> "th"
    "navigation" -> "nav"
    "main" -> "main"
    "article" -> "article"
    "region" -> "section[aria-label],section[aria-labelledby]"
    "dialog" -> "dialog"
    "form" -> "form"
    _ -> ""
  }
}

fn query(roots, selector) {
  use groups <- result.try(list.try_map(roots, dom.query(_, selector)))
  Ok(list.flatten(groups))
}

pub fn resolve(locator: List(p.Step)) {
  use nodes <- result.try(narrow(locator, [dom.document()]))
  Ok(list.filter(nodes, fn(node) { !object.is_same(node, dom.document()) }))
}

fn narrow(steps, roots) {
  case steps {
    [] -> Ok(roots)
    [step, ..rest] -> {
      use nodes <- result.try(case step {
        p.ByCss(selector) -> query(roots, selector)
        p.ByText(text) -> {
          use nodes <- result.try(query(roots, "*"))
          let matching =
            list.filter(nodes, fn(node) {
              !list.contains(
                ["SCRIPT", "STYLE", "TEMPLATE"],
                dom.text(node, "tagName"),
              )
              && includes(dom.text(node, "textContent"), text)
            })
          Ok(
            list.filter(matching, fn(node) {
              !list.any(matching, fn(other) {
                !object.is_same(node, other) && dom.contains(node, other)
              })
            }),
          )
        }
        p.ByRole(role:, name: wanted) -> {
          let implicit = implicit_role(role)
          let selector =
            "[role=\""
            <> dom.escape_css(role)
            <> "\"]"
            <> case implicit {
              "" -> ""
              _ -> "," <> implicit
            }
          use nodes <- result.try(query(roots, selector))
          Ok(
            list.filter(nodes, fn(node) {
              wanted == "" || includes(name(node), wanted)
            }),
          )
        }
        p.ByLabel(text) -> {
          use nodes <- result.try(query(
            roots,
            "input,textarea,select,button,[aria-label]",
          ))
          Ok(
            list.filter(nodes, fn(node) {
              let text_ = case attr(node, "aria-label") {
                "" -> label(node)
                other -> other
              }
              includes(text_, text)
            }),
          )
        }
        p.ByPlaceholder(text) -> {
          use nodes <- result.try(query(roots, "[placeholder]"))
          Ok(
            list.filter(nodes, fn(node) {
              includes(attr(node, "placeholder"), text)
            }),
          )
        }
        p.ByTestId(id) ->
          query(roots, "[data-testid=\"" <> dom.escape_css(id) <> "\"]")
        p.HasText(text) ->
          Ok(
            list.filter(roots, fn(node) {
              includes(dom.text(node, "textContent"), text)
            }),
          )
        p.Nth(index) -> {
          let index = case index < 0 {
            True -> list.length(roots) + index
            False -> index
          }
          Ok(
            case
              case index < 0 {
                True -> Error(Nil)
                False -> list.first(list.drop(roots, index))
              }
            {
              Ok(node) -> [node]
              Error(_) -> []
            },
          )
        }
      })
      narrow(rest, deduplicate(nodes, []))
    }
  }
}

fn deduplicate(nodes, found) {
  case nodes {
    [] -> list.reverse(found)
    [node, ..rest] ->
      case list.any(found, object.is_same(_, node)) {
        True -> deduplicate(rest, found)
        False -> deduplicate(rest, [node, ..found])
      }
  }
}

pub fn describe(steps) {
  case steps {
    [] -> "page"
    _ ->
      list.map(steps, fn(step) {
        case step {
          p.ByCss(value) -> "css=" <> value
          p.ByText(value) -> "text=" <> value
          p.ByRole(role, name) -> "role=" <> role <> "[name=" <> name <> "]"
          p.ByLabel(value) -> "label=" <> value
          p.ByPlaceholder(value) -> "placeholder=" <> value
          p.ByTestId(value) -> "test_id=" <> value
          p.HasText(value) -> "has_text=" <> value
          p.Nth(value) -> "nth=" <> int.to_string(value)
        }
      })
      |> string.join(" >> ")
  }
}
