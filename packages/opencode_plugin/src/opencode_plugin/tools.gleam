//// Host tool schemas and native values as EYG effect descriptions and fields.

import gleam/dict
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/javascript/array
import gleam/list
import gleam/option.{None}
import gleam/result
import gleam/string
import plinthx/javascript/foreign

const lowercase = "abcdefghijklmnopqrstuvwxyz0123456789"

pub fn label(name: String) {
  name
  |> string.to_graphemes
  |> list.map(fn(letter) {
    case string.contains(lowercase, string.lowercase(letter)) {
      True -> letter
      False -> " "
    }
  })
  |> string.concat
  |> string.split(" ")
  |> list.filter(fn(word) { word != "" })
  |> list.map(fn(word) {
    let assert Ok(#(first, rest)) = string.pop_grapheme(word)
    string.uppercase(first) <> rest
  })
  |> string.concat
}

pub fn snake(name: String) {
  do_snake(string.to_graphemes(name), False, [])
}

fn do_snake(letters, previous_lower, acc) {
  case letters {
    [] -> acc |> list.reverse |> string.concat
    [letter, ..rest] -> {
      let lower = string.lowercase(letter)
      let prefix = case previous_lower && lower != letter {
        True -> "_"
        False -> ""
      }
      do_snake(rest, string.contains(lowercase, letter), [
        prefix <> lower,
        ..acc
      ])
    }
  }
}

fn read(value, name, decoder, default) {
  decode.run(value, decode.field(name, decoder, decode.success))
  |> result.unwrap(default)
}

fn first(schema) {
  read(schema, "anyOf", decode.list(decode.dynamic), [])
  |> list.first
  |> result.unwrap(schema)
}

fn items(schema) {
  let value = read(schema, "items", decode.dynamic, foreign.to_dynamic(Nil))
  case decode.run(value, decode.list(decode.dynamic)) {
    Ok(items) -> list.first(items) |> result.unwrap(foreign.to_dynamic(Nil))
    Error(_) -> value
  }
}

/// Display schema types to the model. Optional record fields have a ? suffix.
pub fn type_(definition: Dynamic) -> String {
  let schema = first(definition)
  let kind = read(schema, "type", decode.dynamic, foreign.to_dynamic(Nil))
  let kind = case decode.run(kind, decode.string) {
    Ok(kind) -> kind
    Error(_) ->
      decode.run(kind, decode.list(decode.string))
      |> result.unwrap([])
      |> list.first
      |> result.unwrap("")
  }
  let properties =
    read(
      schema,
      "properties",
      decode.dict(decode.string, decode.dynamic),
      dict.new(),
    )
  let is_object = kind == "object" || properties != dict.new()
  case kind {
    "string" -> "String"
    "integer" | "number" -> "Integer"
    "boolean" -> "True({}) | False({})"
    "array" -> "List(" <> type_(items(schema)) <> ")"
    _ if is_object -> {
      let required = read(schema, "required", decode.list(decode.string), [])
      let fields =
        properties
        |> dict.to_list
        |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
        |> list.map(fn(field) {
          let #(name, definition) = field
          let optional = case list.contains(required, name) {
            True -> ""
            False -> "?"
          }
          snake(name) <> optional <> ": " <> type_(definition)
        })
      "{" <> string.join(fields, ", ") <> "}"
    }
    _ -> "Any"
  }
}

fn nullish(value) {
  decode.run(value, decode.optional(decode.dynamic)) == Ok(None)
}

fn object(fields) {
  foreign.object(array.from_list(fields))
}

/// Map nested snake case fields back to the tool's schema, omitting null fields.
pub fn argument(value: Dynamic, definition: Dynamic) -> Dynamic {
  case foreign.is_uint8_array(value) {
    True -> value
    False ->
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(values) ->
          values
          |> list.map(argument(_, items(first(definition))))
          |> array.from_list
          |> foreign.to_dynamic
        Error(_) ->
          case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
            Error(_) -> value
            Ok(fields) -> {
              let properties =
                read(
                  first(definition),
                  "properties",
                  decode.dict(decode.string, decode.dynamic),
                  dict.new(),
                )
              fields
              |> dict.to_list
              |> list.filter_map(fn(field) {
                let #(key, value) = field
                case nullish(value) {
                  True -> Error(Nil)
                  False -> {
                    let name =
                      dict.keys(properties)
                      |> list.find(fn(name) { snake(name) == key })
                      |> result.unwrap(key)
                    let schema =
                      dict.get(properties, name)
                      |> result.unwrap(foreign.to_dynamic(Nil))
                    Ok(#(name, argument(value, schema)))
                  }
                }
              })
              |> object
            }
          }
      }
  }
}

/// Structured tool replies use snake case names recursively.
pub fn result(value: Dynamic) -> Dynamic {
  case foreign.is_uint8_array(value) {
    True -> value
    False ->
      case decode.run(value, decode.list(decode.dynamic)) {
        Ok(values) ->
          values |> list.map(result) |> array.from_list |> foreign.to_dynamic
        Error(_) ->
          case decode.run(value, decode.dict(decode.string, decode.dynamic)) {
            Error(_) -> value
            Ok(fields) ->
              fields
              |> dict.to_list
              |> list.map(fn(field) { #(snake(field.0), result(field.1)) })
              |> object
          }
      }
  }
}
