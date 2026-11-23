//// Reading request bodies and writing responses for the JSON API.

import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/http/response.{type Response}
import gleam/json.{type Json}
import howdy/content.{type Content}
import howdy/context
import howdy/controller

/// The largest body a request can send, files are written in one request.
const limit = 8_000_000

pub fn read_bits(
  ctx: controller.Context,
  then: fn(BitArray) -> Response(Content),
) -> Response(Content) {
  case controller.read_body(ctx, limit:) {
    Ok(body) -> then(body)
    Error(context.BodyTooLarge) -> status(413)
    Error(context.InvalidBody) -> status(400)
  }
}

pub fn read_text(
  ctx: controller.Context,
  then: fn(String) -> Response(Content),
) -> Response(Content) {
  use body <- read_bits(ctx)
  case bit_array.to_string(body) {
    Ok(text) -> then(text)
    Error(Nil) -> status(400)
  }
}

pub fn read_json(
  ctx: controller.Context,
  then: fn(Dynamic) -> Response(Content),
) -> Response(Content) {
  use body <- read_bits(ctx)
  case json.parse_bits(body, decode.dynamic) {
    Ok(value) -> then(value)
    Error(_) -> status(400)
  }
}

pub fn json(body: Json, status: Int) -> Response(Content) {
  response.new(status)
  |> response.set_header("content-type", "application/json; charset=utf-8")
  |> response.set_body(content.Text(json.to_string(body)))
}

/// A response with no body.
pub fn status(status: Int) -> Response(Content) {
  response.new(status)
  |> response.set_body(content.Empty)
}
