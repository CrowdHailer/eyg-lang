import eygir/expression as e
import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

fn label_decoder(for) {
  use label <- decode.field("l", decode.string)
  decode.success(for(label))
}

pub fn decoder() {
  use switch <- decode.field("0", decode.string)
  case switch {
    "v" -> label_decoder(e.Variable)
    "f" -> {
      use label <- decode.field("l", decode.string)
      use body <- decode.field("b", decoder())
      decode.success(e.Lambda(label, body))
    }
    "a" -> {
      use function <- decode.field("f", decoder())
      use argument <- decode.field("a", decoder())
      decode.success(e.Apply(function, argument))
    }
    "l" -> {
      use label <- decode.field("l", decode.string)
      use value <- decode.field("v", decoder())
      use then <- decode.field("t", decoder())
      decode.success(e.Let(label, value, then))
    }

    "x" -> {
      use encoded <- decode.field("v", decode.string)
      case bit_array.base64_decode(encoded) {
        Ok(bytes) -> decode.success(e.Binary(bytes))
        Error(Nil) -> decode.failure(e.Vacant, "base64")
      }
    }
    "i" -> {
      use value <- decode.field("v", decode.int)
      decode.success(e.Integer(value))
    }
    "s" -> {
      use value <- decode.field("v", decode.string)
      decode.success(e.Str(value))
    }
    "ta" -> decode.success(e.Tail)
    "c" -> decode.success(e.Cons)
    "z" -> decode.success(e.Vacant)
    "u" -> decode.success(e.Empty)
    "e" -> label_decoder(e.Extend)
    "g" -> label_decoder(e.Select)
    "o" -> label_decoder(e.Overwrite)
    "t" -> label_decoder(e.Tag)
    "m" -> label_decoder(e.Case)
    "n" -> decode.success(e.NoCases)
    "p" -> label_decoder(e.Perform)
    "h" -> label_decoder(e.Handle)
    "b" -> label_decoder(e.Builtin)
    "#" -> label_decoder(e.Reference)
    "@" -> {
      use package <- decode.field("p", decode.string)
      use release <- decode.field("r", decode.int)
      decode.success(e.NamedReference(package, release))
    }
    _ -> {
      // io.debug(switch)
      decode.failure(e.Vacant, "valid node key")
    }
  }
}

pub fn decode(json) {
  decode.run(json, decoder())
}

pub fn decode_dynamic_error(json) {
  decode(json)
  |> result.map_error(fn(errors) {
    list.map(errors, fn(error) {
      let decode.DecodeError(expected, found, path) = error
      dynamic.DecodeError(expected, found, path)
    })
  })
}

pub fn from_json(raw) {
  json.parse(raw, decoder())
}
