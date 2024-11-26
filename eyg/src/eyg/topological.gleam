import gleam/list
import gleam/string
import snag

pub fn sort(graph) {
  // For each node if it's not already in the results do a depth first search
  list.try_fold(graph, [], fn(output, el) {
    let #(node, children) = el
    case list.contains(output, node) {
      True -> Ok(output)
      False -> dfs(node, children, [], graph, output)
    }
  })
}

pub type Reason(a) {
  DependencyCycle(List(a))
  MissingNode(a)
}

pub fn to_snag(reason) {
  case reason {
    DependencyCycle(cycle) ->
      "cycle detected: "
      <> cycle |> list.map(string.inspect) |> string.join(" -> ")
    MissingNode(node) -> "missing node: " <> string.inspect(node)
  }
  |> snag.new
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
              case list.key_find(graph, child) {
                Ok(children) -> dfs(child, children, path, graph, output)
                Error(Nil) -> Error(MissingNode(child))
              }
            }
          }
        })
      case result {
        Ok(output) -> Ok([node, ..output])
        Error(reason) -> Error(reason)
      }
    }
    _ ->
      Error(DependencyCycle([node, ..list.reverse(path)] |> list.append([node])))
  }
}
