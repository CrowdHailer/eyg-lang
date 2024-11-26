import eyg/sync/cid
import filepath
import gleam/bit_array
import gleam/list
import midas/task as t

pub fn from_dir(root_dir) {
  use orgs <- t.do(t.list(root_dir))
  use output <- t.do(
    t.sequential(
      list.map(orgs, fn(org) {
        let org_dir = filepath.join(root_dir, org)
        use libs <- t.do(t.list(org_dir))
        t.sequential(
          list.map(libs, fn(lib) {
            use bytes <- t.do(t.read(filepath.join(org_dir, lib)))
            // don't validate as hashes are unique such that invalid content doesn't clash
            let assert Ok(content) = bit_array.to_string(bytes)
            let cid = "h" <> cid.hash_code(content)
            let path = filepath.join("/references", cid <> ".json")
            use Nil <- t.do(t.log(
              "org: " <> org <> ", lib: " <> lib <> ", path: " <> path,
            ))
            t.done(#(path, bytes))
          }),
        )
      }),
    ),
  )
  output
  |> list.flatten()
  |> list.unique()
  |> t.done()
}
