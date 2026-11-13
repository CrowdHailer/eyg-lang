//// Small typed helpers for plain native SDK data. No SDK state is kept here.

import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/list
import gleam/result
import plinthx/javascript/foreign

pub fn object(fields: List(#(String, Dynamic))) {
  foreign.object(array.from_list(fields))
}

pub fn data(value: a) {
  foreign.to_dynamic(value)
}

pub fn call(target: Dynamic, name: String, arguments: List(Dynamic)) {
  foreign.call(target, name, array.from_list(arguments))
}

pub fn field(value: Dynamic, name: String) {
  decode.run(value, decode.field(name, decode.dynamic, decode.success))
  |> result.unwrap(data(Nil))
}

pub fn text(value: Dynamic) {
  decode.run(value, decode.string) |> result.unwrap("")
}

pub fn string(value: Dynamic, name: String) {
  text(field(value, name))
}

pub fn list(value: Dynamic) {
  decode.run(value, decode.list(decode.dynamic)) |> result.unwrap([])
}

pub fn bool(value: Dynamic) {
  decode.run(value, decode.bool) |> result.unwrap(False)
}

pub fn array(values: List(Dynamic)) {
  data(array.from_list(values))
}

pub fn fail(text: String) {
  foreign.raise(foreign.error(text))
}

pub fn joined_text(content: Dynamic) {
  list(content)
  |> list.filter_map(fn(part) {
    case string(part, "type") {
      "text" -> Ok(string(part, "text"))
      _ -> Error(Nil)
    }
  })
  |> gleam_string_join
}

pub fn tool_text(content: Dynamic) {
  list(content)
  |> list.map(fn(part) {
    case string(part, "type") {
      "text" -> string(part, "text")
      kind -> "[" <> kind <> "]"
    }
  })
  |> gleam_string_join
}

fn gleam_string_join(items) {
  list.fold(items, "", fn(acc, text) {
    case acc {
      "" -> text
      _ -> acc <> "\n" <> text
    }
  })
}
