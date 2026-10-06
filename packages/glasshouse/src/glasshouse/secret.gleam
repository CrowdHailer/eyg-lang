//// Keep secret values out of recordings.
////
//// A secret mounted into a program is registered with the recorder.
//// Every occurrence of its value in a recorded string or UTF-8 binary is replaced with a placeholder.
//// Replaying with a substitute value applies the same redaction,
//// so requests built from the substitute match the recorded requests.

import eyg/interpreter/value as v
import eyg/ir/tree as ir
import gleam/bit_array
import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string

pub type Secret {
  Secret(name: String, value: String)
}

/// The text recorded in place of a secret.
pub fn placeholder(name: String) -> String {
  "⟦secret:" <> name <> "⟧"
}

/// A substitute used to replay a run without the real secret.
pub fn dummy(name: String) -> Secret {
  Secret(name:, value: "dummy-secret-" <> name)
}

/// Replace secret values with placeholders.
pub fn redact(value: v.Value(m, c), secrets: List(Secret)) -> v.Value(m, c) {
  let replacements =
    secrets
    |> list.filter(fn(secret) { secret.value != "" })
    // Longest first so a secret containing another is replaced whole.
    |> list.sort(fn(a, b) {
      int.compare(string.length(b.value), string.length(a.value))
    })
    |> list.map(fn(secret) { #(secret.value, placeholder(secret.name)) })
  substitute(value, replacements)
}

/// Replace placeholders with the given secret values.
pub fn restore(value: v.Value(m, c), secrets: List(Secret)) -> v.Value(m, c) {
  let replacements =
    list.map(secrets, fn(secret) { #(placeholder(secret.name), secret.value) })
  substitute(value, replacements)
}

/// Environment variables whose names suggest a credential are treated as secrets.
pub fn is_credential_variable(name: String) -> Bool {
  let name = string.uppercase(name)
  list.any(
    ["TOKEN", "SECRET", "PASSWORD", "CREDENTIAL", "API_KEY", "APIKEY"],
    fn(word) { string.contains(name, word) },
  )
}

/// The name a secret read from an environment variable is recorded under.
pub fn variable_name(name: String) -> String {
  "env:" <> name
}

/// Credential strings in JSON files and OAuth replies, including a nested token set.
/// Other fields and values are left alone; callers supply a stable source name.
pub fn in_json(bytes: BitArray, source: String) -> List(Secret) {
  let fields = decode.dict(decode.string, decode.dynamic)
  case json.parse_bits(bytes, fields) {
    Error(_) -> []
    Ok(values) -> {
      let nested =
        ["tokens", "credentials"]
        |> list.flat_map(fn(key) {
          case dict.get(values, key) {
            Error(Nil) -> []
            Ok(value) ->
              case decode.run(value, fields) {
                Error(_) -> []
                Ok(values) -> json_fields(values, source <> ":" <> key)
              }
          }
        })
      list.append(json_fields(values, source), nested)
    }
  }
}

fn json_fields(values, source) {
  dict.to_list(values)
  |> list.filter_map(fn(field) {
    let #(key, value) = field
    case
      list.contains(
        [
          "access_token",
          "refresh_token",
          "id_token",
          "secret_access_key",
          "api_key",
          "password",
          "token",
          "client_secret",
        ],
        string.lowercase(key),
      )
      || key == "OPENAI_API_KEY"
    {
      False -> Error(Nil)
      True ->
        case decode.run(value, decode.string) {
          Ok("") | Error(_) -> Error(Nil)
          Ok(value) -> Ok(Secret("json:" <> source <> ":" <> key, value))
        }
    }
  })
}

/// Does a string contain any of the secret values.
pub fn reveals(text: String, secrets: List(Secret)) -> Bool {
  list.any(secrets, fn(secret) {
    secret.value != "" && string.contains(text, secret.value)
  })
}

fn substitute(value, replacements) {
  case replacements {
    [] -> value
    _ -> do_substitute(value, replacements)
  }
}

fn do_substitute(value, replacements) {
  case value {
    v.String(text) -> v.String(replace_all(text, replacements))
    v.Binary(bytes) ->
      case bit_array.to_string(bytes) {
        Ok(text) -> {
          let replaced = replace_all(text, replacements)
          case replaced == text {
            True -> value
            False -> v.Binary(bit_array.from_string(replaced))
          }
        }
        Error(Nil) -> value
      }
    v.LinkedList(items) ->
      v.LinkedList(list.map(items, do_substitute(_, replacements)))
    v.Record(fields) ->
      v.Record(
        dict.map_values(fields, fn(_, item) {
          do_substitute(item, replacements)
        }),
      )
    v.Tagged(label, inner) ->
      v.Tagged(label, do_substitute(inner, replacements))
    v.Partial(switch, applied) ->
      v.Partial(switch, list.map(applied, do_substitute(_, replacements)))
    v.Closure(parameter, body, environment) -> {
      let used = ir.free_variables(body, [parameter])
      let body =
        ir.rewrite_pure(body, fn(node) {
          case node.0 {
            ir.String(text) -> #(
              ir.String(replace_all(text, replacements)),
              node.1,
            )
            ir.Binary(bytes) -> {
              let assert v.Binary(bytes) =
                do_substitute(v.Binary(bytes), replacements)
              #(ir.Binary(bytes), node.1)
            }
            expression -> #(expression, node.1)
          }
        })
      let environment =
        list.map(environment, fn(entry) {
          case list.contains(used, entry.0) {
            True -> #(entry.0, do_substitute(entry.1, replacements))
            False -> entry
          }
        })
      v.Closure(parameter, body, environment)
    }
    v.Table(facts, rules) ->
      v.Table(
        dict.map_values(facts, fn(_, rows) {
          list.map(rows, do_substitute(_, replacements))
        }),
        list.map(rules, do_substitute(_, replacements)),
      )
    v.Integer(_) -> value
  }
}

fn replace_all(text, replacements) {
  list.fold(replacements, text, fn(text, replacement) {
    let #(from, to) = replacement
    string.replace(text, from, to)
  })
}
