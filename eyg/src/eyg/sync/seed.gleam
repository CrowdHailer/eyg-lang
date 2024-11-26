import eyg/sync/sync
import eyg/topological as topo
import eygir/annotated
import filepath
import gleam/list
import gleam/listx
import gleam/pair
import gleam/result
import midas/task as t

pub fn from_dir(root_dir) {
  use libs <- t.do(read_seeds(root_dir))
  use libs <- t.try(
    list.try_map(libs, fn(lib) {
      let #(org, name, bytes) = lib
      use source <- result.try(sync.decode_bytes(bytes))
      let references =
        annotated.add_annotation(source, Nil)
        |> annotated.list_references
      let key = "@" <> org <> "." <> name
      // io.debug(key)
      // io.debug(references)

      // let assert Ok(content) = bit_array.to_string(bytes)
      // let cid = "h" <> cid.hash_code(content)
      let path = filepath.join("/references/", key <> ".json")
      #(key, #(references, #(path, bytes)))
      |> Ok
    }),
  )
  let graph = listx.value_map(libs, pair.first)
  use ordered <- t.try(topo.sort(graph) |> result.map_error(topo.to_snag))
  list.map(ordered, fn(key) {
    let assert Ok(#(_, #(path, bytes))) = list.key_find(libs, key)
    #(path, bytes)
  })
  |> t.done()
}

fn read_seeds(root_dir) {
  use orgs <- t.do(t.list(root_dir))
  use output <- t.do(
    t.sequential(
      list.map(orgs, fn(org) {
        let org_dir = filepath.join(root_dir, org)
        use files <- t.do(t.list(org_dir))
        t.sequential(
          list.map(files, fn(file) {
            use bytes <- t.do(t.read(filepath.join(org_dir, file)))
            let name = filepath.strip_extension(file)
            t.done(#(org, name, bytes))
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
