//// Native image and Canvas 2D APIs.

import gleam/javascript/promise.{type Promise}
import plinthx/browser/node.{type Node}

pub type Image

pub type Context

@external(javascript, "./canvas_ffi.mjs", "image")
pub fn image(url: String) -> Promise(Result(Image, String))

@external(javascript, "./canvas_ffi.mjs", "context")
pub fn context(node: Node) -> Context

@external(javascript, "./canvas_ffi.mjs", "fillStyle")
pub fn fill_style(context: Context, color: String) -> Nil

@external(javascript, "./canvas_ffi.mjs", "fillRect")
pub fn fill_rect(
  context: Context,
  x: Float,
  y: Float,
  width: Float,
  height: Float,
) -> Nil

@external(javascript, "./canvas_ffi.mjs", "drawImage")
pub fn draw_image(
  context: Context,
  image: Image,
  sx: Float,
  sy: Float,
  sw: Float,
  sh: Float,
  dx: Float,
  dy: Float,
  dw: Float,
  dh: Float,
) -> Nil

@external(javascript, "./canvas_ffi.mjs", "toDataUrl")
pub fn to_data_url(node: Node) -> Result(String, String)

@external(javascript, "./canvas_ffi.mjs", "encodePng")
pub fn encode_png(node: Node) -> Promise(Result(String, String))
