//// A box is stored as its events, each one records a new file system root.

import multiformats/cid/v1

/// The state of a box after the event with this sequence.
pub type Box {
  Box(name: String, sequence: Int, root: v1.Cid)
}
