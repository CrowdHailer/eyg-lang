//// Node filesystem: https://nodejs.org/api/fs.html#fsmkdtempsyncprefix-options

import gleam/javascript/promise.{type Promise}

@external(javascript, "./fs_ffi.mjs", "temporaryDirectory")
pub fn temporary_directory(prefix: String) -> Result(String, String)

/// Read at most `length` bytes without blocking the JavaScript event loop.
@external(javascript, "./fs_ffi.mjs", "read")
pub fn read(fd: Int, length: Int) -> Promise(Result(BitArray, String))
