import cloud/data/blobs
import cloud/session/session

pub fn access_file_test() {
  let assert Ok(blobs) = blobs.start()
  let blobs = blobs.data

  let code = "perform ReadFile({path: \"/\", offset: 0, limit: 1000000})"
  // fork is a true false query
  session.begin(Nil, code, blobs)
  |> echo
  todo
}
