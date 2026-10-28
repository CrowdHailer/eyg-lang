import gleam/json
import hashi/board
import shared/hashi

/// Four islands in the corners of a 3 by 3 grid, solved by a double bridge
/// along the top, y = 0, and single bridges down the right and along the bottom.
pub fn corners() {
  load(
    "{\"width\":3,\"height\":3,\"islands\":[[0,0],[2,0],[2,2],[0,2]],\"connections\":[[[0,0],[[[2,0],2]]],[[2,0],[[[0,0],2],[[2,2],1]]],[[2,2],[[[2,0],1],[[0,2],1]]],[[0,2],[[[2,2],1]]]]}",
  )
}

/// Two pairs of islands whose bridges would cross in the middle.
pub fn cross() {
  load(
    "{\"width\":3,\"height\":3,\"islands\":[[1,0],[1,2],[0,1],[2,1]],\"connections\":[[[1,0],[[[1,2],1]]],[[1,2],[[[1,0],1]]],[[0,1],[[[2,1],1]]],[[2,1],[[[0,1],1]]]]}",
  )
}

fn load(raw) {
  let assert Ok(puzzle) = json.parse(raw, hashi.decoder())
  board.new(puzzle)
}
