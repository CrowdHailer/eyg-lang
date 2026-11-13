//// Bun stream consumers: https://bun.sh/docs/api/streams

import gleam/javascript/promise.{type Promise}
import plinthx/browser/readable_stream.{type ReadableStream}
import plinthx/bun/runtime.{type Bun}

@external(javascript, "./streams_ffi.mjs", "toText")
pub fn to_text(
  bun: Bun,
  stream: ReadableStream,
) -> Promise(Result(String, String))
