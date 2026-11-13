//// Node filesystem: https://nodejs.org/api/fs.html

import gleam/javascript/promise.{type Promise}

/// Read at most `length` bytes without blocking the JavaScript event loop.
@external(javascript, "./fs_ffi.mjs", "read")
pub fn read(fd: Int, length: Int) -> Promise(Result(BitArray, String))
