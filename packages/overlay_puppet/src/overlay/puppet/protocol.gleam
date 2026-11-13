//// JSON protocol shared with overlay/web/puppet, without executing artifact code in the host.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/json
import overlay/web/puppet as p

pub type Request {
  Request(locator: List(p.Step), action: p.Action, timeout: Int)
}

pub fn message(raw: Dynamic) {
  decode.run(raw, {
    use id <- decode.field("id", decode.string)
    use request <- decode.field("request", {
      use locator <- decode.field("locator", decode.list(step()))
      use action <- decode.field("action", action())
      use timeout <- decode.field("timeout", decode.int)
      decode.success(Request(locator:, action:, timeout:))
    })
    decode.success(#(id, request))
  })
}

fn string_value(constructor) {
  decode.field("value", decode.string, fn(value) {
    decode.success(constructor(value))
  })
}

fn step() {
  use tag <- decode.field("type", decode.string)
  case tag {
    "css" -> string_value(p.ByCss)
    "text" -> string_value(p.ByText)
    "label" -> string_value(p.ByLabel)
    "placeholder" -> string_value(p.ByPlaceholder)
    "test_id" -> string_value(p.ByTestId)
    "has_text" -> string_value(p.HasText)
    "nth" ->
      decode.field("value", decode.int, fn(n) { decode.success(p.Nth(n)) })
    "role" -> {
      use role <- decode.field("role", decode.string)
      use name <- decode.field("name", decode.string)
      decode.success(p.ByRole(role, name))
    }
    _ -> decode.failure(p.ByCss(""), "locator step")
  }
}

fn condition() {
  use tag <- decode.field("type", decode.string)
  case tag {
    "to_have_text" -> string_value(p.ToHaveText)
    "to_contain_text" -> string_value(p.ToContainText)
    "to_have_count" ->
      decode.field("value", decode.int, fn(n) {
        decode.success(p.ToHaveCount(n))
      })
    "to_be_visible" -> decode.success(p.ToBeVisible)
    "to_be_hidden" -> decode.success(p.ToBeHidden)
    "to_have_value" -> string_value(p.ToHaveValue)
    "to_have_attribute" -> {
      use name <- decode.field("name", decode.string)
      use value <- decode.field("value", decode.string)
      decode.success(p.ToHaveAttribute(name, value))
    }
    "to_be_checked" ->
      decode.field("value", decode.bool, fn(flag) {
        decode.success(p.ToBeChecked(flag))
      })
    _ -> decode.failure(p.ToBeVisible, "expectation")
  }
}

fn action() {
  use tag <- decode.field("type", decode.string)
  case tag {
    "click" -> decode.success(p.Click)
    "fill" -> string_value(p.Fill)
    "press" -> string_value(p.Press)
    "set_checked" ->
      decode.field("value", decode.bool, fn(flag) {
        decode.success(p.SetChecked(flag))
      })
    "select_option" -> string_value(p.SelectOption)
    "hover" -> decode.success(p.Hover)
    "focus" -> decode.success(p.Focus)
    "scroll_into_view" -> decode.success(p.ScrollIntoView)
    "text_content" -> decode.success(p.TextContent)
    "inner_text" -> decode.success(p.InnerText)
    "inner_html" -> decode.success(p.InnerHtml)
    "input_value" -> decode.success(p.InputValue)
    "get_attribute" -> string_value(p.GetAttribute)
    "count" -> decode.success(p.Count)
    "all_text_contents" -> decode.success(p.AllTextContents)
    "is_visible" -> decode.success(p.IsVisible)
    "is_checked" -> decode.success(p.IsChecked)
    "is_enabled" -> decode.success(p.IsEnabled)
    "expect" ->
      decode.field("condition", condition(), fn(c) {
        decode.success(p.Expect(c))
      })
    "screenshot" -> decode.success(p.Screenshot)
    _ -> decode.failure(p.Click, "action")
  }
}

pub fn tagged(tag, fields) {
  json.object([#("type", json.string(tag)), ..fields])
}

pub fn done() {
  tagged("done", [])
}

pub fn text(value) {
  tagged("text", [#("value", json.string(value))])
}

pub fn flag(value) {
  tagged("flag", [#("value", json.bool(value))])
}

pub fn failure(reason) {
  tagged("error", [#("value", json.string(reason))])
}
