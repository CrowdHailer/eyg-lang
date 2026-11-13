//// Acquire an immutable artifact without changing the workspace.

import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/cast
import eyg/interpreter/value as v
import gleam/dict
import gleam/option.{type Option}
import gleam/result

pub const label = "Acquire"

pub type Source {
  Git(url: String, ref: Option(String))
  Http(url: String)
}

pub type Input {
  Input(source: Source, expected: Option(String))
}

pub type Receipt {
  Receipt(root: String, resolved: String)
}

pub fn source_type() {
  t.union([
    #("Git", t.record([#("url", t.String), #("ref", t.option(t.String))])),
    #("Http", t.record([#("url", t.String)])),
  ])
}

pub fn lift() {
  t.record([#("source", source_type()), #("expected", t.option(t.String))])
}

pub fn lower() {
  t.result(t.record([#("root", t.String), #("resolved", t.String)]), t.String)
}

pub fn decode_source(value) {
  cast.as_variant(value, [
    #("Git", fn(value) {
      use url <- result.try(cast.field("url", cast.as_string, value))
      use ref <- result.map(cast.field(
        "ref",
        cast.as_option(_, cast.as_string),
        value,
      ))
      Git(url, ref)
    }),
    #("Http", fn(value) {
      result.map(cast.field("url", cast.as_string, value), Http)
    }),
  ])
}

pub fn decode(value) {
  use source <- result.try(cast.field("source", decode_source, value))
  use expected <- result.map(cast.field(
    "expected",
    cast.as_option(_, cast.as_string),
    value,
  ))
  Input(source, expected)
}

pub fn source_value(source: Source) -> v.Value(m, c) {
  case source {
    Git(url, ref) ->
      v.Tagged(
        "Git",
        v.Record(
          dict.from_list([
            #("url", v.String(url)),
            #("ref", v.option(ref, v.String)),
          ]),
        ),
      )
    Http(url) ->
      v.Tagged("Http", v.Record(dict.from_list([#("url", v.String(url))])))
  }
}

pub fn input_value(input: Input) -> v.Value(m, c) {
  v.Record(
    dict.from_list([
      #("source", source_value(input.source)),
      #("expected", v.option(input.expected, v.String)),
    ]),
  )
}

pub fn encode(reply: Result(Receipt, String)) -> v.Value(m, c) {
  case reply {
    Ok(Receipt(root, resolved)) ->
      v.ok(
        v.Record(
          dict.from_list([
            #("root", v.String(root)),
            #("resolved", v.String(resolved)),
          ]),
        ),
      )
    Error(reason) -> v.error(v.String(reason))
  }
}
