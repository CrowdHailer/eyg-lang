import eygir/annotated as e
import gleam/bit_array
import gleam/dynamic
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

fn label_decoder(for, meta) {
  use label <- decode.field("l", decode.string)
  decode.success(#(for(label), meta))
}

pub fn decoder(meta) {
  use switch <- decode.field("0", decode.string)
  case switch {
    "v" -> label_decoder(e.Variable, meta)
    "f" -> {
      use label <- decode.field("l", decode.string)
      use body <- decode.field("b", decoder(meta))
      decode.success(#(e.Lambda(label, body), meta))
    }
    "a" -> {
      use function <- decode.field("f", decoder(meta))
      use argument <- decode.field("a", decoder(meta))
      decode.success(#(e.Apply(function, argument), meta))
    }
    "l" -> {
      use label <- decode.field("l", decode.string)
      use value <- decode.field("v", decoder(meta))
      use then <- decode.field("t", decoder(meta))
      decode.success(#(e.Let(label, value, then), meta))
    }

    "x" -> {
      use encoded <- decode.field("v", decode.string)
      case bit_array.base64_decode(encoded) {
        Ok(bytes) -> decode.success(#(e.Binary(bytes), meta))
        Error(Nil) -> decode.failure(#(e.Vacant, meta), "base64")
      }
    }
    "i" -> {
      use value <- decode.field("v", decode.int)
      decode.success(#(e.Integer(value), meta))
    }
    "s" -> {
      use value <- decode.field("v", decode.string)
      decode.success(#(e.String(value), meta))
    }
    "ta" -> decode.success(#(e.Tail, meta))
    "c" -> decode.success(#(e.Cons, meta))
    "z" -> decode.success(#(e.Vacant, meta))
    "u" -> decode.success(#(e.Empty, meta))
    "e" -> label_decoder(e.Extend, meta)
    "g" -> label_decoder(e.Select, meta)
    "o" -> label_decoder(e.Overwrite, meta)
    "t" -> label_decoder(e.Tag, meta)
    "m" -> label_decoder(e.Case, meta)
    "n" -> decode.success(#(e.NoCases, meta))
    "p" -> label_decoder(e.Perform, meta)
    "h" -> label_decoder(e.Handle, meta)
    "b" -> label_decoder(e.Builtin, meta)
    "#" -> label_decoder(e.Reference, meta)
    "@" -> {
      use package <- decode.field("p", decode.string)
      use release <- decode.field("r", decode.int)
      decode.success(#(e.NamedReference(package, release), meta))
    }
    _ -> {
      // io.debug(switch)
      decode.failure(#(e.Vacant, meta), "valid node key")
    }
  }
}

pub fn decode(json) {
  decode.run(json, decoder(Nil))
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
  json.parse(raw, decoder(Nil))
}
