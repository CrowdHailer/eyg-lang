// IMPORTS ---------------------------------------------------------------------

import gleam/dynamic.{type DecodeError as DynamicError, type Dynamic}
import gleam/function
import gleam/json.{type DecodeError as JsonError, type Json}
import gleam/list
import gleam/dict.{type Dict}
import gleam/option.{type Option}
import gleam/pair
import gleam/result
import gleam/string_builder.{type StringBuilder}
import gleam/int

// TYPES -----------------------------------------------------------------------

// TODO why opaque
/// A `Codec` describes both an encoder and a decoder for a given type. For example,
/// under the hood the `int` codec looks like this:
///
/// ```gleam
/// pub fn int() -> Codec(Int) {
///   Codec(
///     encode: json.int,
///     decode: dynamic.int
///   )
/// }
/// ```
///
/// Why is this useful? Writing decoders and encoders is tedious. Gleam doesn't
/// have any metaprogramming features to derive or generate these for us, so we're
/// stuck writing them. With `Codec`s you only need to write them once to get both
/// an encoder and a decoder!
///
/// Importantly, the codec API means our encoders and decoders stay _isomorphic_.
/// That is, we can guarantee that the conversions to JSON and from `Dynamic` are
/// always in sync. 
///
pub type Codec(a) {
  Codec(
    encode: fn(a) -> Json,
    decode: fn(Dynamic) -> Result(a, List(DynamicError)),
  )
}

///
///
pub opaque type Builder(match, a) {
  Builder(match: match, decoder: Dict(String, Decoder(a)))
}

///
///
pub type Encoder(a) =
  fn(a) -> Json

///
///
pub type Decoder(a) =
  fn(Dynamic) -> Result(a, List(DynamicError))

// CONSTRUCTORS ----------------------------------------------------------------

///
///
pub fn from(encode: Encoder(a), decode: Decoder(a)) -> Codec(a) {
  Codec(encode, decode)
}

///
///
pub fn succeed(a: a) -> Codec(a) {
  Codec(encode: fn(_) { json.null() }, decode: fn(_) { Ok(a) })
}

///
///
pub fn fail(err: DynamicError) -> Codec(a) {
  Codec(encode: fn(_) { json.null() }, decode: fn(_) { Error([err]) })
}

fn container(
  codec: Codec(inner),
  encode: fn(Encoder(inner)) -> Encoder(outer),
  decode: fn(Decoder(inner)) -> Decoder(outer),
) -> Codec(outer) {
  Codec(encode: encode(codec.encode), decode: decode(codec.decode))
}

// CONSTRUCTORS: PRIMITIVES ----------------------------------------------------

///
///
pub fn int() -> Codec(Int) {
  Codec(encode: json.int, decode: dynamic.int)
}

///
///
pub fn float() -> Codec(Float) {
  Codec(encode: json.float, decode: dynamic.float)
}

///
///
pub fn string() -> Codec(String) {
  Codec(encode: json.string, decode: dynamic.string)
}

// CONSTRUCTORS: CONTAINERS ----------------------------------------------------

///
///
pub fn list(codec: Codec(a)) -> Codec(List(a)) {
  container(codec, fn(inner) { json.array(_, inner) }, dynamic.list)
}

///
///
pub fn optional(codec: Codec(a)) -> Codec(Option(a)) {
  container(codec, fn(inner) { json.nullable(_, inner) }, dynamic.optional)
}

///
///
pub fn object(codec: Codec(a)) -> Codec(Dict(String, a)) {
  let encoder = fn(inner) {
    fn(map) {
      map
      |> dict.to_list
      |> list.map(pair.map_second(_, inner))
      |> json.object
    }
  }
  container(codec, encoder, dynamic.map(dynamic.string, _))
}

// CONSTRUCTORS: CUSTOM TYPES --------------------------------------------------

///
///
pub fn custom1(
  match: fn(a, value) -> Json,
) -> Builder(fn(a) -> fn(value) -> Json, value) {
  Builder(function.curry2(match), dict.new())
}

///
///
pub fn custom2(
  match: fn(a, b, value) -> Json,
) -> Builder(fn(a) -> fn(b) -> fn(value) -> Json, value) {
  Builder(function.curry3(match), dict.new())
}

///
///
pub fn custom3(
  match: fn(a, b, c, value) -> Json,
) -> Builder(fn(a) -> fn(b) -> fn(c) -> fn(value) -> Json, value) {
  Builder(function.curry4(match), dict.new())
}

fn variant(
  builder: Builder(fn(a) -> b, value),
  tag: String,
  matcher: fn(fn(List(Json)) -> Json) -> a,
  decoder: Decoder(value),
) -> Builder(b, value) {
  let encode = fn(vals) {
    let fields = list.index_map(vals, fn(i, json) { #(int.to_string(i), json) })
    let tag = #("$", json.string(tag))

    json.object([tag, ..fields])
  }

  Builder(
    match: builder.match(matcher(encode)),
    decoder: dict.insert(builder.decoder, tag, decoder),
  )
}

///
///
pub fn variant0(
  builder: Builder(fn(Json) -> a, value),
  tag: String,
  value: value,
) -> Builder(a, value) {
  variant(builder, tag, fn(f) { f([]) }, fn(_) { Ok(value) })
}

///
///
pub fn variant1(
  builder: Builder(fn(fn(a) -> Json) -> b, value),
  tag: String,
  value: fn(a) -> value,
  codec: Codec(a),
) -> Builder(b, value) {
  variant(builder, tag, fn(f) { fn(a) { f([encode_json(a, codec)]) } }, fn(dyn) {
    dyn
    |> dynamic.field("0", codec.decode)
    |> result.map(value)
  })
}

///
///
pub fn variant2(
  builder: Builder(fn(fn(a, b) -> Json) -> c, value),
  tag: String,
  value: fn(a, b) -> value,
  codec_a: Codec(a),
  codec_b: Codec(b),
) -> Builder(c, value) {
  variant(
    builder,
    tag,
    fn(f) { fn(a, b) { f([encode_json(a, codec_a), encode_json(b, codec_b)]) } },
    dynamic.decode2(
      value,
      dynamic.field("0", codec_a.decode),
      dynamic.field("1", codec_b.decode),
    ),
  )
}

///
///
pub fn construct(builder: Builder(fn(a) -> Json, a)) -> Codec(a) {
  Codec(encode: builder.match, decode: fn(dyn) {
    dyn
    |> dynamic.field("$", dynamic.string)
    |> result.then(fn(tag) {
      case dict.get(builder.decoder, tag) {
        Ok(decoder) -> decoder(dyn)
        Error(_) -> Error([])
      }
    })
  })
}

// QUERIES ---------------------------------------------------------------------

///
///
pub fn encoder(codec: Codec(a)) -> Encoder(a) {
  codec.encode
}

///
///
pub fn decoder(codec: Codec(a)) -> Decoder(a) {
  codec.decode
}

// MANIPULATIONS ---------------------------------------------------------------

///
///
pub fn then(
  codec: Codec(a),
  from: fn(b) -> a,
  to: fn(a) -> Codec(b),
) -> Codec(b) {
  Codec(
    encode: fn(b) {
      let a = from(b)
      codec.encode(a)
    },
    decode: fn(a) {
      codec.decode(a)
      |> result.map(to)
      |> result.then(fn(codec) { codec.decode(a) })
    },
  )
}

///
///
pub fn map(codec: Codec(a), from: fn(b) -> a, to: fn(a) -> b) -> Codec(b) {
  use a <- then(codec, from)
  succeed(to(a))
}

// CONVERSIONS -----------------------------------------------------------------

///
///
pub fn encode_json(value: a, codec: Codec(a)) -> Json {
  codec.encode(value)
}

///
///
pub fn encode_string(value: a, codec: Codec(a)) -> String {
  codec.encode(value)
  |> json.to_string
}

///
///
pub fn encode_string_builder(value: a, codec: Codec(a)) -> StringBuilder {
  codec.encode(value)
  |> json.to_string_builder
}

///
///
pub fn decode_string(json: String, codec: Codec(a)) -> Result(a, JsonError) {
  json.decode(json, codec.decode)
}

///
///
pub fn decode_dynamic(
  dynamic: Dynamic,
  codec: Codec(a),
) -> Result(a, List(DynamicError)) {
  codec.decode(dynamic)
}
