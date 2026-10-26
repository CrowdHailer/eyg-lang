//// https://nodejs.org/api/tty.html

import plinthx/node/process.{type Process}

pub type ReadStream

pub type WriteStream

pub type ResizeEvent

@external(javascript, "./process_ffi.mjs", "get")
pub fn get() -> Result(Process, Nil)

@external(javascript, "./process_ffi.mjs", "stdin")
pub fn stdin(process: Process) -> ReadStream

@external(javascript, "./process_ffi.mjs", "stdout")
pub fn stdout(process: Process) -> WriteStream

/// Streams without terminal support have no isTTY property.
@external(javascript, "./process_ffi.mjs", "isTTY")
pub fn is_read_tty(stream: ReadStream) -> Bool

@external(javascript, "./process_ffi.mjs", "isRaw")
pub fn is_raw(stream: ReadStream) -> Bool

@external(javascript, "./process_ffi.mjs", "setRawMode")
pub fn set_raw_mode(stream: ReadStream, mode: Bool) -> ReadStream

@external(javascript, "./process_ffi.mjs", "resume")
pub fn resume(stream: ReadStream) -> ReadStream

@external(javascript, "./process_ffi.mjs", "pause")
pub fn pause(stream: ReadStream) -> ReadStream

/// Subscribe to input. Call the returned function to remove this listener.
@external(javascript, "./process_ffi.mjs", "onData")
pub fn on_data(stream: ReadStream, callback: fn(BitArray) -> Nil) -> fn() -> Nil

/// Switch the stream to UTF-8 text, buffering characters split across reads.
/// Use instead of `on_data`; returns a function that removes the listener.
@external(javascript, "./process_ffi.mjs", "onText")
pub fn on_text(stream: ReadStream, callback: fn(String) -> Nil) -> fn() -> Nil

@external(javascript, "./process_ffi.mjs", "onEnd")
pub fn on_end(stream: ReadStream, callback: fn() -> Nil) -> fn() -> Nil

@external(javascript, "./process_ffi.mjs", "onError")
pub fn on_read_error(
  stream: ReadStream,
  callback: fn(String) -> Nil,
) -> fn() -> Nil

@external(javascript, "./process_ffi.mjs", "onError")
pub fn on_write_error(
  stream: WriteStream,
  callback: fn(String) -> Nil,
) -> fn() -> Nil

@external(javascript, "./process_ffi.mjs", "isTTY")
pub fn is_write_tty(stream: WriteStream) -> Bool

@external(javascript, "./process_ffi.mjs", "columns")
pub fn columns(stream: WriteStream) -> Int

@external(javascript, "./process_ffi.mjs", "rows")
pub fn rows(stream: WriteStream) -> Int

@external(javascript, "./process_ffi.mjs", "onResize")
pub fn on_resize(
  stream: WriteStream,
  callback: fn(ResizeEvent) -> Nil,
) -> fn() -> Nil
