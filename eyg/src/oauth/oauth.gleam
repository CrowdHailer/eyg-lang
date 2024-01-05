import gleam/string
import gleam/uri.{Uri}

fn join_path(root, sub_path) {
  let Uri(path: root_path, ..) = root
  let path = string.append(root_path, sub_path)
  Uri(..root, path: root_path)
}

fn implicit_grant_flow(root, path) {
  let response_type = "token"
  todo
}
// fn run()  {
//     let #(url, k) = implicit_grant_flow()
//     redirect
//     fetch
//     // use resp <- result.then(send_request)

// }
