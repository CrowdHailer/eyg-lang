//// https://nodejs.org/api/tty.html

import plinthx/node/stream.{type Stream}

/// Streams without terminal support have no isTTY property.
@external(javascript, "./process_ffi.mjs", "isTTY")
pub fn is_tty(stream: Stream) -> Result(Bool, Nil)
