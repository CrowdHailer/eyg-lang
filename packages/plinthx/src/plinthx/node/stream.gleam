//// Native Node readable and writable streams.

pub type Stream

@external(javascript, "./stream_ffi.mjs", "setEncoding")
pub fn set_encoding(stream: Stream, encoding: String) -> Result(Nil, String)

@external(javascript, "./stream_ffi.mjs", "onData")
pub fn on_data(
  stream: Stream,
  callback: fn(String) -> Nil,
) -> Result(Nil, String)

@external(javascript, "./stream_ffi.mjs", "offData")
pub fn off_data(
  stream: Stream,
  callback: fn(String) -> Nil,
) -> Result(Nil, String)

@external(javascript, "./stream_ffi.mjs", "resume")
pub fn resume(stream: Stream) -> Result(Nil, String)

@external(javascript, "./stream_ffi.mjs", "pause")
pub fn pause(stream: Stream) -> Result(Nil, String)
