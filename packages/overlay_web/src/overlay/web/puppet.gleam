//// Drive artifacts shown in the workspace, following the Playwright API.
////
//// A program performs `Puppet` with the panel to control, a locator and an action.
//// A puppet script inside the sandboxed preview finds elements and acts on them.
//// The application sends data to the preview and reads data back, it never
//// runs code from the preview, see the artifact control section of
//// guides/overlay_artifacts.md.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/result.{try}
import gleam/string
import overlay/web/artifact
import touch_grass/interface

pub type Step {
  ByCss(String)
  ByText(String)
  ByRole(role: String, name: String)
  ByLabel(String)
  ByPlaceholder(String)
  ByTestId(String)
  HasText(String)
  Nth(Int)
}

pub type Condition {
  ToHaveText(String)
  ToContainText(String)
  ToHaveCount(Int)
  ToBeVisible
  ToBeHidden
  ToHaveValue(String)
  ToHaveAttribute(name: String, value: String)
  ToBeChecked(Bool)
}

pub type Action {
  Click
  Fill(String)
  Press(String)
  SetChecked(Bool)
  SelectOption(String)
  Hover
  Focus
  ScrollIntoView
  TextContent
  InnerText
  InnerHtml
  InputValue
  GetAttribute(String)
  Count
  AllTextContents
  IsVisible
  IsChecked
  IsEnabled
  Expect(Condition)
  Screenshot
}

pub type Request {
  Request(
    page: artifact.Item,
    locator: List(Step),
    action: Action,
    timeout: Int,
  )
}

pub type Reply {
  Done
  Value(String)
  Values(List(String))
  Number(Int)
  Flag(Bool)
  Missing
  Image(BitArray)
}

pub const label = "Puppet"

pub fn effect() -> interface.Interface(Request, a) {
  let string_step = fn(tag) { #(tag, t.String) }
  let step =
    t.union([
      string_step("Css"),
      string_step("Text"),
      #("Role", t.record([#("role", t.String), #("name", t.String)])),
      string_step("Label"),
      string_step("Placeholder"),
      string_step("TestId"),
      string_step("HasText"),
      #("Nth", t.Integer),
    ])
  let condition =
    t.union([
      #("ToHaveText", t.String),
      #("ToContainText", t.String),
      #("ToHaveCount", t.Integer),
      #("ToBeVisible", t.unit),
      #("ToBeHidden", t.unit),
      #("ToHaveValue", t.String),
      #(
        "ToHaveAttribute",
        t.record([#("name", t.String), #("value", t.String)]),
      ),
      #("ToBeChecked", t.boolean),
    ])
  let action =
    t.union([
      #("Click", t.unit),
      #("Fill", t.String),
      #("Press", t.String),
      #("SetChecked", t.boolean),
      #("SelectOption", t.String),
      #("Hover", t.unit),
      #("Focus", t.unit),
      #("ScrollIntoView", t.unit),
      #("TextContent", t.unit),
      #("InnerText", t.unit),
      #("InnerHtml", t.unit),
      #("InputValue", t.unit),
      #("GetAttribute", t.String),
      #("Count", t.unit),
      #("AllTextContents", t.unit),
      #("IsVisible", t.unit),
      #("IsChecked", t.unit),
      #("IsEnabled", t.unit),
      #("Expect", condition),
      #("Screenshot", t.unit),
    ])
  let page =
    t.union([
      #("Artifact", t.String),
      #("Revision", t.record([#("name", t.String), #("version", t.Integer)])),
    ])
  let reply =
    t.union([
      #("Done", t.unit),
      #("Text", t.String),
      #("Texts", t.List(t.String)),
      #("Count", t.Integer),
      #("Flag", t.boolean),
      #("Missing", t.unit),
      #("Image", t.Binary),
    ])
  interface.Interface(
    name: label,
    lift_type: t.record([
      #("page", page),
      #("locator", t.List(step)),
      #("action", action),
      #("timeout", t.Integer),
    ]),
    lower_type: t.result(reply, t.String),
    decode:,
  )
}

fn decode(raw) {
  use page <- try(cast.field("page", decode_page, raw))
  use locator <- try(cast.field("locator", cast.as_list_of(_, decode_step), raw))
  use action <- try(cast.field("action", decode_action, raw))
  use timeout <- try(cast.field("timeout", cast.as_integer, raw))
  Ok(Request(page:, locator:, action:, timeout:))
}

fn decode_page(raw) {
  cast.as_variant(raw, [
    #("Artifact", cast.map(cast.as_string, artifact.Artifact)),
    #("Revision", fn(raw) {
      use name <- try(cast.field("name", cast.as_string, raw))
      use version <- try(cast.field("version", cast.as_integer, raw))
      Ok(artifact.Revision(name, version))
    }),
  ])
}

fn decode_step(raw) {
  cast.as_variant(raw, [
    #("Css", cast.map(cast.as_string, ByCss)),
    #("Text", cast.map(cast.as_string, ByText)),
    #("Role", fn(raw) {
      use role <- try(cast.field("role", cast.as_string, raw))
      use name <- try(cast.field("name", cast.as_string, raw))
      Ok(ByRole(role, name))
    }),
    #("Label", cast.map(cast.as_string, ByLabel)),
    #("Placeholder", cast.map(cast.as_string, ByPlaceholder)),
    #("TestId", cast.map(cast.as_string, ByTestId)),
    #("HasText", cast.map(cast.as_string, HasText)),
    #("Nth", cast.map(cast.as_integer, Nth)),
  ])
}

fn decode_bool(raw) {
  cast.as_variant(raw, [
    #("True", cast.as_unit(_, True)),
    #("False", cast.as_unit(_, False)),
  ])
}

fn decode_condition(raw) {
  cast.as_variant(raw, [
    #("ToHaveText", cast.map(cast.as_string, ToHaveText)),
    #("ToContainText", cast.map(cast.as_string, ToContainText)),
    #("ToHaveCount", cast.map(cast.as_integer, ToHaveCount)),
    #("ToBeVisible", cast.as_unit(_, ToBeVisible)),
    #("ToBeHidden", cast.as_unit(_, ToBeHidden)),
    #("ToHaveValue", cast.map(cast.as_string, ToHaveValue)),
    #("ToHaveAttribute", fn(raw) {
      use name <- try(cast.field("name", cast.as_string, raw))
      use value <- try(cast.field("value", cast.as_string, raw))
      Ok(ToHaveAttribute(name, value))
    }),
    #("ToBeChecked", cast.map(decode_bool, ToBeChecked)),
  ])
}

fn decode_action(raw) {
  cast.as_variant(raw, [
    #("Click", cast.as_unit(_, Click)),
    #("Fill", cast.map(cast.as_string, Fill)),
    #("Press", cast.map(cast.as_string, Press)),
    #("SetChecked", cast.map(decode_bool, SetChecked)),
    #("SelectOption", cast.map(cast.as_string, SelectOption)),
    #("Hover", cast.as_unit(_, Hover)),
    #("Focus", cast.as_unit(_, Focus)),
    #("ScrollIntoView", cast.as_unit(_, ScrollIntoView)),
    #("TextContent", cast.as_unit(_, TextContent)),
    #("InnerText", cast.as_unit(_, InnerText)),
    #("InnerHtml", cast.as_unit(_, InnerHtml)),
    #("InputValue", cast.as_unit(_, InputValue)),
    #("GetAttribute", cast.map(cast.as_string, GetAttribute)),
    #("Count", cast.as_unit(_, Count)),
    #("AllTextContents", cast.as_unit(_, AllTextContents)),
    #("IsVisible", cast.as_unit(_, IsVisible)),
    #("IsChecked", cast.as_unit(_, IsChecked)),
    #("IsEnabled", cast.as_unit(_, IsEnabled)),
    #("Expect", cast.map(decode_condition, Expect)),
    #("Screenshot", cast.as_unit(_, Screenshot)),
  ])
}

/// The request sent to the puppet script in a preview.
pub fn to_json(request: Request) -> Json {
  let Request(locator:, action:, timeout:, ..) = request
  json.object([
    #("locator", json.array(locator, step_to_json)),
    #("action", action_to_json(action)),
    #("timeout", json.int(timeout)),
  ])
}

fn tagged(type_, fields) {
  json.object([#("type", json.string(type_)), ..fields])
}

fn step_to_json(step) {
  case step {
    ByCss(css) -> tagged("css", [#("value", json.string(css))])
    ByText(text) -> tagged("text", [#("value", json.string(text))])
    ByRole(role, name) ->
      tagged("role", [
        #("role", json.string(role)),
        #("name", json.string(name)),
      ])
    ByLabel(text) -> tagged("label", [#("value", json.string(text))])
    ByPlaceholder(text) ->
      tagged("placeholder", [#("value", json.string(text))])
    ByTestId(id) -> tagged("test_id", [#("value", json.string(id))])
    HasText(text) -> tagged("has_text", [#("value", json.string(text))])
    Nth(index) -> tagged("nth", [#("value", json.int(index))])
  }
}

fn condition_to_json(condition) {
  case condition {
    ToHaveText(text) -> tagged("to_have_text", [#("value", json.string(text))])
    ToContainText(text) ->
      tagged("to_contain_text", [#("value", json.string(text))])
    ToHaveCount(count) -> tagged("to_have_count", [#("value", json.int(count))])
    ToBeVisible -> tagged("to_be_visible", [])
    ToBeHidden -> tagged("to_be_hidden", [])
    ToHaveValue(value) ->
      tagged("to_have_value", [#("value", json.string(value))])
    ToHaveAttribute(name, value) ->
      tagged("to_have_attribute", [
        #("name", json.string(name)),
        #("value", json.string(value)),
      ])
    ToBeChecked(checked) ->
      tagged("to_be_checked", [#("value", json.bool(checked))])
  }
}

fn action_to_json(action) {
  case action {
    Click -> tagged("click", [])
    Fill(value) -> tagged("fill", [#("value", json.string(value))])
    Press(key) -> tagged("press", [#("value", json.string(key))])
    SetChecked(checked) ->
      tagged("set_checked", [#("value", json.bool(checked))])
    SelectOption(value) ->
      tagged("select_option", [#("value", json.string(value))])
    Hover -> tagged("hover", [])
    Focus -> tagged("focus", [])
    ScrollIntoView -> tagged("scroll_into_view", [])
    TextContent -> tagged("text_content", [])
    InnerText -> tagged("inner_text", [])
    InnerHtml -> tagged("inner_html", [])
    InputValue -> tagged("input_value", [])
    GetAttribute(name) ->
      tagged("get_attribute", [#("value", json.string(name))])
    Count -> tagged("count", [])
    AllTextContents -> tagged("all_text_contents", [])
    IsVisible -> tagged("is_visible", [])
    IsChecked -> tagged("is_checked", [])
    IsEnabled -> tagged("is_enabled", [])
    Expect(condition) ->
      tagged("expect", [#("condition", condition_to_json(condition))])
    Screenshot -> tagged("screenshot", [])
  }
}

/// Read the reply of a puppet script, a failed action has a reason.
pub fn reply(data: Dynamic) -> Result(Reply, String) {
  case decode.run(data, reply_decoder()) {
    Ok(reply) -> reply
    Error(_) -> Error("Unexpected reply from artifact")
  }
}

fn reply_decoder() {
  use type_ <- decode.field("type", decode.string)
  case type_ {
    "done" -> decode.success(Ok(Done))
    "missing" -> decode.success(Ok(Missing))
    "text" -> decode.field("value", decode.string, ok(Value))
    "texts" -> decode.field("value", decode.list(decode.string), ok(Values))
    "count" -> decode.field("value", decode.int, ok(Number))
    "flag" -> decode.field("value", decode.bool, ok(Flag))
    "error" ->
      decode.field("value", decode.string, fn(reason) {
        decode.success(Error(reason))
      })
    "image" ->
      decode.field("value", decode.string, fn(url) {
        case image(url) {
          Ok(bytes) -> decode.success(Ok(Image(bytes)))
          Error(Nil) -> decode.failure(Error("image"), "PNG data URL")
        }
      })
    _ -> decode.failure(Ok(Done), "reply type")
  }
}

fn ok(constructor) {
  fn(value) { decode.success(Ok(constructor(value))) }
}

fn image(url) {
  case url {
    "data:image/png;base64," <> encoded -> bit_array.base64_decode(encoded)
    _ -> Error(Nil)
  }
}

/// The value a program resumes with.
pub fn to_value(reply: Result(Reply, String)) -> v.Value(a, b) {
  case reply {
    Ok(Done) -> v.ok(v.Tagged("Done", v.unit()))
    Ok(Value(text)) -> v.ok(v.Tagged("Text", v.String(text)))
    Ok(Values(texts)) ->
      v.ok(v.Tagged("Texts", v.LinkedList(list.map(texts, v.String))))
    Ok(Number(count)) -> v.ok(v.Tagged("Count", v.Integer(count)))
    Ok(Flag(flag)) -> v.ok(v.Tagged("Flag", v.bool(flag)))
    Ok(Missing) -> v.ok(v.Tagged("Missing", v.unit()))
    Ok(Image(bytes)) -> v.ok(v.Tagged("Image", v.Binary(bytes)))
    Error(reason) -> v.error(v.String(reason))
  }
}

/// Attributes that identify the preview frame of a panel.
pub fn frame_attributes(item: artifact.Item) -> List(#(String, String)) {
  case item {
    artifact.Artifact(name) -> [
      #("data-artifact", name),
      #("data-version", "latest"),
    ]
    artifact.Revision(name, version) -> [
      #("data-artifact", name),
      #("data-version", int.to_string(version)),
    ]
    artifact.History(..) | artifact.Diff(..) -> []
  }
}

/// A selector for the preview of a shown panel.
pub fn frame_selector(
  store: artifact.Store,
  item: artifact.Item,
) -> Result(String, String) {
  let shown = list.any(store.panels, fn(panel) { panel.item == item })
  case shown, frame_attributes(item) {
    True, [_, ..] as attributes ->
      Ok(
        "iframe.artifact-preview"
        <> string.concat(
          list.map(attributes, fn(attribute) {
            "[" <> attribute.0 <> "=" <> css_string(attribute.1) <> "]"
          }),
        ),
      )
    _, _ ->
      Error(artifact.title(item) <> " is not shown, use Show before Puppet")
  }
}

fn css_string(value) {
  let escaped =
    value
    |> string.replace("\\", "\\\\")
    |> string.replace("\"", "\\\"")
    |> string.replace("\n", "\\a ")
  "\"" <> escaped <> "\""
}

pub const instructions =
  "
# Checking and controlling artifacts
Puppet({page, locator, action, timeout}) drives a shown preview like Playwright and returns Ok(reply) or Error(reason).
page is Artifact(name) or Revision({name, version}) and must already be shown. timeout is in milliseconds, 5000 is typical.
locator is a list of steps narrowing from the whole page []: Css(selector), Text(text), Role({role, name}), Label(text), Placeholder(text), TestId(id), HasText(text), Nth(index).
These actions wait for exactly one visible element: Click({}), Fill(text), Press(key), SetChecked(True({})), SelectOption(value), Hover({}), Focus({}), ScrollIntoView({}).
These wait for one element: TextContent({}), InnerText({}), InnerHtml({}), InputValue({}), GetAttribute(name).
These return at once: Count({}), AllTextContents({}), IsVisible({}), IsChecked({}), IsEnabled({}).
Expect(condition) retries until the timeout: ToHaveText(text), ToContainText(text), ToHaveCount(n), ToBeVisible({}), ToBeHidden({}), ToHaveValue(text), ToHaveAttribute({name, value}), ToBeChecked(True({})).
Replies are Done({}), Text(text), Texts(list), Count(n), Flag(bool), Missing({}) or Image(png).
Screenshot({}) replies Image(png) of the locator or visible page, the latest screenshots are shown to you with the tool result.
After creating an artifact, check it works and looks right with Puppet.
"
