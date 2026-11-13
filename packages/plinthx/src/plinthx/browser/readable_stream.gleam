//// Streams: https://streams.spec.whatwg.org/#rs-class

pub type ReadableStream

import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option}

pub type TextReader

@external(javascript, "./readable_stream_ffi.mjs", "getTextReader")
pub fn get_text_reader(stream: ReadableStream) -> Result(TextReader, String)

@external(javascript, "./readable_stream_ffi.mjs", "readText")
pub fn read_text(reader: TextReader) -> Promise(Result(Option(String), String))
