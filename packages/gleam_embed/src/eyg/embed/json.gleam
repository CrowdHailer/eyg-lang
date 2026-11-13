//// EYG values and types as plain JSON, for hosts that are not written in Gleam.
////
//// Integers are numbers, strings are strings, lists are arrays, records are
//// objects, `True({})` and `False({})` are booleans, and any other tag is
//// `{"$": "Ok", "value": ...}`, where a missing value is the empty record.
////
//// Types are `"integer"`, `"string"`, `"boolean"`, `"unit"`, `{"list": T}`,
//// `{"record": {"name": T}}`, `{"union": {"Tag": T}}` or
//// `{"result": {"ok": T, "error": T}}`.

import eyg/analysis/type_/binding
import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/integer
import gleam/dict
import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/result

/// Decode a type from its JSON description.
pub fn type_decoder() -> decode.Decoder(binding.Mono) {
  // Dispatch on the key, `decode.field` runs its decoder on a placeholder when
  // the field is missing, which never ends for a recursive decoder.
  decode.one_of(decode.string |> decode.then(named_type), [
    decode.dict(decode.string, decode.dynamic)
    |> decode.then(fn(object) {
      case dict.to_list(object) {
        [#("list", item)] -> nested(item, type_decoder(), t.List)
        [#("record", fields)] ->
          nested(fields, decode.dict(decode.string, type_decoder()), fn(fields) {
            t.record(dict.to_list(fields))
          })
        [#("union", variants)] ->
          nested(
            variants,
            decode.dict(decode.string, type_decoder()),
            fn(variants) { t.union(dict.to_list(variants)) },
          )
        [#("result", inner)] ->
          nested(inner, decode.dict(decode.string, type_decoder()), fn(parts) {
            case
              dict.size(parts),
              dict.get(parts, "ok"),
              dict.get(parts, "error")
            {
              2, Ok(ok), Ok(error) -> t.result(ok, error)
              _, _, _ -> t.Never
            }
          })
        _ -> decode.failure(t.unit, "type")
      }
    }),
  ])
}

fn named_type(name) {
  case name {
    "integer" -> decode.success(t.Integer)
    "string" -> decode.success(t.String)
    "boolean" -> decode.success(t.boolean)
    "unit" -> decode.success(t.unit)
    _ -> decode.failure(t.unit, "type")
  }
}

fn nested(data, decoder, wrap) {
  case decode.run(data, decoder) {
    Ok(inner) ->
      case wrap(inner) {
        t.Never -> decode.failure(t.unit, "type")
        type_ -> decode.success(type_)
      }
    Error(_) -> decode.failure(t.unit, "type")
  }
}

/// Decode effects, `{"Label": {"lift": T, "lower": T}}`.
pub fn effects_decoder() {
  decode.dict(decode.string, {
    use lift <- decode.field("lift", type_decoder())
    use lower <- decode.field("lower", type_decoder())
    decode.success(#(lift, lower))
  })
  |> decode.map(dict.to_list)
}

/// A value as JSON, functions cannot be.
pub fn to_json(value: state.Value(m)) -> Result(Json, String) {
  let unit = v.unit()
  case value {
    v.Integer(i) ->
      case integer.is_safe(i) {
        True -> Ok(json.int(i))
        False -> Error("integer is outside the JavaScript safe range")
      }
    v.String(s) -> Ok(json.string(s))
    v.Binary(_) -> Error("binary values cannot be passed as JSON")
    v.Tagged("True", inner) if inner == unit -> Ok(json.bool(True))
    v.Tagged("False", inner) if inner == unit -> Ok(json.bool(False))
    v.Tagged(label, inner) -> {
      use inner <- result.map(to_json(inner))
      json.object([#("$", json.string(label)), #("value", inner)])
    }
    v.LinkedList(items) ->
      list.try_map(items, to_json) |> result.map(json.preprocessed_array)
    v.Record(fields) -> {
      use Nil <- result.try(case dict.has_key(fields, "$") {
        True -> Error("$ is reserved for tagged JSON values")
        False -> Ok(Nil)
      })
      dict.to_list(fields)
      |> list.try_map(fn(field) {
        let #(key, value) = field
        use value <- result.map(to_json(value))
        #(key, value)
      })
      |> result.map(json.object)
    }
    _ -> Error("a function cannot be passed to the host")
  }
}

/// Decode a value from JSON, without knowing its type.
pub fn value_decoder() -> decode.Decoder(state.Value(m)) {
  use <- decode.recursive
  decode.one_of(
    decode.int
      |> decode.then(fn(i) {
        case integer.is_safe(i) {
          True -> decode.success(v.Integer(i))
          False -> decode.failure(v.unit(), "safe integer")
        }
      }),
    [
      decode.string |> decode.map(v.String),
      decode.bool |> decode.map(v.bool),
      decode.list(value_decoder()) |> decode.map(v.LinkedList),
      decode.dict(decode.string, decode.dynamic)
        |> decode.then(fn(fields) {
          case dict.get(fields, "$") {
            Error(_) -> {
              let values =
                list.try_map(dict.to_list(fields), fn(field) {
                  use value <- result.map(decode.run(field.1, value_decoder()))
                  #(field.0, value)
                })
              case values {
                Ok(values) -> decode.success(v.Record(dict.from_list(values)))
                Error(_) -> decode.failure(v.unit(), "record of EYG values")
              }
            }
            Ok(label) -> {
              use label <- decode.then(case decode.run(label, decode.string) {
                Ok(label) -> decode.success(label)
                Error(_) -> decode.failure("", "tag label")
              })
              case dict.get(fields, "value"), dict.size(fields) {
                Error(_), 1 -> decode.success(v.Tagged(label, v.unit()))
                Ok(inner), 2 ->
                  case decode.run(inner, value_decoder()) {
                    Ok(value) -> decode.success(v.Tagged(label, value))
                    Error(_) -> decode.failure(v.unit(), "tag payload")
                  }
                _, _ ->
                  decode.failure(
                    v.unit(),
                    "tagged value with only $ and optional value",
                  )
              }
            }
          }
        }),
    ],
  )
}

/// Check a decoded host reply against the closed type offered to the program.
/// Call this before resuming; decoding alone does not enforce the declared type.
pub fn conforms(value: state.Value(m), type_: binding.Mono) -> Bool {
  case type_, value {
    t.Integer, v.Integer(i) -> integer.is_safe(i)
    t.String, v.String(_) -> True
    t.List(item), v.LinkedList(items) -> list.all(items, conforms(_, item))
    t.Record(rows), v.Record(fields) -> {
      let rows = rows_of(rows)
      list.length(rows) == dict.size(fields)
      && list.all(rows, fn(row) {
        let #(label, type_) = row
        case dict.get(fields, label) {
          Ok(value) -> conforms(value, type_)
          Error(Nil) -> False
        }
      })
    }
    t.Union(rows), v.Tagged(label, inner) ->
      case list.key_find(rows_of(rows), label) {
        Ok(type_) -> conforms(inner, type_)
        Error(Nil) -> False
      }
    _, _ -> False
  }
}

fn rows_of(rows) {
  case rows {
    t.RowExtend(label, type_, rest) -> [#(label, type_), ..rows_of(rest)]
    _ -> []
  }
}
