//// Synchronous hashing for browser recording and replay.

import sha256 as portable

pub fn hash(bytes: BitArray) -> BitArray {
  portable.hash(bytes)
}
