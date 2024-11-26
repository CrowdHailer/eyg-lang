import eyg/sync/cid
import filepath
import gleam/bit_array
import gleam/io
import gleam/list
import midas/task as t

pub fn from_dir(root_dir) {
  use libs <- t.do(read_seeds(root_dir))
  list.map(libs, fn(lib) {
    let #(_org, _name, bytes) = lib
    let assert Ok(content) = bit_array.to_string(bytes)
    let cid = "h" <> cid.hash_code(content)
    let path = filepath.join("/references", cid <> ".json")
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
        use libs <- t.do(t.list(org_dir))
        t.sequential(
          list.map(libs, fn(lib) {
            use bytes <- t.do(t.read(filepath.join(org_dir, lib)))
            t.done(#(org, lib, bytes))
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

pub fn topo(graph) {
  // For each node if it's not already in the results do a depth first search
  list.try_fold(graph, [], fn(output, el) {
    let #(node, children) = el
    case list.contains(output, node) {
      True -> Ok(output)
      False -> dfs(node, children, [], graph, output)
    }
  })
}

fn dfs(node, children, path, graph, output) {
  let #(path, check) = list.split_while(path, fn(x) { x != node })
  case check {
    [] -> {
      let path = [node, ..path]
      let result =
        list.try_fold(children, output, fn(output, child) {
          case list.contains(output, child) {
            True -> Ok(output)
            False -> {
              let assert Ok(children) = list.key_find(graph, child)
              dfs(child, children, path, graph, output)
            }
          }
        })
      case result {
        Ok(output) -> Ok([node, ..output])
        Error(reason) -> Error(reason)
      }
    }
    _ -> Error([node, ..list.reverse(path)] |> list.append([node]))
  }
}
